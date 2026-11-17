#!/usr/bin/env python3
"""Render every examples/*.mmd (flowcharts + sequence); fails on crash or empty output."""
import glob, os, subprocess, sys
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
env=dict(os.environ, LD_LIBRARY_PATH=os.path.join(ROOT,'lib')); bad=0
for f in sorted(glob.glob(os.path.join(ROOT,'examples','*.mmd'))):
    out=f[:-4]+'.png'
    r=subprocess.run([os.path.join(ROOT,'bin/nimaid'),f,out],capture_output=True,text=True,env=env,timeout=120)
    ok=r.returncode==0 and os.path.getsize(out)>1000
    print(('ok  ' if ok else 'FAIL'),os.path.basename(f)); bad+=not ok
sys.exit(1 if bad else 0)
