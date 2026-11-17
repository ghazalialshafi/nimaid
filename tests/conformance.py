#!/usr/bin/env python3
"""Run mermaid's flowchart parser spec assertions against bin/dumpdb. Usage: conformance.py [-v] [file-filter]"""
import json, re, subprocess, sys, tempfile, os, collections
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args=[a for a in sys.argv[1:] if a!='-v']; verbose='-v' in sys.argv
filt=args[0] if args else ''
cases=json.load(open(os.path.join(ROOT,'tests/spec_cases.json')))
MISSING=object()

def resolve(lhs, d, aliases):
    toks=re.findall(r"[A-Za-z_]\w*|\[\d+\]|\.|\('[^']*'\)|\(\w*\)",lhs)
    # normalise: build path list
    m=re.match(r"vert\.get\('([^']*)'\)(.*)",lhs)
    if m:
        cur=d['vertices'].get(m.group(1),MISSING); rest=m.group(2)
        if cur is MISSING: return MISSING
    else:
        m=re.match(r"classes\.get\('([^']*)'\)(.*)",lhs)
        if m:
            cur=d['classes'].get(m.group(1),MISSING); rest=m.group(2)
            if cur is MISSING: return MISSING
        else:
            m=re.match(r"(\w+?)((?:\[\d+\])?)(\..*|\[\d+\].*|)$",lhs)
            rm=re.match(r"[A-Za-z_]\w*",lhs)
            if not rm: return ('UNSUPPORTED',lhs)
            root=rm.group(0); rest=lhs[len(root):]
            if root in ('edges','subgraphs','direction','data4Layout'):
                cur={'edges':d['edges'],'subgraphs':d['subgraphs'],'direction':d['direction'],'data4Layout':d['data4Layout']}[root]
            elif root=='subgraph' and 'subgraph' not in aliases:
                cur=d['subgraphs'][0] if d['subgraphs'] else MISSING
            elif root in aliases:
                i=aliases[root]
                if isinstance(i,str): cur=next((s for s in d['subgraphs'] if s['id']==i),MISSING)
                else: cur=d['subgraphs'][i] if i<len(d['subgraphs']) else MISSING
            elif root=='vert' and rest=='.size': return len(d['vertices'])
            else: return ('UNSUPPORTED',root)
            if cur is MISSING: return MISSING
    for t in re.findall(r"\.(\w+)|\[(\d+)\]",rest):
        try:
            if t[0]=='length' and isinstance(cur,(list,str)): cur=len(cur)
            elif t[0]=='interpolate' or t[0]=='animate' or t[0]=='defaultInterpolate': return ('UNSUPPORTED',t[0])
            elif t[0]: cur=cur[t[0]] if t[0] in cur else (None if isinstance(cur,dict) else MISSING)
            else: cur=cur[int(t[1])]
        except (IndexError,KeyError,TypeError): return MISSING
    return cur

stats=collections.Counter(); fails=[]; byfile=collections.defaultdict(lambda:[0,0,0])
for c in cases:
    if 'chart' not in c or filt not in c['file']: continue
    with tempfile.NamedTemporaryFile('w',suffix='.mmd',delete=False) as f: f.write(c['chart']); path=f.name
    try:
        out=subprocess.run([os.path.join(ROOT,'bin/dumpdb'),path],capture_output=True,text=True,timeout=10)
        d=json.loads(out.stdout) if out.stdout.strip() else {'error':'crash: '+out.stderr[-200:]}
    except subprocess.TimeoutExpired: d={'error':'TIMEOUT'}
    os.unlink(path)
    if 'error' in d:
        stats['error']+=1; byfile[c['file']][2]+=1; fails.append((c,'PARSE ERROR: '+d['error'],None)); continue
    bad=[]
    for e in c['expect']:
        v=resolve(e['lhs'],d,c.get('aliases',{}))
        if isinstance(v,tuple): stats['unsupported']+=1; continue
        exp=e['rhs']
        if v is MISSING: v=None
        if e['op']=='toBe' or e['op']=='toEqual': ok=(v==exp) or (exp is None and v in (None,''))
        elif e['op']=='toContain': ok=exp in (v or [])
        else: ok=len(v or [])==exp
        # json numbers
        stats['pass' if ok else 'fail']+=1
        if not ok: bad.append((e['lhs'],e['op'],exp,v))
    if bad: byfile[c['file']][1]+=1; fails.append((c,'ASSERT',bad))
    else: byfile[c['file']][0]+=1
print('assertions:',dict(stats))
for f,(p,b,e) in sorted(byfile.items()): print(f'  {f:34s} pass {p:3d}  fail {b:3d}  parse-error {e:3d}')
if verbose:
    for c,kind,bad in fails:
        print('\n---',c['file'],'|',c['name'],'|',kind); print('   chart:',repr(c['chart'][:160]))
        for b in bad or []: print('   ',b)
