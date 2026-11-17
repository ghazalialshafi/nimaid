#!/usr/bin/env python3
"""Render every chart extracted from mermaid's flowchart specs; report crashes/timeouts."""
import json, subprocess, tempfile, os, sys, collections
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
cases=json.load(open(os.path.join(ROOT,'tests/spec_cases.json')))
env=dict(os.environ, LD_LIBRARY_PATH=os.path.join(ROOT,'lib'))
res=collections.Counter(); bad=[]
seen=set()
for c in cases:
    if 'chart' not in c or c['chart'] in seen: continue
    seen.add(c['chart'])
    with tempfile.NamedTemporaryFile('w',suffix='.mmd',delete=False) as f: f.write(c['chart']); p=f.name
    d=subprocess.run([os.path.join(ROOT,'bin/dumpdb'),p],capture_output=True,text=True)
    try: parse_err='error' in json.loads(d.stdout)
    except Exception: parse_err=True
    try:
        r=subprocess.run([os.path.join(ROOT,'bin/nimaid'),p,'/tmp/spec_out.png'],capture_output=True,text=True,timeout=30,env=env)
        rc=r.returncode; err=(r.stderr or r.stdout)[-300:]
    except subprocess.TimeoutExpired: rc=-9; err='TIMEOUT'
    os.unlink(p)
    if parse_err: res['parse-error(expected-or-unsupported)']+=1
    elif rc==0: res['ok']+=1
    else: res['RENDER FAIL']+=1; bad.append((c['file'],c['name'],rc,c['chart'][:150],err.strip().splitlines()[-1] if err.strip() else ''))
print(dict(res))
for b in bad[:40]: print('\n',b[0],'|',b[1],'| rc',b[2],'\n  chart:',repr(b[3]),'\n  ',b[4])
