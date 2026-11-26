#!/usr/bin/env python3
"""Smoke-test the release archives of one target on a machine that can run them (used by CI on native runners).

    python3 tools/ci_smoke.py linux-x86_64-gnu [--dist capi/dist]

Unpacks the C API package and the CLI package, renders with both CLIs (outputs must be byte-identical), and compiles +
runs the C test suite against the static and (where possible) shared library, using `zig cc` for the target.
"""
import argparse, os, shutil, subprocess, sys, tarfile, tempfile, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "capi"))
import build  # noqa: E402  (TARGETS, version)


def unpack(dist, base, dest):
    for ext, opener in ((".tar.gz", tarfile.open), (".zip", zipfile.ZipFile)):
        p = os.path.join(dist, base + ext)
        if os.path.exists(p):
            with opener(p) as a: a.extractall(dest)
            return os.path.join(dest, base)
    sys.exit(f"missing archive {base}.(tar.gz|zip) in {dist}")


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode: sys.exit(f"FAILED: {' '.join(map(str, cmd))}\n{r.stdout}\n{r.stderr}")
    return r


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("target"); ap.add_argument("--dist", default=os.path.join(ROOT, "capi", "dist"))
    a = ap.parse_args()
    zt, _, _, kind = build.TARGETS[a.target]; ver = build.version(); exe = ".exe" if kind == "windows" else ""
    tmp = tempfile.mkdtemp(prefix="nimaid-smoke-")
    capi = unpack(a.dist, f"nimaid-capi-{ver}-{a.target}", tmp); cli = unpack(a.dist, f"nimaid-cli-{ver}-{a.target}", tmp)
    c_cli, n_cli = os.path.join(capi, "bin", "nimaid" + exe), os.path.join(cli, "nimaid" + exe)
    for p in (c_cli, n_cli): os.chmod(p, 0o755)
    for p in (c_cli, n_cli): assert ver in run([p, "--version"]).stdout, f"{p}: wrong version"
    ex = os.path.join(ROOT, "docs", "examples")
    n = 0
    for f in sorted(os.listdir(ex)):
        if not f.endswith(".mmd"): continue
        for ext in ("png", "svg"):
            o1, o2 = os.path.join(tmp, f"a_{f}.{ext}"), os.path.join(tmp, f"b_{f}.{ext}")
            run([n_cli, os.path.join(ex, f), o1]); run([c_cli, os.path.join(ex, f), o2])
            assert open(o1, "rb").read() == open(o2, "rb").read(), f"Nim CLI and C API CLI differ on {f}.{ext}"
            n += 1
    print(f"ok: {n} renders identical between the Nim CLI and the C API CLI")
    zig = [shutil.which("zig")] if shutil.which("zig") else [sys.executable, "-m", "ziglang"]
    test_c = os.path.join(ROOT, "capi", "tests", "test_capi.c"); inc = "-I" + os.path.join(capi, "include")
    libm = [] if kind in ("windows", "macos") else ["-lm"]
    modes = [("static", [os.path.join(capi, "lib", "libnimaid.a"), *libm], [])]
    if "musl" not in a.target and kind != "freebsd":
        if kind == "windows": modes.append(("shared", [os.path.join(capi, "lib", "nimaid.lib")], ["-DNIMAID_SHARED"]))
        elif kind == "macos": modes.append(("shared", ["-L" + os.path.join(capi, "lib"), "-lnimaid", "-Wl,-rpath," + os.path.join(capi, "lib")], []))
        else: modes.append(("shared", ["-L" + os.path.join(capi, "lib"), "-lnimaid", "-Wl,-rpath," + os.path.join(capi, "lib")], []))
    for mode, link, defs in modes:
        out = os.path.join(tmp, f"test_{mode}{exe}")
        run(zig + ["cc", "-target", zt, "-O1", *defs, inc, test_c, *link, "-o", out])
        if mode == "shared" and kind == "windows": shutil.copy(os.path.join(capi, "bin", "nimaid.dll"), tmp)
        r = run([out], cwd=tmp); assert "passed" in r.stdout, r.stdout
        print(f"ok: C test suite ({mode})")
    print(f"smoke test passed for {a.target}")


if __name__ == "__main__":
    main()
