## Math, matrices, path segments (M/L/Q/C/Z), Bezier flattening.
import std/math
type
  Pt* = object
    x*, y*: float
  Mat* = object          ## x' = a*x + c*y + e ; y' = b*x + d*y + f
    a*, b*, c*, d*, e*, f*: float
  Seg* = object          ## 'M' 'L' 'C' 'Z'
    op*: char
    v*: array[6, float]
  Poly* = object
    pts*: seq[Pt]
    closed*: bool

const Ident* = Mat(a: 1, d: 1)

proc npts*(op: char): int =
  case op
  of 'M', 'L': 1
  of 'Q': 2
  of 'C': 3
  else: 0

proc pt*(x, y: float): Pt = Pt(x: x, y: y)
proc `+`*(a, b: Pt): Pt = Pt(x: a.x + b.x, y: a.y + b.y)
proc `-`*(a, b: Pt): Pt = Pt(x: a.x - b.x, y: a.y - b.y)
proc `*`*(a: Pt, s: float): Pt = Pt(x: a.x * s, y: a.y * s)
proc len*(a: Pt): float = sqrt(a.x * a.x + a.y * a.y)

proc `*`*(m, n: Mat): Mat =
  ## (m*n)(p) = m(n(p))
  Mat(a: m.a*n.a + m.c*n.b, b: m.b*n.a + m.d*n.b,
      c: m.a*n.c + m.c*n.d, d: m.b*n.c + m.d*n.d,
      e: m.a*n.e + m.c*n.f + m.e, f: m.b*n.e + m.d*n.f + m.f)
proc apply*(m: Mat, x, y: float): Pt = Pt(x: m.a*x + m.c*y + m.e, y: m.b*x + m.d*y + m.f)
proc scaleOf*(m: Mat): float = sqrt(abs(m.a*m.d - m.b*m.c))
proc inverse*(m: Mat): Mat =
  let det = m.a * m.d - m.b * m.c
  if abs(det) < 1e-12: return Ident
  let id = 1.0 / det
  Mat(a: m.d * id, b: -m.b * id, c: -m.c * id, d: m.a * id,
      e: (m.c * m.f - m.d * m.e) * id, f: (m.b * m.e - m.a * m.f) * id)
proc translateM*(x, y: float): Mat = Mat(a: 1, d: 1, e: x, f: y)
proc scaleM*(s: float): Mat = Mat(a: s, d: s)
proc rotateM*(deg: float): Mat =
  let r = deg * PI / 180.0
  Mat(a: cos(r), b: sin(r), c: -sin(r), d: cos(r))

proc flatten*(segs: seq[Seg], m: Mat, tol = 0.05): seq[Poly] =
  ## Transforms to device space and flattens cubics into polylines.
  var cur = Poly()
  var first, last: Pt
  var started = false
  template push() =
    if cur.pts.len >= 2: result.add cur
  for s in segs:
    case s.op
    of 'M':
      push()
      first = m.apply(s.v[0], s.v[1]); last = first
      cur = Poly(pts: @[first]); started = true
    of 'L':
      if not started: first = m.apply(s.v[0], s.v[1]); cur = Poly(pts: @[first]); started = true; last = first
      else:
        last = m.apply(s.v[0], s.v[1]); cur.pts.add last
    of 'Q':
      if not started: started = true; first = m.apply(s.v[0], s.v[1]); last = first; cur = Poly(pts: @[first])
      let p0 = last
      let q = m.apply(s.v[0], s.v[1]); let p3 = m.apply(s.v[2], s.v[3])
      let p1 = p0 + (q - p0) * (2.0 / 3.0); let p2 = p3 + (q - p3) * (2.0 / 3.0)
      let dd = max((p0 - p1*2.0 + p2).len, (p1 - p2*2.0 + p3).len)
      let n = clamp(int(ceil(sqrt(0.75 * dd / tol))), 1, 200)
      for i in 1..n:
        let t = i / n; let u = 1 - t
        cur.pts.add Pt(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                       y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
      last = p3
    of 'C':
      if not started: started = true; first = m.apply(s.v[0], s.v[1]); last = first; cur = Poly(pts: @[first])
      let p0 = last
      let p1 = m.apply(s.v[0], s.v[1]); let p2 = m.apply(s.v[2], s.v[3]); let p3 = m.apply(s.v[4], s.v[5])
      let dd = max((p0 - p1*2.0 + p2).len, (p1 - p2*2.0 + p3).len)
      let n = clamp(int(ceil(sqrt(0.75 * dd / tol))), 1, 200)
      for i in 1..n:
        let t = i / n; let u = 1 - t
        cur.pts.add Pt(x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
                       y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y)
      last = p3
    else: # 'Z'
      if started:
        cur.closed = true
        push()
        cur = Poly(pts: @[first]); last = first
  push()

proc bounds*(polys: seq[Poly]): tuple[x0, y0, x1, y1: float, ok: bool] =
  result = (1e30, 1e30, -1e30, -1e30, false)
  for p in polys:
    for q in p.pts:
      result.ok = true
      result.x0 = min(result.x0, q.x); result.y0 = min(result.y0, q.y)
      result.x1 = max(result.x1, q.x); result.y1 = max(result.y1, q.y)
