#!/usr/bin/env python3
"""Checks that every relative link, image and #anchor in the Markdown docs resolves.   python3 docs/check_links.py"""
import os, re, sys, glob
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
files=[os.path.join(ROOT,f) for f in ("README.md","CONTRIBUTING.md","CHANGELOG.md","THIRD_PARTY.md")]+glob.glob(os.path.join(ROOT,"docs","**","*.md"),recursive=True)
def slug(h):
    h=re.sub(r"[*`_]","",h.strip().lower()); h=re.sub(r"[^\w\- ]","",h); return h.replace(" ","-")
def anchors(path):
    out=set(); fence=False
    for line in open(path,encoding="utf8"):
        if line.startswith("```"): fence=not fence
        if not fence:
            m=re.match(r"#{1,6}\s+(.*)",line)
            if m: out.add(slug(m.group(1)))
    return out
bad=0; n=0
for f in sorted(files):
    text=open(f,encoding="utf8").read()
    text_nofence=re.sub(r"```.*?```","",text,flags=re.S)
    refs=re.findall(r"\]\(([^)\s]+)\)",text_nofence)+re.findall(r'(?:src|href)="([^"]+)"',text_nofence)
    for r in refs:
        if r.startswith(("http://","https://","mailto:")): continue
        n+=1; path,_,frag=r.partition("#")
        target=f if path=="" else os.path.normpath(os.path.join(os.path.dirname(f),path))
        if not os.path.exists(target): print("MISSING",os.path.relpath(f,ROOT),"->",r); bad+=1; continue
        if frag and target.endswith(".md") and frag not in anchors(target): print("BAD ANCHOR",os.path.relpath(f,ROOT),"->",r); bad+=1
print(f"{n} links/images checked, {bad} problem(s)"); sys.exit(1 if bad else 0)
