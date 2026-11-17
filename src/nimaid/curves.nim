## Ports of d3-shape curve generators used by mermaid edges (basis is mermaid's default).
import std/math
import geom, edges

type Cmds = seq[PathCommand]

proc mv(c: var Cmds, x, y: float) = c.add PathCommand(kind: pckMove, p1: Point(x: x, y: y))
proc ln(c: var Cmds, x, y: float) = c.add PathCommand(kind: pckLine, p1: Point(x: x, y: y))
proc bz(c: var Cmds, a, b, d, e, f, g: float) =
  c.add PathCommand(kind: pckCubic, p1: Point(x: a, y: b), p2: Point(x: d, y: e), p3: Point(x: f, y: g))

proc linear(p: seq[Point]): Cmds =
  for i, q in p:
    if i == 0: result.mv(q.x, q.y) else: result.ln(q.x, q.y)

proc basis(p: seq[Point]): Cmds =
  var st = 0
  var x0, y0, x1, y1 = NaN
  proc seg(c: var Cmds, x, y: float) =
    c.bz((2 * x0 + x1) / 3, (2 * y0 + y1) / 3, (x0 + 2 * x1) / 3, (y0 + 2 * y1) / 3,
         (x0 + 4 * x1 + x) / 6, (y0 + 4 * y1 + y) / 6)
  for q in p:
    let x = q.x
    let y = q.y
    case st
    of 0:
      st = 1
      result.mv(x, y)
    of 1: st = 2
    of 2:
      st = 3
      result.ln((5 * x0 + x1) / 6, (5 * y0 + y1) / 6)
      result.seg(x, y)
    else: result.seg(x, y)
    x0 = x1; x1 = x; y0 = y1; y1 = y
  if st == 3: result.seg(x1, y1)
  if st >= 2: result.ln(x1, y1)

proc cardinalLike(p: seq[Point], tension: float): Cmds =
  let k = (1 - tension) / 6
  var st = 0
  var x0, y0, x1, y1, x2, y2 = NaN
  proc seg(c: var Cmds, x, y: float) =
    c.bz(x1 + k * (x2 - x0), y1 + k * (y2 - y0), x2 + k * (x1 - x), y2 + k * (y1 - y), x2, y2)
  for q in p:
    let x = q.x
    let y = q.y
    case st
    of 0:
      st = 1
      result.mv(x, y)
    of 1:
      st = 2
      x1 = x; y1 = y
    of 2:
      st = 3
      result.seg(x, y)
    else: result.seg(x, y)
    x0 = x1; x1 = x2; x2 = x; y0 = y1; y1 = y2; y2 = y
  if st == 2: result.ln(x2, y2)
  elif st == 3: result.seg(x1, y1)

proc catmullRom(p: seq[Point], alpha = 0.5): Cmds =
  const eps = 1e-12
  var st = 0
  var x0, y0, x1, y1, x2, y2 = NaN
  var l01a, l12a, l23a, l01_2a, l12_2a, l23_2a = 0.0
  proc seg(c: var Cmds, x, y: float) =
    var ax = x1
    var ay = y1
    var bx = x2
    var by = y2
    if l01a > eps:
      let a = 2 * l01_2a + 3 * l01a * l12a + l12_2a
      let n = 3 * l01a * (l01a + l12a)
      ax = (x1 * a - x0 * l12_2a + x2 * l01_2a) / n
      ay = (y1 * a - y0 * l12_2a + y2 * l01_2a) / n
    if l23a > eps:
      let b = 2 * l23_2a + 3 * l23a * l12a + l12_2a
      let m = 3 * l23a * (l23a + l12a)
      bx = (x2 * b + x1 * l23_2a - x * l12_2a) / m
      by = (y2 * b + y1 * l23_2a - y * l12_2a) / m
    c.bz(ax, ay, bx, by, x2, y2)
  proc feed(c: var Cmds, x, y: float) =
    if st > 0:
      let x23 = x2 - x
      let y23 = y2 - y
      l23_2a = pow(x23 * x23 + y23 * y23, alpha)
      l23a = sqrt(l23_2a)
    case st
    of 0:
      st = 1
      c.mv(x, y)
    of 1: st = 2
    of 2:
      st = 3
      c.seg(x, y)
    else: c.seg(x, y)
    l01a = l12a; l12a = l23a; l01_2a = l12_2a; l12_2a = l23_2a
    x0 = x1; x1 = x2; x2 = x; y0 = y1; y1 = y2; y2 = y
  for q in p: result.feed(q.x, q.y)
  if st == 2: result.ln(x2, y2)
  elif st == 3: result.feed(x2, y2)

proc ctrlPoints(x: seq[float]): (seq[float], seq[float]) =
  let n = x.len - 1
  var a = newSeq[float](n)
  var b = newSeq[float](n)
  var r = newSeq[float](n)
  a[0] = 0; b[0] = 2; r[0] = x[0] + 2 * x[1]
  for i in 1 ..< n - 1:
    a[i] = 1; b[i] = 4; r[i] = 4 * x[i] + 2 * x[i + 1]
  a[n - 1] = 2; b[n - 1] = 7; r[n - 1] = 8 * x[n - 1] + x[n]
  for i in 1 ..< n:
    let m = a[i] / b[i - 1]
    b[i] -= m
    r[i] -= m * r[i - 1]
  a[n - 1] = r[n - 1] / b[n - 1]
  for i in countdown(n - 2, 0): a[i] = (r[i] - a[i + 1]) / b[i]
  b[n - 1] = (x[n] + a[n - 1]) / 2
  for i in 0 ..< n - 1: b[i] = 2 * x[i + 1] - a[i + 1]
  (a, b)

proc natural(p: seq[Point]): Cmds =
  let n = p.len
  if n == 0: return
  result.mv(p[0].x, p[0].y)
  if n == 1: return
  if n == 2:
    result.ln(p[1].x, p[1].y)
    return
  var xs, ys: seq[float]
  for q in p:
    xs.add q.x
    ys.add q.y
  let (ax, bx) = ctrlPoints(xs)
  let (ay, by) = ctrlPoints(ys)
  for i in 0 ..< n - 1: result.bz(ax[i], ay[i], bx[i], by[i], xs[i + 1], ys[i + 1])

proc monotoneX(p: seq[Point]): Cmds =
  var st = 0
  var x0, y0, x1, y1, t0 = NaN
  proc sgn(v: float): float = (if v < 0: -1.0 else: 1.0)
  proc slope3(x2, y2: float): float =
    let h0 = x1 - x0
    let h1 = x2 - x1
    let s0 = (y1 - y0) / (if h0 != 0: h0 elif h1 < 0: -0.0 else: 0.0)
    let s1 = (y2 - y1) / (if h1 != 0: h1 elif h0 < 0: -0.0 else: 0.0)
    let pp = (s0 * h1 + s1 * h0) / (h0 + h1)
    let r = (sgn(s0) + sgn(s1)) * min(abs(s0), min(abs(s1), 0.5 * abs(pp)))
    if r.isNaN: 0.0 else: r
  proc slope2(t: float): float =
    let h = x1 - x0
    if h != 0: (3 * (y1 - y0) / h - t) / 2 else: t
  proc seg(c: var Cmds, a, b: float) =
    let dx = (x1 - x0) / 3
    c.bz(x0 + dx, y0 + dx * a, x1 - dx, y1 - dx * b, x1, y1)
  for q in p:
    let x = q.x
    let y = q.y
    if x == x1 and y == y1: continue
    var t1 = NaN
    case st
    of 0:
      st = 1
      result.mv(x, y)
    of 1: st = 2
    of 2:
      st = 3
      t1 = slope3(x, y)
      result.seg(slope2(t1), t1)
    else:
      t1 = slope3(x, y)
      result.seg(t0, t1)
    x0 = x1; x1 = x; y0 = y1; y1 = y; t0 = t1
  if st == 2: result.ln(x1, y1)
  elif st == 3: result.seg(t0, slope2(t0))

proc swapXY(p: seq[Point]): seq[Point] =
  for q in p: result.add Point(x: q.y, y: q.x)

proc swapCmds(c: Cmds): Cmds =
  for x in c:
    var y = x
    y.p1 = Point(x: x.p1.y, y: x.p1.x)
    y.p2 = Point(x: x.p2.y, y: x.p2.x)
    y.p3 = Point(x: x.p3.y, y: x.p3.x)
    result.add y

proc step(p: seq[Point], t: float): Cmds =
  var st = 0
  var x, y = 0.0
  for q in p:
    if st == 0:
      st = 1
      result.mv(q.x, q.y)
    else:
      st = 2
      if t <= 0:
        result.ln(x, q.y)
        result.ln(q.x, q.y)
      else:
        let x1 = x * (1 - t) + q.x * t
        result.ln(x1, y)
        result.ln(x1, q.y)
    x = q.x
    y = q.y
  if 0 < t and t < 1 and st == 2: result.ln(x, y)

proc bump(p: seq[Point], horizontal: bool): Cmds =
  var x0, y0 = 0.0
  for i, q in p:
    if i == 0: result.mv(q.x, q.y)
    else:
      if horizontal:
        let m = (x0 + q.x) / 2
        result.bz(m, y0, m, q.y, q.x, q.y)
      else:
        let m = (y0 + q.y) / 2
        result.bz(x0, m, q.x, m, q.x, q.y)
    x0 = q.x
    y0 = q.y

proc curveCommands*(points: seq[Point], curve: string): seq[PathCommand] =
  case curve
  of "linear": linear(points)
  of "cardinal": cardinalLike(points, 0.0)
  of "catmullRom": catmullRom(points, 0.5)
  of "natural": natural(points)
  of "monotoneX": monotoneX(points)
  of "monotoneY": swapCmds(monotoneX(swapXY(points)))
  of "step": step(points, 0.5)
  of "stepBefore": step(points, 0.0)
  of "stepAfter": step(points, 1.0)
  of "bumpX": bump(points, true)
  of "bumpY": bump(points, false)
  of "rounded": generateRoundedPathCommands(points, 5.0)
  else: basis(points)     # mermaid's default
