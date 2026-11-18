#!/usr/bin/env python3
"""Render every examples/*.mmd to a temp dir; fails on crash or empty output. (Never overwrites the golden examples/*.png.)"""
import glob, os, subprocess, sys, tempfile
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
env=dict(os.environ); bad=0
tmp=tempfile.mkdtemp(prefix="nimaid_smoke_")
for f in sorted(glob.glob(os.path.join(ROOT,'examples','*.mmd'))):
    out=os.path.join(tmp,os.path.basename(f)[:-4]+'.png')
    r=subprocess.run([os.path.join(ROOT,'bin/nimaid'),f,out],capture_output=True,text=True,env=env,timeout=120)
    ok=r.returncode==0 and os.path.exists(out) and os.path.getsize(out)>1000
    print(('ok  ' if ok else 'FAIL'),os.path.basename(f)); bad+=not ok
sys.exit(1 if bad else 0)
