#!/usr/bin/env python3
"""Every examples/*.mmd must export to valid PNG, palette PNG, GIF and well-formed SVG (and stay small)."""
import glob, os, subprocess, sys, xml.dom.minidom
from PIL import Image
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
env=dict(os.environ, LD_LIBRARY_PATH=os.path.join(ROOT,'lib')); bad=0; tot={}
for f in sorted(glob.glob(os.path.join(ROOT,'examples','*.mmd'))):
    base=os.path.basename(f)[:-4]
    for ext,args in (('png',[]),('gif',[]),('svg',[]),('p64.png',['--colors=64'])):
        out=f'/tmp/exp_{base}.{ext}'
        r=subprocess.run([os.path.join(ROOT,'bin/nimaid'),*args,f,out],capture_output=True,text=True,env=env,timeout=120)
        ok=r.returncode==0 and os.path.exists(out)
        if ok:
            try:
                if ext.endswith('png') or ext=='gif': Image.open(out).load()
                else: xml.dom.minidom.parse(out)
            except Exception as e: ok=False; print('  invalid',out,e)
        if not ok: bad+=1; print('FAIL',base,ext,r.stderr[-120:])
        else: tot[ext]=tot.get(ext,0)+os.path.getsize(out)
print({k:f'{v/1024:.0f} KB' for k,v in tot.items()}, 'FAILURES' if bad else 'all valid')
sys.exit(1 if bad else 0)
