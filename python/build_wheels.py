#!/usr/bin/env python3
"""Build the PyPI wheels from the cross-compiled C API archives (capi/dist).

    python3 capi/build.py                 # 1. cross-compile every target (needs Nim + `pip install ziglang`)
    python3 python/build_wheels.py        # 2. -> python/dist/*.whl   (no extra tools needed)
    pip install twine && twine check python/dist/*  &&  twine upload python/dist/*

One wheel per platform (the shared library is loaded with ctypes, so the wheels are tagged py3-none-<platform>
and work on every Python >= 3.8), plus `nimaid-noto-emoji` (Noto Color Emoji, py3-none-any).
"""
import argparse, base64, glob, hashlib, io, os, re, stat, sys, tarfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# capi target -> (wheel platform tags, path of the shared library inside the archive, filename in the wheel)
PLATFORMS = {
    "linux-x86_64-gnu":       (["manylinux_2_17_x86_64", "manylinux2014_x86_64"],   "lib/libnimaid.so",    "libnimaid.so"),
    "linux-aarch64-gnu":      (["manylinux_2_17_aarch64", "manylinux2014_aarch64"], "lib/libnimaid.so",    "libnimaid.so"),
    "linux-armv7-gnueabihf":  (["manylinux_2_17_armv7l", "manylinux2014_armv7l"],   "lib/libnimaid.so",    "libnimaid.so"),
    "linux-x86-gnu":          (["manylinux_2_17_i686", "manylinux2014_i686"],       "lib/libnimaid.so",    "libnimaid.so"),
    "linux-x86_64-musl":      (["musllinux_1_2_x86_64"],                            "lib/libnimaid.so",    "libnimaid.so"),
    "linux-aarch64-musl":     (["musllinux_1_2_aarch64"],                           "lib/libnimaid.so",    "libnimaid.so"),
    "linux-armv7-musleabihf": (["musllinux_1_2_armv7l"],                            "lib/libnimaid.so",    "libnimaid.so"),
    "macos-x86_64":           (["macosx_11_0_x86_64"],                              "lib/libnimaid.dylib", "libnimaid.dylib"),
    "macos-aarch64":          (["macosx_11_0_arm64"],                               "lib/libnimaid.dylib", "libnimaid.dylib"),
    "windows-x86_64":         (["win_amd64"],                                       "bin/nimaid.dll",      "nimaid.dll"),
    "windows-aarch64":        (["win_arm64"],                                       "bin/nimaid.dll",      "nimaid.dll"),
    "windows-x86":            (["win32"],                                           "bin/nimaid.dll",      "nimaid.dll"),
}  # not built as wheels: linux-riscv64-gnu, freebsd-x86_64 (no stable wheel tag / PyPI support)

CLASSIFIERS = [
    "Development Status :: 4 - Beta", "Intended Audience :: Developers", "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3", "Programming Language :: Python :: 3 :: Only",
    "Programming Language :: Python :: 3.8", "Programming Language :: Python :: 3.9", "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11", "Programming Language :: Python :: 3.12", "Programming Language :: Python :: 3.13",
    "Operating System :: POSIX :: Linux", "Operating System :: MacOS", "Operating System :: Microsoft :: Windows",
    "Topic :: Multimedia :: Graphics", "Topic :: Software Development :: Documentation", "Typing :: Typed",
]
URLS = [("Homepage", "https://github.com/ghazalialshafi/nimaid"),
        ("Documentation", "https://github.com/ghazalialshafi/nimaid/tree/main/capi/docs"),
        ("Issues", "https://github.com/ghazalialshafi/nimaid/issues")]


def version():
    return re.search(r'__version__ = "([^"]+)"', open(os.path.join(HERE, "src", "nimaid", "__init__.py")).read()).group(1)


def metadata(name, ver, summary, readme, extra_lines=()):
    lines = ["Metadata-Version: 2.1", f"Name: {name}", f"Version: {ver}", f"Summary: {summary}",
             "Keywords: mermaid,diagram,flowchart,sequence,svg,png,gif,render,nim", "Author: Ghazali", "License: MIT",
             "Requires-Python: >=3.8", "Description-Content-Type: text/markdown"]
    lines += [f"Project-URL: {k}, {v}" for k, v in URLS] + [f"Classifier: {c}" for c in CLASSIFIERS] + list(extra_lines)
    return "\n".join(lines) + "\n\n" + open(readme, encoding="utf-8").read()


def write_wheel(path, files, dist_info, tags, purelib):
    """files: [(arcname, bytes, mode)]; adds WHEEL + RECORD."""
    wheel = ("Wheel-Version: 1.0\nGenerator: nimaid build_wheels.py\n"
             f"Root-Is-Purelib: {'true' if purelib else 'false'}\n" + "".join(f"Tag: py3-none-{t}\n" for t in tags))
    files = files + [(f"{dist_info}/WHEEL", wheel.encode(), 0o644)]
    rec = io.StringIO()
    for arc, data, _ in files:
        digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=").decode()
        rec.write(f"{arc},sha256={digest},{len(data)}\n")
    rec.write(f"{dist_info}/RECORD,,\n")
    files.append((f"{dist_info}/RECORD", rec.getvalue().encode(), 0o644))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for arc, data, mode in files:
            zi = zipfile.ZipInfo(arc, date_time=(2020, 1, 1, 0, 0, 0)); zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (stat.S_IFREG | mode) << 16
            z.writestr(zi, data)


def extract_member(capi_dist, ver, target, member):
    base = f"nimaid-capi-{ver}-{target}"
    tgz, zp = os.path.join(capi_dist, base + ".tar.gz"), os.path.join(capi_dist, base + ".zip")
    if os.path.exists(tgz):
        with tarfile.open(tgz) as t: return t.extractfile(f"{base}/{member}").read()
    if os.path.exists(zp):
        with zipfile.ZipFile(zp) as z: return z.read(f"{base}/{member}")
    raise FileNotFoundError(f"missing {tgz} (run capi/build.py first)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--capi-dist", default=os.path.join(ROOT, "capi", "dist"))
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "dist"))
    ap.add_argument("-t", "--targets", nargs="*", default=list(PLATFORMS))
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    ver = version(); capi_ver = re.search(r'version\s*=\s*"([^"]+)"', open(os.path.join(ROOT, "nimaid.nimble")).read()).group(1)
    assert ver == capi_ver, f"python version {ver} != nimble version {capi_ver}: keep them in sync"
    rd = lambda p, m="rb": open(p, m).read()
    src = [(f"nimaid/{f}", rd(os.path.join(HERE, "src", "nimaid", f)), 0o644)
           for f in ("__init__.py", "_native.py", "_cli.py", "__main__.py", "py.typed")]
    legal = [("LICENSE", rd(os.path.join(ROOT, "LICENSE")), 0o644), ("THIRD_PARTY.md", rd(os.path.join(ROOT, "THIRD_PARTY.md")), 0o644)]
    meta = metadata("nimaid", ver, "Mermaid diagrams to PNG, GIF and SVG. Pure Nim core, no dependencies, no browser.",
                    os.path.join(HERE, "README.md"),
                    ['Provides-Extra: emoji', f'Requires-Dist: nimaid-noto-emoji (>={ver}) ; extra == "emoji"']).encode()
    di = f"nimaid-{ver}.dist-info"
    common = src + [(f"{di}/METADATA", meta, 0o644), (f"{di}/entry_points.txt", b"[console_scripts]\nnimaid = nimaid._cli:main\n", 0o644),
                    (f"{di}/top_level.txt", b"nimaid\n", 0o644)] + [(f"{di}/{n}", d, m) for n, d, m in legal]
    for target in a.targets:
        tags, member, libname = PLATFORMS[target]
        lib = extract_member(a.capi_dist, ver, target, member)
        out = os.path.join(a.out, f"nimaid-{ver}-py3-none-{'.'.join(tags)}.whl")
        write_wheel(out, common + [(f"nimaid/_native/{libname}", lib, 0o755)], di, tags, purelib=False)
        print(f"{os.path.getsize(out)/1e6:6.2f} MB  {os.path.basename(out)}")
    # nimaid-noto-emoji: pure python
    font = os.path.join(ROOT, "fonts", "NotoColorEmoji-Regular.ttf"); ofl = os.path.join(ROOT, "fonts", "OFL-NotoColorEmoji.txt")
    edi = f"nimaid_noto_emoji-{ver}.dist-info"
    emeta = metadata("nimaid-noto-emoji", ver, "Noto Color Emoji font for nimaid (colour emoji in Mermaid diagrams).",
                     os.path.join(HERE, "emoji", "README.md")).replace("License: MIT", "License: SIL OFL 1.1 (font), MIT (code)").encode()
    files = [("nimaid_emoji/__init__.py", rd(os.path.join(HERE, "emoji", "nimaid_emoji", "__init__.py")), 0o644),
             ("nimaid_emoji/NotoColorEmoji-Regular.ttf", rd(font), 0o644), ("nimaid_emoji/OFL.txt", rd(ofl), 0o644),
             (f"{edi}/METADATA", emeta, 0o644), (f"{edi}/top_level.txt", b"nimaid_emoji\n", 0o644),
             (f"{edi}/OFL.txt", rd(ofl), 0o644), (f"{edi}/LICENSE", rd(os.path.join(ROOT, "LICENSE")), 0o644)]
    out = os.path.join(a.out, f"nimaid_noto_emoji-{ver}-py3-none-any.whl")
    write_wheel(out, files, edi, ["any"], purelib=True)
    print(f"{os.path.getsize(out)/1e6:6.2f} MB  {os.path.basename(out)}")


if __name__ == "__main__":
    main()
