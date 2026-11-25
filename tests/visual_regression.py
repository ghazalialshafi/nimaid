#!/usr/bin/env python3
"""Visual regression: render every examples/*.mmd and compare with the golden examples/*.png.
Also (if `pip install resvg-py`) renders each SVG with an independent engine and compares it to the PNG.

  python3 tests/visual_regression.py            # needs Pillow + numpy
Exit status is non-zero if any example drifts beyond tolerance.
"""
import glob, io, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN=os.path.join(ROOT,'bin','nimaid')
FONT=os.path.join(ROOT,'fonts','DejaVuSans.ttf')
TOL_MEAN, TOL_BAD = 1.0, 0.05          # mean abs diff (0..255; large translucent areas such as sankey ribbons differ by ~1/255 between engines) and % of pixels differing by >64
try:
    import resvg_py
except ImportError:
    resvg_py=None
def flat(im): return Image.alpha_composite(Image.new("RGBA",im.size,(255,255,255,255)),im.convert("RGBA"))
def diff(a,b):
    w,h=min(a.width,b.width),min(a.height,b.height)
    d=np.abs(np.asarray(a.crop((0,0,w,h)),int)-np.asarray(b.crop((0,0,w,h)),int)).max(axis=2)
    return d.mean(), 100*(d>64).mean()
tmp=tempfile.mkdtemp(prefix="nimaid_vr_"); bad=0
print(f"{'example':14}{'PNG vs golden':>20}{'SVG vs PNG':>20}")
for f in sorted(glob.glob(os.path.join(ROOT,'examples','*.mmd'))):
    n=os.path.basename(f)[:-4]; png=os.path.join(tmp,n+'.png'); svg=os.path.join(tmp,n+'.svg')
    for out in (png,svg): subprocess.run([BIN,f,out],check=True,capture_output=True,timeout=180)
    got=Image.open(png); gold=Image.open(os.path.join(ROOT,'examples',n+'.png'))
    if got.size!=gold.size: print(f"{n:14}  SIZE MISMATCH {got.size} vs {gold.size}"); bad+=1; continue
    m,p=diff(flat(got),flat(gold)); ok=m<=TOL_MEAN and p<=TOL_BAD; line=f"{n:14}{m:9.3f} /{p:7.4f}%"
    if resvg_py:
        s=Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_path=svg,font_files=[FONT],zoom=2))))
        m2,p2=diff(flat(s),flat(got)); ok=ok and m2<=TOL_MEAN and p2<=TOL_BAD; line+=f"{m2:9.3f} /{p2:7.4f}%"
    print(line+("" if ok else "   <-- DRIFT")); bad+=not ok
print("OK" if not bad else f"{bad} example(s) drifted")
sys.exit(1 if bad else 0)
