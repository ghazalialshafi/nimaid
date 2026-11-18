#!/usr/bin/env python3
"""Syntax coverage: render every chart string found in mermaid's own specs for a diagram type; group failures.
usage: coverage_diagrams.py <spec-dir-or-json> <header-prefix> [-v]"""
import json, subprocess, sys, os, tempfile, collections
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src,prefix=sys.argv[1],sys.argv[2].lower(); verbose='-v' in sys.argv
import re, glob
LIT=re.compile(r"`((?:[^`\\]|\\.)*)`|'((?:[^'\\\n]|\\.)*)'|\"((?:[^\"\\\n]|\\.)*)\"",re.S)
def unesc(t): return re.sub(r"\\(.)",lambda m:{'n':'\n','t':'\t'}.get(m.group(1),m.group(1)),t)
cases=[]
files=[src] if os.path.isfile(src) else [f for pat in ('*.spec.js','*.spec.ts','*.test.ts') for f in glob.glob(os.path.join(src,'**',pat),recursive=True)]
for f in files:
    for m in LIT.finditer(open(f).read()):
        t=next(g for g in m.groups() if g is not None)
        if '${' in t: continue
        t=unesc(t)
        if t.strip().lower().startswith(prefix): cases.append({'chart':t})
env=dict(os.environ)
seen=set(); res=collections.Counter(); errs=collections.defaultdict(list)
for c in cases:
    ch=c.get('chart')
    if not ch or ch in seen: continue
    seen.add(ch)
    with tempfile.NamedTemporaryFile('w',suffix='.mmd',delete=False) as f: f.write(ch); p=f.name
    try:
        r=subprocess.run([os.path.join(ROOT,'bin/nimaid'),p,'/tmp/cov.png'],capture_output=True,text=True,timeout=30,env=env); rc=r.returncode; err=(r.stderr or r.stdout)
    except subprocess.TimeoutExpired: rc=-9; err='TIMEOUT'
    os.unlink(p)
    if rc==0: res['ok']+=1
    else:
        res['FAIL']+=1; msg=[l for l in err.strip().splitlines() if l.strip()][-1][:110] if err.strip() else 'rc=%d'%rc
        errs[msg].append(ch[:110].replace('\n','\\n'))
print(dict(res))
for m,l in sorted(errs.items(),key=lambda x:-len(x[1]))[:12]:
    print(f'  [{len(l)}] {m}\n      e.g. {l[0]}')
