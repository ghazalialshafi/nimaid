## Scanline coverage rasteriser.
## 16 sub-scanlines, exact horizontal coverage, true nonzero / even-odd winding.
import std/[math, algorithm]
import core
const SS = 16
type
  Mask* = object
    x0*, y0*, w*, h*: int
    cov*: seq[float32]           ## w*h, 0..1
  Layer* = object
    w*, h*: int
    px*: seq[float32]            ## premultiplied RGBA, w*h*4

proc newLayer*(w, h: int): Layer = Layer(w: w, h: h, px: newSeq[float32](w * h * 4))

proc cmpX(a, b: (float32, int8)): int = cmp(a[0], b[0])

proc rasterize*(polys: seq[Poly], evenOdd: bool, cw, ch: int): Mask =
  let b = bounds(polys)
  if not b.ok: return
  let x0 = max(0, int(floor(b.x0))); let x1 = min(cw, int(ceil(b.x1)))
  let y0 = max(0, int(floor(b.y0))); let y1 = min(ch, int(ceil(b.y1)))
  if x1 <= x0 or y1 <= y0: return
  let w = x1 - x0; let h = y1 - y0
  result = Mask(x0: x0, y0: y0, w: w, h: h, cov: newSeq[float32](w * h))
  let nsub = h * SS
  var buckets = newSeq[seq[(float32, int8)]](nsub)
  for p in polys:
    let n = p.pts.len
    if n < 2: continue
    for i in 0..<n:
      let a = p.pts[i]; let c = p.pts[(i + 1) mod n]
      if a.y == c.y: continue
      let (ax, ay, bx, by, dir) = if a.y < c.y: (a.x, a.y, c.x, c.y, 1'i8) else: (c.x, c.y, a.x, a.y, -1'i8)
      let dxdy = (bx - ax) / (by - ay)
      let k0 = max(0, int(ceil((ay - y0.float) * SS - 0.5)))
      let k1 = min(nsub - 1, int(ceil((by - y0.float) * SS - 0.5)) - 1)
      for k in k0..k1:
        let ys = y0.float + (k.float + 0.5) / SS
        buckets[k].add((float32(ax + (ys - ay) * dxdy - x0.float), dir))
  var acc = newSeq[float32](w + 2)
  var dif = newSeq[float32](w + 2)
  let wt = 1'f32 / SS
  for row in 0..<h:
    for i in 0..w+1: acc[i] = 0; dif[i] = 0
    var any = false
    for s in 0..<SS:
      var xs = move buckets[row * SS + s]
      if xs.len < 2: continue
      xs.sort(cmpX)
      var wind = 0
      for i in 0..<xs.len - 1:
        wind += xs[i][1].int
        if (if evenOdd: (wind and 1) != 0 else: wind != 0):
          let a = max(0'f32, xs[i][0]); let c = min(w.float32, xs[i + 1][0])
          if c <= a: continue
          any = true
          let ia = int(a); let ib = int(c)
          if ia == ib: acc[ia] += (c - a) * wt
          else:
            acc[ia] += (ia.float32 + 1 - a) * wt
            acc[ib] += (c - ib.float32) * wt
            dif[ia + 1] += wt; dif[ib] -= wt
    if not any: continue
    var run = 0'f32
    for x in 0..<w:
      run += dif[x]
      result.cov[row * w + x] = clamp(acc[x] + run, 0'f32, 1'f32)

proc blend*(L: var Layer, m: Mask, r, g, b, a: float) =
  ## Source-over of a straight colour through a coverage mask.
  if m.w == 0: return
  for y in 0..<m.h:
    for x in 0..<m.w:
      let c = m.cov[y * m.w + x]
      if c <= 0: continue
      let ca = c.float * a
      let i = ((y + m.y0) * L.w + x + m.x0) * 4
      let inv = float32(1 - ca)
      L.px[i]     = L.px[i] * inv + float32(r * ca)
      L.px[i + 1] = L.px[i + 1] * inv + float32(g * ca)
      L.px[i + 2] = L.px[i + 2] * inv + float32(b * ca)
      L.px[i + 3] = L.px[i + 3] * inv + float32(ca)

proc compositeGroup*(dst: var Layer, src: Layer, opacity: float) =
  for i in 0..<dst.w * dst.h:
    let sa = src.px[i * 4 + 3] * opacity.float32
    if src.px[i * 4 + 3] <= 0: continue
    let inv = 1 - sa
    for c in 0..2: dst.px[i * 4 + c] = dst.px[i * 4 + c] * inv + src.px[i * 4 + c] * opacity.float32
    dst.px[i * 4 + 3] = dst.px[i * 4 + 3] * inv + sa

type Ramp* = array[256, array[4, float32]]   ## straight RGBA

proc blendGradient*(L: var Layer, m: Mask, ramp: ref Ramp, radial: bool, t: array[6, float],
                    devToImg: Mat, alpha: float) =
  ## Gradient fill (nanosvg model: t maps image space to unit gradient space, 256-entry ramp, pad spread).
  if m.w == 0: return
  for y in 0..<m.h:
    for x in 0..<m.w:
      let c = m.cov[y * m.w + x]
      if c <= 0: continue
      let p = devToImg.apply(float(x + m.x0) + 0.5, float(y + m.y0) + 0.5)
      let g = if radial:
          let gx = p.x * t[0] + p.y * t[2] + t[4]
          let gy = p.x * t[1] + p.y * t[3] + t[5]
          sqrt(gx * gx + gy * gy)
        else: p.x * t[1] + p.y * t[3] + t[5]
      let col = ramp[][clamp(int(g * 255), 0, 255)]
      let ca = c * col[3] * alpha.float32
      let i = ((y + m.y0) * L.w + x + m.x0) * 4
      let inv = 1 - ca
      L.px[i] = L.px[i] * inv + col[0] * ca
      L.px[i + 1] = L.px[i + 1] * inv + col[1] * ca
      L.px[i + 2] = L.px[i + 2] * inv + col[2] * ca
      L.px[i + 3] = L.px[i + 3] * inv + ca
