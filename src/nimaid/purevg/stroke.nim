## Stroker: caps, joins, miter limit, dashes.
## Output is a set of consistently-oriented convex pieces; fill with nonzero => union.
import std/[math, algorithm]
import core
type
  Cap* = enum cButt, cRound, cSquare
  Join* = enum jMiter, jRound, jBevel

proc area(p: openArray[Pt]): float =
  for i in 0..<p.len:
    let a = p[i]; let b = p[(i + 1) mod p.len]
    result += a.x * b.y - b.x * a.y
proc emit(res: var seq[Poly], pts: seq[Pt]) =
  var q = pts
  if area(q) < 0: q.reverse()
  res.add Poly(pts: q, closed: true)
proc unit(a: Pt): Pt = (let l = a.len; if l < 1e-12: Pt() else: Pt(x: a.x / l, y: a.y / l))
proc leftN(d: Pt): Pt = Pt(x: -d.y, y: d.x)
proc arcStep(r: float): float = 2 * arccos(max(0.0, 1 - 0.04 / max(r, 0.05)))

proc arcPts(c: Pt, r, a0, sweep: float, withEnds = true): seq[Pt] =
  let n = max(2, int(ceil(abs(sweep) / max(arcStep(r), 0.05))))
  for i in 0..n: result.add c + Pt(x: cos(a0 + sweep * float(i) / float(n)), y: sin(a0 + sweep * float(i) / float(n))) * r

proc joinAt(res: var seq[Poly], P, d0, d1: Pt, hw: float, join: Join, miter: float) =
  let cr = d0.x * d1.y - d0.y * d1.x
  let dt = d0.x * d1.x + d0.y * d1.y
  if abs(cr) < 1e-7 and dt > 0: return
  let s = if cr > 0: -1.0 else: 1.0
  let n0 = leftN(d0) * s; let n1 = leftN(d1) * s
  let a = P + n0 * hw; let b = P + n1 * hw
  case join
  of jRound:
    let sweep = arctan2(n0.x * n1.y - n0.y * n1.x, n0.x * n1.x + n0.y * n1.y)
    var pts = @[P]; pts.add arcPts(P, hw, arctan2(n0.y, n0.x), sweep); res.emit pts
  of jMiter:
    if 1 + dt > 1e-9 and sqrt(2 / (1 + dt)) <= miter:
      res.emit @[P, a, P + (n0 + n1) * (hw / (1 + dt)), b]
    else: res.emit @[P, a, b]
  of jBevel: res.emit @[P, a, b]

proc capAt(res: var seq[Poly], P, d: Pt, hw: float, cap: Cap) =
  let L = leftN(d)
  case cap
  of cButt: discard
  of cSquare: res.emit @[P + L*hw, P + L*hw + d*hw, P - L*hw + d*hw, P - L*hw]
  of cRound:
    res.emit arcPts(P, hw, arctan2(L.y, L.x), -PI)

proc strokeLine(res: var seq[Poly], src: seq[Pt], closed: bool, hw: float, cap: Cap, join: Join, miter: float) =
  var pts: seq[Pt]
  for p in src:
    if pts.len == 0 or (p - pts[^1]).len > 1e-9: pts.add p
  if closed and pts.len > 1 and (pts[0] - pts[^1]).len <= 1e-9: pts.setLen(pts.len - 1)
  let n = pts.len
  if n == 0: return
  if n == 1:
    if cap == cRound: res.emit arcPts(pts[0], hw, 0, 2 * PI)
    elif cap == cSquare: res.emit @[pts[0] + Pt(x: -hw, y: -hw), pts[0] + Pt(x: hw, y: -hw), pts[0] + Pt(x: hw, y: hw), pts[0] + Pt(x: -hw, y: hw)]
    return
  let segN = if closed: n else: n - 1
  var dirs = newSeq[Pt](segN)
  for i in 0..<segN:
    dirs[i] = unit(pts[(i + 1) mod n] - pts[i])
    let a = pts[i]; let b = pts[(i + 1) mod n]; let L = leftN(dirs[i]) * hw
    res.emit @[a + L, b + L, b - L, a - L]
  if closed:
    for i in 0..<n: res.joinAt(pts[i], dirs[(i - 1 + n) mod n], dirs[i], hw, join, miter)
  else:
    for i in 1..<n - 1: res.joinAt(pts[i], dirs[i - 1], dirs[i], hw, join, miter)
    res.capAt(pts[0], dirs[0] * -1.0, hw, cap)
    res.capAt(pts[^1], dirs[^1], hw, cap)

proc dashPolys(polys: seq[Poly], dash: seq[float], offset: float): seq[Poly] =
  var pat = dash
  if pat.len mod 2 == 1: pat.add dash
  var total = 0.0
  for d in pat: total += d
  if total <= 0: return polys
  for p in polys:
    var pts = p.pts
    if p.closed: pts.add pts[0]
    var idx = 0; var rem = pat[0]; var on = true
    var off = offset mod total
    if off < 0: off += total
    while off > 0:
      if off >= rem: off -= rem; idx = (idx + 1) mod pat.len; rem = pat[idx]; on = idx mod 2 == 0
      else: rem -= off; off = 0
    var cur: seq[Pt]
    for i in 0..<pts.len - 1:
      let a = pts[i]; let b = pts[i + 1]; let L = (b - a).len
      if L < 1e-12: continue
      var pos = 0.0
      while pos < L - 1e-12:
        let take = min(rem, L - pos)
        if on:
          if cur.len == 0: cur.add a + (b - a) * (pos / L)
          cur.add a + (b - a) * ((pos + take) / L)
        pos += take; rem -= take
        if rem <= 1e-12:
          if on and cur.len > 0: result.add Poly(pts: cur); cur = @[]
          idx = (idx + 1) mod pat.len; rem = pat[idx]; on = idx mod 2 == 0
    if on and cur.len > 0: result.add Poly(pts: cur)

proc strokePolys*(polys: seq[Poly], width: float, cap: Cap, join: Join, dash: seq[float] = @[],
                  dashOffset = 0.0, miter = 4.0): seq[Poly] =
  let src = if dash.len > 0: dashPolys(polys, dash, dashOffset) else: polys
  let closedAfter = dash.len == 0
  for p in src: result.strokeLine(p.pts, p.closed and closedAfter, width / 2, cap, join, miter)
