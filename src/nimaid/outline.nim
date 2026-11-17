## Shape outlines at a node's final size, used for edge/border intersection.
import std/math
import geom

proc polyOutline*(shape: string, w, h: float): seq[Point] =
  ## Centered polygon (spans exactly w x h) or empty if shape is not polygonal.
  let hw = w / 2.0
  let hh = h / 2.0
  case shape
  of "diamond", "question":
    @[Point(x: 0, y: -hh), Point(x: hw, y: 0), Point(x: 0, y: hh), Point(x: -hw, y: 0)]
  of "hexagon":
    let m = h / 4.0
    @[Point(x: -hw + m, y: -hh), Point(x: hw - m, y: -hh), Point(x: hw, y: 0),
      Point(x: hw - m, y: hh), Point(x: -hw + m, y: hh), Point(x: -hw, y: 0)]
  of "trapezoid":
    let m = h / 3.0
    @[Point(x: -hw + m, y: -hh), Point(x: hw - m, y: -hh), Point(x: hw, y: hh), Point(x: -hw, y: hh)]
  of "inv_trapezoid":
    let m = h / 2.0
    @[Point(x: -hw, y: -hh), Point(x: hw, y: -hh), Point(x: hw - m, y: hh), Point(x: -hw + m, y: hh)]
  of "lean_right":
    let m = h / 2.0
    @[Point(x: -hw + m, y: -hh), Point(x: hw, y: -hh), Point(x: hw - m, y: hh), Point(x: -hw, y: hh)]
  of "lean_left":
    let m = h / 2.0
    @[Point(x: -hw, y: -hh), Point(x: hw - m, y: -hh), Point(x: hw, y: hh), Point(x: -hw + m, y: hh)]
  of "odd":
    let m = h / 4.0
    @[Point(x: -hw, y: -hh), Point(x: hw, y: -hh), Point(x: hw, y: hh), Point(x: -hw, y: hh), Point(x: -hw + m, y: 0)]
  of "stadium":
    let r = min(hh, hw)
    var pts: seq[Point]
    for i in 0 .. 12:   # right cap, top -> bottom
      let a = -PI / 2 + PI * float(i) / 12.0
      pts.add Point(x: hw - r + r * cos(a), y: r * sin(a))
    for i in 0 .. 12:   # left cap, bottom -> top
      let a = PI / 2 + PI * float(i) / 12.0
      pts.add Point(x: -hw + r + r * cos(a), y: r * sin(a))
    pts
  else:
    @[]

proc intersectShape*(shape: string, cx, cy, w, h: float, target: Point): Point =
  let node = (x: cx, y: cy, width: w, height: h)
  case shape
  of "circle", "mindmapCircle", "doublecircle":
    let r = intersectCircle(node, target)
    if r.x.isNaN or r.y.isNaN: Point(x: cx, y: cy) else: r
  of "ellipse":
    intersectEllipse(node, w / 2.0, h / 2.0, target)
  else:
    let poly = polyOutline(shape, w, h)
    if poly.len > 0: intersectPolygon(node, poly, target)
    else: intersectRect(node, target)


import shapes

proc intersectGeom*(g: Geom, cx, cy, w, h: float, target: Point): Point =
  ## Intersection of the segment centre->target with the node silhouette.
  let node = (x: cx, y: cy, width: w, height: h)
  case g.kind
  of okEllipse:
    let r = intersectEllipse(node, w / 2.0, h / 2.0, target)
    if r.x.isNaN or r.y.isNaN: Point(x: cx, y: cy) else: r
  of okPoly:
    if g.poly.len < 3: return intersectRect(node, target)
    var best = Point(x: cx, y: cy)
    var bestD = Inf
    let c = Point(x: cx, y: cy)
    for i in 0 ..< g.poly.len:
      let p1 = Point(x: cx + g.poly[i].x, y: cy + g.poly[i].y)
      let q = g.poly[(i + 1) mod g.poly.len]
      let p2 = Point(x: cx + q.x, y: cy + q.y)
      let ip = intersectLine(c, target, p1, p2)
      if ip.x.isNaN or ip.y.isNaN: continue
      let d = hypot(ip.x - target.x, ip.y - target.y)
      if d < bestD:
        bestD = d
        best = ip
    best
  of okRect:
    intersectRect(node, target)
