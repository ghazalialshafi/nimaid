#!/usr/bin/env python3
"""Set the version everywhere:  python3 tools/bump_version.py 0.5.0     (no argument: print and verify)"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# file -> regex with one group around the version
SPOTS = {
    "nimaid.nimble": r'^version\s*=\s*"([^"]+)"',
    "src/nimaid.nim": r'const nimaidVersion\* = "([^"]+)"',
    "capi/include/nimaid.h": r'#define NIMAID_VERSION_STRING "([^"]+)"',
    "python/src/nimaid/__init__.py": r'^__version__ = "([^"]+)"',
    "python/emoji/nimaid_emoji/__init__.py": r'^__version__ = "([^"]+)"',
    "wasm/package.json": r'"version":\s*"([^"]+)"',
}
EXTRA = {  # places that merely mention the version; updated together
    "capi/include/nimaid.h": [(r'(#define NIMAID_VERSION_MAJOR )\d+', "{0}"), (r'(#define NIMAID_VERSION_MINOR )\d+', "{1}"),
                              (r'(#define NIMAID_VERSION_PATCH )\d+', "{2}"), (r'(nimaid_version\(void\);\s*/\* ")[^"]+', "{v}")],
    "capi/docs/reference/c-api.md": [(r'(nimaid_version\(void\);\s*/\* ")[^"]+', "{v}")],
}


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f: return f.read()


def current():
    return re.search(SPOTS["nimaid.nimble"], read("nimaid.nimble"), re.M).group(1)


def main():
    if len(sys.argv) == 1:
        vs = {}
        for rel, rx in SPOTS.items():
            if os.path.exists(os.path.join(ROOT, rel)): vs[rel] = re.search(rx, read(rel), re.M).group(1)
        for rel, v in vs.items(): print(f"{v:10} {rel}")
        if len(set(vs.values())) != 1: sys.exit("VERSION MISMATCH")
        return
    new = sys.argv[1].lstrip("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", new): sys.exit("version must look like 1.2.3")
    parts = new.split(".")
    for rel, rx in SPOTS.items():
        if not os.path.exists(os.path.join(ROOT, rel)): continue
        s = re.sub(rx, lambda m: m.group(0).replace(m.group(1), new), read(rel), flags=re.M)
        for erx, tpl in EXTRA.get(rel, []):
            s = re.sub(erx, lambda m: m.group(1) + tpl.format(*parts, v=new), s)
        open(os.path.join(ROOT, rel), "w", encoding="utf-8").write(s)
    for rel, lst in EXTRA.items():
        if rel in SPOTS: continue
        s = read(rel)
        for erx, tpl in lst: s = re.sub(erx, lambda m: m.group(1) + tpl.format(*parts, v=new), s)
        open(os.path.join(ROOT, rel), "w", encoding="utf-8").write(s)
    print(f"version set to {new}")


if __name__ == "__main__":
    main()
