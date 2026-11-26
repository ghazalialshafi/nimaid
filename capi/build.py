#!/usr/bin/env python3
"""Cross-compile the nimaid C API for every platform with Nim (C generation) + Zig (C compiler/linker).

    pip install ziglang          # the only extra tool besides Nim >= 2.0
    python3 capi/build.py                       # all targets  -> capi/dist/
    python3 capi/build.py --list
    python3 capi/build.py -t linux-x86_64-musl windows-x86_64
    python3 capi/build.py -t native             # just this machine
    python3 capi/build.py -t wasm32-wasi        # WebAssembly module + JS wrapper (npm package layout)
    python3 capi/build.py --products capi       # only the C API (default: capi + cli)

Each target yields   dist/nimaid-capi-<version>-<target>.(tar.gz|zip)   containing
    include/nimaid.h   lib/libnimaid.a   lib/libnimaid.(so|dylib)  | bin/nimaid.dll + lib/nimaid.lib
    bin/nimaid[.exe] (the CLI built on the C API)   examples/  docs/  README.md  LICENSE  THIRD_PARTY.md
and   dist/nimaid-cli-<version>-<target>.(tar.gz|zip)   the standalone Nim CLI (src/nimaid_cli.nim, font built in)
and   dist/nimaid-wasm-<version>.tar.gz                    nimaid.wasm + nimaid.mjs (npm package layout)
"""
import argparse, concurrent.futures as cf, glob, hashlib, os, platform, re, shutil, struct, subprocess, sys, tarfile, zipfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# name: (zig target, nim --os, nim --cpu, kind)
TARGETS = {
    "linux-x86_64-gnu":     ("x86_64-linux-gnu.2.17",      "linux",   "amd64",   "linux"),
    "linux-aarch64-gnu":    ("aarch64-linux-gnu.2.17",     "linux",   "arm64",   "linux"),
    "linux-armv7-gnueabihf":("arm-linux-gnueabihf.2.17",   "linux",   "arm",     "linux"),
    "linux-x86-gnu":        ("x86-linux-gnu.2.17",         "linux",   "i386",    "linux"),
    "linux-riscv64-gnu":    ("riscv64-linux-gnu.2.27",     "linux",   "riscv64", "linux"),
    "linux-x86_64-musl":    ("x86_64-linux-musl",          "linux",   "amd64",   "linux"),
    "linux-aarch64-musl":   ("aarch64-linux-musl",         "linux",   "arm64",   "linux"),
    "linux-armv7-musleabihf":("arm-linux-musleabihf",      "linux",   "arm",     "linux"),
    "windows-x86_64":       ("x86_64-windows-gnu",         "windows", "amd64",   "windows"),
    "windows-aarch64":      ("aarch64-windows-gnu",        "windows", "arm64",   "windows"),
    "windows-x86":          ("x86-windows-gnu",            "windows", "i386",    "windows"),
    "macos-x86_64":         ("x86_64-macos.11.0",          "macosx",  "amd64",   "macos"),
    "macos-aarch64":        ("aarch64-macos.11.0",         "macosx",  "arm64",   "macos"),
    "freebsd-x86_64":       ("x86_64-freebsd",             "freebsd", "amd64",   "freebsd"),
    "wasm32-wasi":          ("wasm32-wasi",                "linux",   "wasm32",  "wasm"),
}
NIM_COMMON = ["--app:lib", "--noMain", "-d:release", "--mm:orc", "--threads:off", "--hints:off", "--warnings:off"]
WASM_NIM = ["-d:useMalloc", "--exceptions:goto", "-d:noSignalHandler"]   # no mmap / setjmp in WASI

def native_name():
    m = platform.machine().lower(); sysn = platform.system().lower()
    arch = {"x86_64": "x86_64", "amd64": "x86_64", "arm64": "aarch64", "aarch64": "aarch64"}.get(m, m)
    if sysn == "linux": return f"linux-{arch}-gnu"
    if sysn == "darwin": return f"macos-{arch}"
    if sysn == "windows": return f"windows-{arch}"
    return None

def version():
    return re.search(r'version\s*=\s*"([^"]+)"', open(os.path.join(ROOT, "nimaid.nimble")).read()).group(1)

def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode:
        raise RuntimeError(f"command failed ({r.returncode}): {' '.join(map(str, cmd))}\n{r.stdout[-3000:]}\n{r.stderr[-3000:]}")
    return r

def find_zig():
    z = shutil.which("zig")
    if z: return [z]
    try:
        import ziglang  # noqa
        return [sys.executable, "-m", "ziglang"]
    except ImportError:
        sys.exit("zig not found: run  pip install ziglang")

def pe_exports(path):
    """Names exported by a PE DLL (to verify that only the public API is exported)."""
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec = struct.unpack_from("<H", d, pe + 6)[0]; optsz = struct.unpack_from("<H", d, pe + 20)[0]
    opt = pe + 24; magic = struct.unpack_from("<H", d, opt)[0]
    rva, _ = struct.unpack_from("<II", d, opt + (112 if magic == 0x20B else 96))
    secs = [struct.unpack_from("<4xIIII", d, opt + optsz + 40 * i + 8 - 4)[0:4] for i in range(nsec)]
    def off(r):
        for vsz, va, rsz, ptr in [(s[0], s[1], s[2], s[3]) for s in secs]:
            if va <= r < va + max(vsz, rsz): return r - va + ptr
    if not rva: return []
    e = off(rva); n = struct.unpack_from("<I", d, e + 24)[0]; names = off(struct.unpack_from("<I", d, e + 32)[0])
    out = []
    for i in range(n):
        o = off(struct.unpack_from("<I", d, names + 4 * i)[0]); out.append(d[o:d.index(b"\0", o)].decode())
    return out

class Builder:
    def __init__(self, a):
        self.a = a; self.zig = find_zig(); self.ver = version()
        self.nim = a.nim or shutil.which("nim") or sys.exit("nim not found (use --nim /path/to/nim)")
        self.nimlib = self.find_nim_lib()
        self.build = os.path.join(HERE, "build"); self.dist = os.path.abspath(a.out)
        os.makedirs(self.build, exist_ok=True); os.makedirs(self.dist, exist_ok=True)

    def find_nim_lib(self):
        """Directory holding nimbase.h: ask the compiler (`nim dump`), fall back to <nim>/../lib."""
        try:
            import json
            lp = json.loads(run([self.nim, "dump", "--dump.format:json", "--hints:off", "."], cwd=ROOT).stdout)["libpath"]
            if os.path.exists(os.path.join(lp, "nimbase.h")): return lp
        except Exception:
            pass
        lp = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(self.nim))), "lib")
        if not os.path.exists(os.path.join(lp, "nimbase.h")):
            sys.exit(f"cannot find nimbase.h (looked in {lp}); use Nim from the official installer/tarball")
        return lp

    def cc(self, tgt, *args, **kw):
        return run(self.zig + ["cc", "-target", tgt, *args], **kw)

    def zig_cxx(self, tgt, *args):
        return run(self.zig + ["c++", "-target", tgt, "-std=c++11", "-O1", *args])

    def compile_nim(self, name, entry, tag, nim_args, lib_mode):
        """Nim -> C for this exact os/cpu, then C -> objects with zig cc (parallel). Returns the object files."""
        zt, nos, ncpu, kind = TARGETS[name]
        tdir = os.path.join(self.build, name); cache = os.path.join(tdir, tag + "_nimcache"); objd = os.path.join(tdir, tag + "_obj")
        os.makedirs(objd, exist_ok=True)
        extra = WASM_NIM if kind == "wasm" else []
        run([self.nim, "c", "--compileOnly", *nim_args, *extra, f"--os:{nos}", f"--cpu:{ncpu}", f"--nimcache:{cache}",
             *self.a.nim_args, entry], cwd=ROOT)
        if lib_mode:   # keep Nim's runtime entry points out of the public ABI
            main_c = glob.glob(os.path.join(cache, "@mnimaid_capi.nim.c"))[0]
            s = open(main_c).read()
            open(main_c, "w").write(re.sub(r"N_LIB_EXPORT (N_CDECL\(void, (?:NimMain|NimDestroyGlobals)\))", r"N_LIB_PRIVATE \1", s))
        flags = ["-O2", "-w", "-fno-strict-aliasing", "-fwrapv", "-ffunction-sections", "-fdata-sections", "-I" + self.nimlib, "-I" + cache]
        if lib_mode: flags.append("-fvisibility=hidden")
        if kind not in ("windows", "wasm"): flags.append("-fPIC")
        srcs = sorted(glob.glob(os.path.join(cache, "*.c")))
        def one(c):
            o = os.path.join(objd, os.path.basename(c)[:-2] + ".o")
            self.cc(zt, *flags, "-c", c, "-o", o); return o
        with cf.ThreadPoolExecutor(self.a.jobs) as ex: return list(ex.map(one, srcs))

    def build_target(self, name):
        t0 = time.time()
        zt, nos, ncpu, kind = TARGETS[name]
        shutil.rmtree(os.path.join(self.build, name), ignore_errors=True); os.makedirs(os.path.join(self.build, name))
        if kind == "wasm": return name, self.build_wasm(name, t0)
        msgs = []
        capi_exe = None
        if "capi" in self.a.products:
            m, capi_exe = self.build_capi(name, t0); msgs.append(m)
        if "cli" in self.a.products:
            msgs.append(self.build_cli(name, t0, capi_exe))
        return name, "\n      ".join(msgs)

    def build_capi(self, name, t0):
        zt, nos, ncpu, kind = TARGETS[name]
        tdir = os.path.join(self.build, name)
        objs = self.compile_nim(name, os.path.join(HERE, "src", "nimaid_capi.nim"), "capi", NIM_COMMON, True)
        # 3. static + shared + CLI
        pkg = os.path.join(tdir, "pkg"); lib = os.path.join(pkg, "lib"); bindir = os.path.join(pkg, "bin")
        for d in (lib, bindir, os.path.join(pkg, "include")): os.makedirs(d, exist_ok=True)
        run(self.zig + ["ar", "rcs", os.path.join(lib, "libnimaid.a"), *objs])
        strip = [] if kind == "macos" else ["-s"]
        if kind == "windows":
            shared = os.path.join(bindir, "nimaid.dll"); extra = ["-shared", "-Wl,--out-implib," + os.path.join(lib, "nimaid.lib")]
        elif kind == "macos":
            shared = os.path.join(lib, "libnimaid.dylib"); extra = ["-dynamiclib", "-install_name", "@rpath/libnimaid.dylib"]
        else:
            shared = os.path.join(lib, "libnimaid.so"); extra = ["-shared", "-Wl,-soname,libnimaid.so", "-Wl,--gc-sections"]
        self.cc(zt, "-O2", *extra, *strip, "-o", shared, *objs)
        exe = os.path.join(bindir, "nimaid" + (".exe" if kind == "windows" else ""))
        self.cc(zt, "-O2", *strip, "-I" + os.path.join(HERE, "include"), os.path.join(HERE, "examples", "nimaid_cli.c"),
                os.path.join(lib, "libnimaid.a"), "-o", exe)
        for f in glob.glob(os.path.join(bindir, "*.pdb")) + glob.glob(os.path.join(lib, "*.pdb")) + glob.glob(os.path.join(bindir, "*.lib")): os.remove(f)
        for f in glob.glob(os.path.join(lib, "*.lib")):      # keep only the DLL's import library
            if os.path.basename(f) != "nimaid.lib": os.remove(f)
        if kind == "windows": assert os.path.exists(os.path.join(lib, "nimaid.lib")), "import library missing"
        # 4. verify
        info = self.verify(name, kind, pkg, shared, exe)
        # 5. package
        self.assemble(pkg, kind, name)
        arc = self.archive(pkg, name, kind)
        return f"{time.time()-t0:5.1f}s  {os.path.getsize(arc)/1e6:5.2f} MB  {os.path.basename(arc)}  {info}", exe

    def build_cli(self, name, t0, capi_exe):
        """The standalone Nim CLI (src/nimaid_cli.nim) with DejaVu Sans built in."""
        zt, nos, ncpu, kind = TARGETS[name]
        tdir = os.path.join(self.build, name)
        objs = self.compile_nim(name, os.path.join(ROOT, "src", "nimaid_cli.nim"), "cli",
                                ["--app:console", "-d:release", "--mm:orc", "--threads:off", "--hints:off", "--warnings:off", "-d:nimaidEmbedFont"], False)
        base = f"nimaid-cli-{self.ver}-{name}"; pkg = os.path.join(tdir, base); os.makedirs(pkg, exist_ok=True)
        exe = os.path.join(pkg, "nimaid" + (".exe" if kind == "windows" else ""))
        self.cc(zt, "-O2", *([] if kind == "macos" else ["-s"]), "-o", exe, *objs)
        for f in glob.glob(os.path.join(pkg, "*.lib")) + glob.glob(os.path.join(pkg, "*.pdb")): os.remove(f)
        shutil.copy(os.path.join(HERE, "cli-README.md"), os.path.join(pkg, "README.md"))
        for f in ("LICENSE", "THIRD_PARTY.md"): shutil.copy(os.path.join(ROOT, f), pkg)
        shutil.copytree(os.path.join(ROOT, "docs", "examples"), os.path.join(pkg, "examples"), dirs_exist_ok=True)
        info = "built"
        if self.can_run(name):
            cwd = os.path.join(tdir, "clirun"); os.makedirs(cwd, exist_ok=True)
            assert self.ver in run([exe, "--version"]).stdout, "CLI version mismatch"
            for ex in ("01-first", "07-sequence", "09-er", "12-gantt"):
                src = os.path.join(ROOT, "docs", "examples", ex + ".mmd")
                if not os.path.exists(src): continue
                for ext in ("png", "svg"):
                    out = os.path.join(cwd, f"{ex}.{ext}"); run([exe, src, out])
                    if capi_exe:   # the Nim CLI and the C API CLI must agree byte for byte
                        ref = os.path.join(cwd, f"{ex}.c.{ext}"); run([capi_exe, src, ref])
                        assert open(out, "rb").read() == open(ref, "rb").read(), f"CLI differs from C API CLI on {ex}.{ext}"
            info = "CLI == C API CLI (byte-identical on 8 renders)" if capi_exe else "CLI runs"
        arc = self.archive_dir(pkg, base, kind)
        return f"{time.time()-t0:5.1f}s  {os.path.getsize(arc)/1e6:5.2f} MB  {os.path.basename(arc)}  {info}"

    def build_wasm(self, name, t0):
        """nimaid.wasm (WASI reactor) + the JS wrapper, in npm package layout."""
        zt, _, _, _ = TARGETS[name]
        tdir = os.path.join(self.build, name)
        objs = self.compile_nim(name, os.path.join(HERE, "src", "nimaid_capi.nim"), "capi", NIM_COMMON, True)
        pkg = os.path.join(tdir, f"nimaid-wasm-{self.ver}"); os.makedirs(pkg, exist_ok=True)
        names = sorted(set(re.findall(r"proc (nimaid_[a-z_]+)\*", open(os.path.join(HERE, "src", "nimaid_capi.nim")).read())))
        self.cc(zt, "-O2", "-s", "-mexec-model=reactor", "-Wl,--no-entry", "-Wl,-z,stack-size=8388608", "-Wl,--gc-sections",
                *[f"-Wl,--export={n}" for n in names], "-o", os.path.join(pkg, "nimaid.wasm"), *objs)
        for f in ("nimaid.mjs", "index.d.ts", "package.json", "README.md", "demo.html", "test.mjs"):
            shutil.copy(os.path.join(ROOT, "wasm", f), pkg)
        for f in ("LICENSE", "THIRD_PARTY.md"): shutil.copy(os.path.join(ROOT, f), pkg)
        os.makedirs(os.path.join(pkg, "examples"), exist_ok=True)
        for ex in sorted(os.listdir(os.path.join(ROOT, "docs", "examples"))):      # every example: test.mjs renders them all on wasm32
            if ex.endswith(".mmd"): shutil.copy(os.path.join(ROOT, "docs", "examples", ex), os.path.join(pkg, "examples"))
        info = "built"
        node = shutil.which("node")
        if node:
            r = run([node, "test.mjs"], cwd=pkg); assert "passed" in r.stdout, r.stdout
            info = "node tests passed"
        arc = self.archive_dir(pkg, os.path.basename(pkg), "wasm")
        return f"{time.time()-t0:5.1f}s  {os.path.getsize(arc)/1e6:5.2f} MB  {os.path.basename(arc)}  {info}"

    def can_run(self, name):
        return name == native_name() or (platform.system() == "Linux" and platform.machine() == "x86_64" and name == "linux-x86_64-musl")

    def archive_dir(self, pkg, base, kind):
        """Archive an already assembled directory whose name is `base`."""
        if kind == "windows":
            arc = os.path.join(self.dist, base + ".zip")
            with zipfile.ZipFile(arc, "w", zipfile.ZIP_DEFLATED) as z:
                for dp, _, fs in os.walk(pkg):
                    for f in sorted(fs): p = os.path.join(dp, f); z.write(p, os.path.join(base, os.path.relpath(p, pkg)))
        else:
            arc = os.path.join(self.dist, base + ".tar.gz")
            with tarfile.open(arc, "w:gz") as t: t.add(pkg, arcname=base)
        return arc

    def verify(self, name, kind, pkg, shared, exe):
        out = []
        if kind == "windows":
            ex = sorted(pe_exports(shared)); bad = [e for e in ex if not e.startswith("nimaid_")]
            assert ex and not bad, f"unexpected DLL exports: {bad}"
            assert "nimaid_render_png" in ex; out.append(f"{len(ex)} exports")
        if name == native_name() or (name.startswith("linux-x86_64") and platform.system() == "Linux" and platform.machine() == "x86_64"):
            cwd = os.path.join(self.build, name, "run"); os.makedirs(cwd, exist_ok=True)
            zt = TARGETS[name][0]; t = os.path.join(HERE, "tests", "test_capi.c"); inc = "-I" + os.path.join(HERE, "include")
            libd = os.path.join(pkg, "lib")
            modes = [("static", [os.path.join(libd, "libnimaid.a"), "-lm"])]
            if "musl" not in name:   # a musl executable cannot load a shared lib on a glibc host
                modes.append(("shared", ["-L" + libd, "-lnimaid", "-Wl,-rpath," + libd]))
            for mode, extra in modes:
                tb = os.path.join(cwd, "t_" + mode); self.cc(zt, "-O1", inc, t, *extra, "-o", tb)
                r = run([tb], cwd=cwd); assert "passed" in r.stdout, r.stdout
            tb = os.path.join(cwd, "t_cpp"); self.zig_cxx(zt, inc, os.path.join(HERE, "tests", "test_cpp.cpp"), os.path.join(libd, "libnimaid.a"), "-lm", "-o", tb)
            assert "ok" in run([tb], cwd=cwd).stdout
            out.append("C + C++ tests passed (" + "+".join(m for m, _ in modes) + ")")
            r = run([exe, "-v"]); out.append(r.stdout.strip())
        return "; ".join(out) if out else "built"

    def assemble(self, pkg, kind, name):
        shutil.copytree(os.path.join(HERE, "include"), os.path.join(pkg, "include"), dirs_exist_ok=True)
        for sub in ("examples", "docs"): shutil.copytree(os.path.join(HERE, sub), os.path.join(pkg, sub), dirs_exist_ok=True)
        for f in ("README.md", "LICENSE.md"):
            if os.path.exists(os.path.join(HERE, f)): shutil.copy(os.path.join(HERE, f), pkg)
        shutil.copy(os.path.join(ROOT, "LICENSE"), pkg); shutil.copy(os.path.join(ROOT, "THIRD_PARTY.md"), pkg)
        # pkg-config + CMake config (relocatable)
        os.makedirs(os.path.join(pkg, "lib", "pkgconfig"), exist_ok=True)
        libs_priv = "-lm" if kind in ("linux", "freebsd") else ""
        open(os.path.join(pkg, "lib", "pkgconfig", "nimaid.pc"), "w").write(
            f"prefix=${{pcfiledir}}/../..\nlibdir=${{prefix}}/lib\nincludedir=${{prefix}}/include\n\n"
            f"Name: nimaid\nDescription: Mermaid diagrams to PNG/GIF/SVG (C API)\nVersion: {self.ver}\n"
            f"Cflags: -I${{includedir}}\nLibs: -L${{libdir}} -lnimaid\nLibs.private: {libs_priv}\n")
        cm = os.path.join(pkg, "lib", "cmake", "nimaid"); os.makedirs(cm, exist_ok=True)
        open(os.path.join(cm, "nimaid-config.cmake"), "w").write(
            'get_filename_component(_nimaid_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)\n'
            "add_library(nimaid::nimaid STATIC IMPORTED)\n"
            'set_target_properties(nimaid::nimaid PROPERTIES IMPORTED_LOCATION "${_nimaid_root}/lib/libnimaid.a"\n'
            '  INTERFACE_INCLUDE_DIRECTORIES "${_nimaid_root}/include")\n'
            + ('set_property(TARGET nimaid::nimaid APPEND PROPERTY INTERFACE_LINK_LIBRARIES m)\n' if libs_priv else ""))

    def archive(self, pkg, name, kind):
        base = f"nimaid-capi-{self.ver}-{name}"
        stage = os.path.join(self.build, name, base); shutil.rmtree(stage, ignore_errors=True); shutil.copytree(pkg, stage)
        if kind == "windows":
            arc = os.path.join(self.dist, base + ".zip")
            with zipfile.ZipFile(arc, "w", zipfile.ZIP_DEFLATED) as z:
                for dp, _, fs in os.walk(stage):
                    for f in sorted(fs): p = os.path.join(dp, f); z.write(p, os.path.relpath(p, os.path.dirname(stage)))
        else:
            arc = os.path.join(self.dist, base + ".tar.gz")
            with tarfile.open(arc, "w:gz") as t: t.add(stage, arcname=base)
        return arc

    def fonts_archive(self):
        arc = os.path.join(self.dist, f"nimaid-fonts-{self.ver}.tar.gz")
        with tarfile.open(arc, "w:gz") as t: t.add(os.path.join(ROOT, "fonts"), arcname="fonts")
        return arc

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-t", "--targets", nargs="*", default=["all"], help="target names, 'all' or 'native'")
    ap.add_argument("--products", nargs="*", default=["capi", "cli"], choices=["capi", "cli"], help="what to build for native targets (default: both)")
    ap.add_argument("--fonts-only", action="store_true", help="only create the nimaid-fonts archive")
    ap.add_argument("--list", action="store_true"); ap.add_argument("--nim", help="path to the nim executable")
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "dist")); ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--nim-arg", dest="nim_args", action="append", default=[], help="extra argument for nim (e.g. -d:nimaidNoEmbeddedFont)")
    a = ap.parse_args()
    if a.list:
        for n, (z, o, c, k) in TARGETS.items(): print(f"{n:24} {z}")
        return
    if a.fonts_only:
        print("created", Builder(a).fonts_archive()); return
    names = list(TARGETS) if a.targets == ["all"] else [native_name() if t == "native" else t for t in a.targets]
    for n in names:
        if n not in TARGETS: sys.exit(f"unknown target '{n}' (see --list)")
    b = Builder(a); failed = []
    for n in names:
        try:
            _, msg = b.build_target(n); print(f"OK    {n:24} {msg}", flush=True)
        except Exception as e:
            failed.append(n); print(f"FAIL  {n:24} {str(e)[:1500]}", flush=True)
    if len(names) == len(TARGETS): print("fonts", os.path.basename(b.fonts_archive()))
    with open(os.path.join(b.dist, "SHA256SUMS"), "w") as f:
        for p in sorted(glob.glob(os.path.join(b.dist, "nimaid-*"))):
            f.write(f"{hashlib.sha256(open(p, 'rb').read()).hexdigest()}  {os.path.basename(p)}\n")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
