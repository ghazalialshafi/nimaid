## Node shape geometry for every shape in mermaid's registry.
## buildGeom(shape, textW, textH, padding) returns the final node size, drawing paths (centered on the
## origin, y down), the label offset and the outline used for edge/border intersection.
import std/math
import geom, types

type
  FillMode* = enum fmNode, fmNone, fmLine, fmBorder, fmBg, fmAlt

  Cmd* = object
    op*: char                     ## 'M' 'L' 'C' 'Z'
    x1*, y1*, x2*, y2*, x3*, y3*: float

  GPath* = object
    cmds*: seq[Cmd]
    fill*: FillMode
    stroke*: bool

  OutlineKind* = enum okRect, okPoly, okEllipse

  TextItem* = object
    text*: string
    x*, y*, size*: float       ## x = left edge (alignLeft) or centre
    alignLeft*: bool

  Geom* = object
    texts*: seq[TextItem]
    w*, h*: float
    paths*: seq[GPath]
    kind*: OutlineKind
    poly*: seq[Point]             ## centered silhouette when kind == okPoly
    labelDx*, labelDy*: float
    noLabel*: bool

# ---------------------------------------------------------------------------
# path builders
# ---------------------------------------------------------------------------
proc mv(p: var GPath, x, y: float) = p.cmds.add Cmd(op: 'M', x1: x, y1: y)
proc ln(p: var GPath, x, y: float) = p.cmds.add Cmd(op: 'L', x1: x, y1: y)
proc cu(p: var GPath, a, b, c, d, e, f: float) =
  p.cmds.add Cmd(op: 'C', x1: a, y1: b, x2: c, y2: d, x3: e, y3: f)
proc cl(p: var GPath) = p.cmds.add Cmd(op: 'Z')

proc newPath(fill = fmNode, stroke = true): GPath = GPath(fill: fill, stroke: stroke)

proc arcTo(p: var GPath, cx, cy, rx, ry, a0, a1: float) =
  ## Appends an elliptical arc (degrees, y down). Assumes the pen is already at the arc start.
  let total = a1 - a0
  let n = max(1, int(ceil(abs(total) / 90.0)))
  let step = degToRad(total / float(n))
  var a = degToRad(a0)
  for _ in 0 ..< n:
    let b = a + step
    let k = 4.0 / 3.0 * tan((b - a) / 4.0)
    let x0 = cx + rx * cos(a)
    let y0 = cy + ry * sin(a)
    let x3 = cx + rx * cos(b)
    let y3 = cy + ry * sin(b)
    p.cu(x0 - k * rx * sin(a), y0 + k * ry * cos(a),
         x3 + k * rx * sin(b), y3 - k * ry * cos(b), x3, y3)
    a = b

proc pt(cx, cy, rx, ry, a: float): (float, float) =
  (cx + rx * cos(degToRad(a)), cy + ry * sin(degToRad(a)))

proc rectPath(x, y, w, h: float, fill = fmNode, stroke = true): GPath =
  result = newPath(fill, stroke)
  result.mv(x, y); result.ln(x + w, y); result.ln(x + w, y + h); result.ln(x, y + h); result.cl()

proc rrectPath(x, y, w, h, r: float, fill = fmNode, stroke = true): GPath =
  let r = min(r, min(w, h) / 2)
  result = newPath(fill, stroke)
  result.mv(x + r, y)
  result.ln(x + w - r, y); result.arcTo(x + w - r, y + r, r, r, -90, 0)
  result.ln(x + w, y + h - r); result.arcTo(x + w - r, y + h - r, r, r, 0, 90)
  result.ln(x + r, y + h); result.arcTo(x + r, y + h - r, r, r, 90, 180)
  result.ln(x, y + r); result.arcTo(x + r, y + r, r, r, 180, 270)
  result.cl()

proc polyPath(pts: openArray[(float, float)], fill = fmNode, stroke = true, close = true): GPath =
  result = newPath(fill, stroke)
  for i, q in pts:
    if i == 0: result.mv(q[0], q[1]) else: result.ln(q[0], q[1])
  if close: result.cl()

proc ellipsePath(cx, cy, rx, ry: float, fill = fmNode, stroke = true): GPath =
  result = newPath(fill, stroke)
  result.mv(cx + rx, cy)
  result.arcTo(cx, cy, rx, ry, 0, 360)
  result.cl()

proc linePath(x1, y1, x2, y2: float): GPath =
  result = newPath(fmNone, true)
  result.mv(x1, y1); result.ln(x2, y2)

proc flatten(g: GPath, steps = 14): seq[Point] =
  var cx, cy = 0.0
  for c in g.cmds:
    case c.op
    of 'M', 'L':
      result.add Point(x: c.x1, y: c.y1)
      cx = c.x1; cy = c.y1
    of 'C':
      for i in 1 .. steps:
        let t = float(i) / float(steps)
        let u = 1 - t
        result.add Point(
          x: u*u*u*cx + 3*u*u*t*c.x1 + 3*u*t*t*c.x2 + t*t*t*c.x3,
          y: u*u*u*cy + 3*u*u*t*c.y1 + 3*u*t*t*c.y2 + t*t*t*c.y3)
      cx = c.x3; cy = c.y3
    else: discard

proc geomFrom(w, h: float, paths: seq[GPath], silhouette = 0, dx = 0.0, dy = 0.0): Geom =
  result = Geom(w: w, h: h, paths: paths, labelDx: dx, labelDy: dy)
  if paths.len > 0:
    result.kind = okPoly
    result.poly = flatten(paths[silhouette])
  else:
    result.kind = okRect

proc withPoly(g: Geom, pts: seq[Point]): Geom =
  result = g
  result.kind = okPoly
  result.poly = pts

proc rectGeom(w, h: float, r = 0.0): Geom =
  result = Geom(w: w, h: h, kind: okRect)
  result.paths = @[if r > 0: rrectPath(-w / 2, -h / 2, w, h, r) else: rectPath(-w / 2, -h / 2, w, h)]

proc circleGeom(r: float, fill = fmNode, hideLabel = false): Geom =
  result = Geom(w: 2 * r, h: 2 * r, kind: okEllipse, noLabel: hideLabel)
  result.paths = @[ellipsePath(0, 0, r, r, fill)]

proc wavePts(x1, x2, base, amp: float, n = 24): seq[(float, float)] =
  ## one full sine cycle from x1 to x2 around y = base (dips first, like a document)
  for i in 0 .. n:
    let t = float(i) / float(n)
    result.add (x1 + (x2 - x1) * t, base + amp * sin(2 * PI * t))

proc bracePath(x0, hh, r: float, towardsLeft: bool): GPath =
  ## vertical curly brace; the point is at x0 - (or +) r*2
  result = newPath(fmNone, true)
  let s = if towardsLeft: -1.0 else: 1.0
  # spine at x0, ends hook back towards +s*(-r) ; tip pokes out by r
  result.mv(x0 - s * r, -hh)
  result.cu(x0, -hh, x0, -hh, x0, -hh + r)
  result.ln(x0, -r)
  result.cu(x0, 0, x0 + s * r, 0, x0 + s * r, 0)
  result.cu(x0 + s * r, 0, x0, 0, x0, r)
  result.ln(x0, hh - r)
  result.cu(x0, hh, x0, hh, x0 - s * r, hh)

# ---------------------------------------------------------------------------
# the registry of geometries
# ---------------------------------------------------------------------------
proc buildGeom*(shape: string, tw, th, pd: float, verticalFlow = true): Geom =
  ## tw/th: measured label size; pd: node padding (mermaid default 8).
  let LX = pd * 2.0           # horizontal label padding used by rect-like shapes
  let LY = pd

  case shape
  of "squareRect", "rect", "composite", "rectWithTitle", "labelRect", "note", "block_arrow",
     "icon", "iconSquare", "iconCircle", "iconRounded", "imageSquare", "defaultMindmapNode",
     "collapsedGroup", "kanbanItem", "classBox", "erBox", "requirementBox":
    result = rectGeom(tw + 2 * LX, th + 2 * LY)

  of "roundedRect", "state":
    result = rectGeom(tw + 2 * pd, th + 2 * pd, 5)

  of "text":
    result = rectGeom(tw + pd, th + pd)
    result.paths = @[]

  of "stadium", "terminal", "pill":
    let h = th + 2 * pd
    let w = max(tw + h / 4 + 2 * pd, 1.5 * h)
    let r = h / 2
    var p = newPath()
    p.mv(-w / 2 + r, -h / 2); p.ln(w / 2 - r, -h / 2)
    p.arcTo(w / 2 - r, 0, r, r, -90, 90)
    p.ln(-w / 2 + r, h / 2)
    p.arcTo(-w / 2 + r, 0, r, r, 90, 270)
    p.cl()
    result = geomFrom(w, h, @[p])

  of "subroutine":
    let w = tw + 2 * LX
    let h = th + 2 * LY
    result = rectGeom(w, h)
    result.paths.add linePath(-w / 2 + 8, -h / 2, -w / 2 + 8, h / 2)
    result.paths.add linePath(w / 2 - 8, -h / 2, w / 2 - 8, h / 2)

  of "cylinder":
    let w = tw + 2 * pd
    let rx = w / 2
    let ry = rx / (2.5 + w / 50)
    let h = th + 2 * pd + ry
    let H = h + 2 * ry
    let top = -H / 2
    let bot = H / 2
    var body = newPath()
    body.mv(-rx, top + ry)
    body.arcTo(0, top + ry, rx, ry, 180, 360)
    body.ln(rx, bot - ry)
    body.arcTo(0, bot - ry, rx, ry, 0, 180)
    body.cl()
    var lip = newPath(fmNone, true)
    lip.mv(-rx, top + ry)
    lip.arcTo(0, top + ry, rx, ry, 180, 0)
    result = geomFrom(w, H, @[body, lip], 0, 0, ry / 2 + pd / 3)

  of "datastore":
    let w = tw + 2 * LX
    let h = th + 2 * LY
    result = Geom(w: w, h: h, kind: okRect)
    result.paths = @[rectPath(-w / 2, -h / 2, w, h, fmNode, false),
                     linePath(-w / 2, -h / 2, w / 2, -h / 2), linePath(-w / 2, h / 2, w / 2, h / 2)]

  of "folder":
    let w = max(tw + 2 * pd, 90.0)
    let content = th + 2 * pd
    let tab = max(min(content * 0.16, 14.0), 8.0)
    let H = content + tab
    let tabW = max(w * 0.38, 28.0)
    let top = -H / 2
    result = geomFrom(w, H, @[polyPath([(-w / 2, top), (-w / 2 + tabW, top), (-w / 2 + tabW, top + tab),
                                        (w / 2, top + tab), (w / 2, H / 2), (-w / 2, H / 2)])],
                      0, 0, tab / 2)

  of "bucket":
    let w = max(tw + 2 * pd, 80.0)
    let rim = max(min(w * 0.08, 12.0), 5.0)
    let H = th + 2 * pd + rim
    let topY = -H / 2 + rim
    let botY = H / 2
    let bw = w * 0.72
    var body = newPath()
    body.mv(-w / 2, topY); body.ln(-bw / 2, botY)
    body.arcTo(0, botY, bw / 2, rim, 180, 0)       # bottom rim bulges down
    body.ln(w / 2, topY)
    body.arcTo(0, topY, w / 2, rim, 0, -180)       # back of the top rim
    body.cl()
    let top = ellipsePath(0, topY, w / 2, rim)
    result = geomFrom(w, H, @[body, top], 0, 0, (topY + botY) / 2)

  of "browser", "consoleWindow":
    let bar = if shape == "browser": 18.0 else: 24.0
    let w = max(tw + 2 * pd, 90.0)
    let h = th + 2 * pd + bar
    var g = Geom(w: w, h: h, kind: okRect)
    g.paths = @[rrectPath(-w / 2, -h / 2, w, h, 12), linePath(-w / 2, -h / 2 + bar, w / 2, -h / 2 + bar)]
    for i in 0 .. 2:
      g.paths.add ellipsePath(-w / 2 + 12 + float(i) * 11, -h / 2 + bar / 2, 3, 3, fmLine, false)
    if shape == "browser":
      g.paths.add rrectPath(-w / 2 + 48, -h / 2 + 4, max(w - 56, 10.0), bar - 8, 3, fmBg)
    g.labelDy = bar / 2
    result = g

  of "person":
    let w = max(tw + 2 * pd, 100.0)
    let head = min(max(w * 0.23, 16.0), 56.0)
    let bodyH = max(th + 2 * pd, head * 1.5)
    let H = bodyH + 2 * head - head * 0.3
    var headP = ellipsePath(0, -H / 2 + head, head, head)
    let bodyTop = -H / 2 + 2 * head - head * 0.3
    var body = newPath()
    let br = min(w * 0.177, bodyH * 0.45)
    body.mv(-w / 2, H / 2); body.ln(-w / 2, bodyTop + br)
    body.arcTo(-w / 2 + br, bodyTop + br, br, br, 180, 270)
    body.ln(w / 2 - br, bodyTop)
    body.arcTo(w / 2 - br, bodyTop + br, br, br, -90, 0)
    body.ln(w / 2, H / 2); body.cl()
    result = Geom(w: w, h: H, kind: okRect, paths: @[body, headP], labelDy: (bodyTop + H / 2) / 2)

  of "circle", "circ":
    result = circleGeom(sqrt(tw * tw + th * th) / 2 + pd / 2)

  of "doublecircle":
    let inner = sqrt(tw * tw + th * th) / 2 + pd
    let outer = inner + 5
    result = Geom(w: 2 * outer, h: 2 * outer, kind: okEllipse)
    result.paths = @[ellipsePath(0, 0, outer, outer), ellipsePath(0, 0, inner, inner, fmNone)]

  of "ellipse":
    let rx = tw / 2 * 1.3 + pd * 1.5
    let ry = th / 2 * 1.3 + pd
    result = Geom(w: 2 * rx, h: 2 * ry, kind: okEllipse, paths: @[ellipsePath(0, 0, rx, ry)])

  of "bang":
    let hp = pd / 2
    let w = max(tw + 10 * hp, tw + 20)
    let h = max(th + 8 * hp, th + 20)
    var pts: seq[(float, float)]
    let n = 16
    for i in 0 ..< n * 2:
      let a = 2 * PI * float(i) / float(n * 2)
      let f = if i mod 2 == 0: 1.0 else: 0.78
      pts.add (cos(a) * w / 2 * f, sin(a) * h / 2 * f)
    result = geomFrom(w, h, @[polyPath(pts)])

  of "cloud":
    let hp = pd / 2
    let w = tw + 2 * hp + pd * 3
    let h = th + 2 * hp + pd * 2
    var pts: seq[(float, float)]
    let bumps = 8
    for i in 0 ..< 96:
      let a = 2 * PI * float(i) / 96.0
      let bump = 1.0 + 0.09 * abs(sin(a * float(bumps) / 2.0)) - 0.045
      pts.add (cos(a) * w / 2 * bump, sin(a) * h / 2 * bump)
    result = geomFrom(w, h, @[polyPath(pts)])

  of "question", "diamond", "decision":
    let s = tw + th + 2 * pd
    result = geomFrom(s, s, @[polyPath([(0.0, -s / 2), (s / 2, 0.0), (0.0, s / 2), (-s / 2, 0.0)])])

  of "hexagon", "hex", "prepare":
    let h = th + pd
    let m = h / 4
    let w = tw + 2 * m + pd
    result = geomFrom(w, h, @[polyPath([(-w / 2 + m, -h / 2), (w / 2 - m, -h / 2), (w / 2, 0.0),
                                        (w / 2 - m, h / 2), (-w / 2 + m, h / 2), (-w / 2, 0.0)])])

  of "lean_right", "lean-r":
    let h = th + pd
    let w = tw + pd
    let tot = w + h
    result = geomFrom(tot, h, @[polyPath([(-tot / 2 + h / 2 * 1.0, -h / 2) , (tot / 2, -h / 2),
                                          (tot / 2 - h / 2, h / 2), (-tot / 2, h / 2)])])
  of "lean_left", "lean-l":
    let h = th + pd
    let w = tw + pd
    let tot = w + h
    result = geomFrom(tot, h, @[polyPath([(-tot / 2, -h / 2), (tot / 2 - h / 2, -h / 2),
                                          (tot / 2, h / 2), (-tot / 2 + h / 2, h / 2)])])
  of "trapezoid", "trap-b":
    let h = th + pd
    let w = tw + pd
    let tot = w + h
    result = geomFrom(tot, h, @[polyPath([(-tot / 2 + h / 2, -h / 2), (tot / 2 - h / 2, -h / 2),
                                          (tot / 2, h / 2), (-tot / 2, h / 2)])])
  of "inv_trapezoid", "trap-t":
    let h = th + 2 * pd
    let w = tw + 2 * pd
    let tot = w + h
    result = geomFrom(tot, h, @[polyPath([(-tot / 2, -h / 2), (tot / 2, -h / 2),
                                          (tot / 2 - h / 2, h / 2), (-tot / 2 + h / 2, h / 2)])])

  of "card":
    let w = tw + 2 * LX
    let h = th + 2 * LY
    let nt = 12.0
    result = geomFrom(w, h, @[polyPath([(-w / 2 + nt, -h / 2), (w / 2, -h / 2), (w / 2, h / 2),
                                        (-w / 2, h / 2), (-w / 2, -h / 2 + nt)])])

  of "shadedProcess":
    let fw = 8.0
    let w = tw + 2 * LX + fw
    let h = th + 2 * LY
    result = rectGeom(w, h)
    result.paths.add linePath(-w / 2 + fw, -h / 2, -w / 2 + fw, h / 2)
    result.labelDx = fw / 2

  of "stateStart":
    result = circleGeom(7, fmLine, true)
  of "stateEnd":
    result = Geom(w: 14, h: 14, kind: okEllipse, noLabel: true)
    result.paths = @[ellipsePath(0, 0, 7, 7, fmBg), ellipsePath(0, 0, 5, 5, fmLine, false)]
  of "filledCircle":
    result = circleGeom(7, fmBorder, true)
  of "anchor":
    result = circleGeom(3, fmBorder, true)
  of "crossedCircle":
    let r = 30.0
    result = circleGeom(r, fmNode, true)
    let d = r * cos(PI / 4)
    result.paths.add linePath(-d, -d, d, d)
    result.paths.add linePath(-d, d, d, -d)

  of "forkJoin":
    let (w, h) = if verticalFlow: (70.0, 10.0) else: (10.0, 70.0)
    result = Geom(w: w, h: h, kind: okRect, noLabel: true)
    result.paths = @[rectPath(-w / 2, -h / 2, w, h, fmLine, false)]

  of "choice":
    let s = 28.0
    result = geomFrom(s, s, @[polyPath([(0.0, -s / 2), (s / 2, 0.0), (0.0, s / 2), (-s / 2, 0.0)])])
    result.noLabel = true

  of "hourglass":
    let w = 30.0
    result = Geom(w: w, h: w, kind: okRect, noLabel: true)
    result.paths = @[polyPath([(-w / 2, -w / 2), (w / 2, -w / 2), (-w / 2, w / 2), (w / 2, w / 2)])]

  of "curlyBraceLeft", "curlyBraceRight", "curlyBraces":
    let w = tw + 2 * pd
    let h = th + 2 * pd
    let r = max(5.0, h * 0.1)
    var g = Geom(w: w + 2 * r * (if shape == "curlyBraces": 2.0 else: 1.0), h: h + 2 * r, kind: okRect)
    g.paths = @[rectPath(-w / 2, -h / 2, w, h, fmNone, false)]
    case shape
    of "curlyBraceLeft": g.paths.add bracePath(-w / 2 - r, h / 2, r, true); g.labelDx = r / 2
    of "curlyBraceRight": g.paths.add bracePath(w / 2 + r, h / 2, r, false); g.labelDx = -r / 2
    else:
      g.paths.add bracePath(-w / 2 - r, h / 2, r, true)
      g.paths.add bracePath(w / 2 + r, h / 2, r, false)
    result = g

  of "lightningBolt":
    let w = 35.0
    let h = 35.0
    let gap = 7.0
    # mermaid points are y-up; flip and centre
    let raw = [(w, 0.0), (0.0, h + gap / 2), (w - 2 * gap, h + gap / 2), (0.0, 2 * h),
               (w, h - gap / 2), (2 * gap, h - gap / 2)]
    var pts: seq[(float, float)]
    for p in raw: pts.add (p[0] - w / 2, h - p[1])
    result = geomFrom(w, 2 * h, @[polyPath(pts)])
    result.noLabel = true

  of "waveEdgedRectangle", "linedWaveEdgedRect", "taggedWaveEdgedRectangle", "multiWaveEdgedRectangle":
    let w = tw + 2 * LX
    let h0 = th + 2 * LY
    let amp = h0 / 8
    let H = h0 + 2 * amp
    let baseY = H / 2 - amp
    proc doc(dx, dy: float, fill = fmNode): GPath =
      var pts: seq[(float, float)]
      pts.add (-w / 2 + dx, -H / 2 + dy)
      pts.add (w / 2 + dx, -H / 2 + dy)
      for p in wavePts(w / 2, -w / 2, baseY, amp):
        pts.add (p[0] + dx, p[1] + dy)
      polyPath(pts, fill)
    case shape
    of "multiWaveEdgedRectangle":
      let off = 5.0
      result = Geom(w: w + 2 * off, h: H + 2 * off, kind: okRect)
      result.paths = @[doc(off * 2, -off * 2), doc(off, -off), doc(0, 0)]
      result.labelDy = -amp / 2 + off / 2
    of "linedWaveEdgedRect":
      result = geomFrom(w, H, @[doc(0, 0), linePath(-w / 2 + 8, -H / 2, -w / 2 + 8, baseY + amp * 0.9)], 0, 4, -amp / 2)
    of "taggedWaveEdgedRectangle":
      let tg = H * 0.2
      result = geomFrom(w, H, @[doc(0, 0),
                                polyPath([(w / 2 - tg, baseY), (w / 2, baseY - tg), (w / 2, baseY)], fmBorder)],
                        0, 0, -amp / 2)
    else:
      result = geomFrom(w, H, @[doc(0, 0)], 0, 0, -amp / 2)

  of "waveRectangle":
    let w = tw + 2 * LX
    let h0 = th + LY
    let amp = h0 / 8
    let H = h0 + 2 * amp
    var pts: seq[(float, float)]
    for p in wavePts(-w / 2, w / 2, -H / 2 + amp, -amp): pts.add p
    for p in wavePts(w / 2, -w / 2, H / 2 - amp, amp): pts.add p
    result = geomFrom(w, H, @[polyPath(pts)])

  of "halfRoundedRectangle":
    let h = th + 2 * pd
    let r = h / 2
    let clear = r - sqrt(max(0.0, r * r - (th / 2) * (th / 2)))
    let w = max(tw, 15.0) + clear * 2 + 2 * pd
    var p = newPath()
    p.mv(-w / 2, -h / 2); p.ln(w / 2 - r, -h / 2)
    p.arcTo(w / 2 - r, 0, r, r, -90, 90)
    p.ln(-w / 2, h / 2); p.cl()
    result = geomFrom(w, h, @[p])

  of "tiltedCylinder":
    let h = th + pd
    let ry = h / 2
    let rx = ry / (2.5 + h / 50)
    let w = tw + rx + pd
    let xl = -w / 2 + rx
    let xr = w / 2 - rx
    var body = newPath()
    body.mv(xl, -ry); body.ln(xr, -ry)
    body.arcTo(xr, 0, rx, ry, -90, 90)
    body.ln(xl, ry)
    body.arcTo(xl, 0, rx, ry, 90, 270)
    body.cl()
    var inner = newPath(fmNone, true)
    inner.mv(xl, -ry)
    inner.arcTo(xl, 0, rx, ry, -90, 90)
    result = geomFrom(w, h, @[body, inner], 0, rx / 2, 0)

  of "linedCylinder":
    let w = tw + 2 * LX
    let rx = w / 2
    let ry = rx / (2.5 + w / 50)
    let h = th + ry + 2 * LY
    let H = h + 2 * ry
    let off = h * 0.1
    let top = -H / 2
    let bot = H / 2
    var body = newPath()
    body.mv(-rx, top + ry)
    body.arcTo(0, top + ry, rx, ry, 180, 360)
    body.ln(rx, bot - ry)
    body.arcTo(0, bot - ry, rx, ry, 0, 180)
    body.cl()
    var lip = newPath(fmNone, true)
    lip.mv(-rx, top + ry); lip.arcTo(0, top + ry, rx, ry, 180, 0)
    var lip2 = newPath(fmNone, true)
    lip2.mv(-rx, top + ry + off); lip2.arcTo(0, top + ry + off, rx, ry, 180, 0)
    result = geomFrom(w, H, @[body, lip, lip2], 0, 0, ry / 2 + off / 2)

  of "curvedTrapezoid":
    let h = th + 2 * pd
    let r = h / 2
    let w = tw + h / 2 + 2 * pd
    var p = newPath()
    p.mv(-w / 2 + h / 4, -h / 2); p.ln(w / 2 - r, -h / 2)
    p.arcTo(w / 2 - r, 0, r, r, -90, 90)
    p.ln(-w / 2 + h / 4, h / 2)
    p.cu(-w / 2 - h / 8, h / 4, -w / 2 - h / 8, -h / 4, -w / 2 + h / 4, -h / 2)
    p.cl()
    result = geomFrom(w, h, @[p], 0, h / 8, 0)

  of "dividedRectangle":
    let w = tw + 2 * pd
    let h0 = th + 2 * pd
    let off = h0 * 0.2
    let H = h0 + off
    result = rectGeom(w, H)
    result.paths.add linePath(-w / 2, -H / 2 + off, w / 2, -H / 2 + off)
    result.labelDy = off / 2

  of "triangle", "flippedTriangle":
    let w = (tw + 2 * pd) * 1.7
    let h = w + th
    let up = shape == "triangle"
    let pts = if up: @[(0.0, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
              else: @[(-w / 2, -h / 2), (w / 2, -h / 2), (0.0, h / 2)]
    result = geomFrom(w, h, @[polyPath(pts)])
    result.labelDy = (if up: h * 0.2 else: -h * 0.2)

  of "windowPane":
    let off = 10.0
    let w = tw + 2 * LX
    let h = th + 2 * LY
    result = Geom(w: w + off, h: h + off, kind: okRect)
    let x0 = -w / 2 - off / 2
    let y0 = -h / 2 - off / 2
    result.paths = @[rectPath(x0, y0, w + off, h + off),
                     linePath(x0 + off, y0, x0 + off, y0 + h + off),
                     linePath(x0, y0 + off, x0 + w + off, y0 + off)]
    result.labelDx = off / 2
    result.labelDy = off / 2

  of "trapezoidalPentagon":
    let w = tw + 2 * LX
    let h = th + 2 * LY
    result = geomFrom(w, h, @[polyPath([(-w / 2 * 0.8, -h / 2), (w / 2 * 0.8, -h / 2),
                                        (w / 2, -h / 2 * 0.6), (w / 2, h / 2), (-w / 2, h / 2),
                                        (-w / 2, -h / 2 * 0.6)])])

  of "slopedRect":
    let w = tw + 2 * LX
    let h0 = th + 2 * LY
    let slope = h0 / 2
    let H = h0 + slope
    result = geomFrom(w, H, @[polyPath([(-w / 2, -H / 2 + slope), (w / 2, -H / 2), (w / 2, H / 2), (-w / 2, H / 2)])],
                      0, 0, slope / 2)

  of "multiRect":
    let off = 5.0
    let w = tw + 2 * LX
    let h = th + 2 * LY
    result = Geom(w: w + 2 * off, h: h + 2 * off, kind: okRect)
    # three stacked rectangles, drawn back to front (front one is lowest-left)
    result.paths = @[rectPath(-w / 2 + 2 * off, -h / 2 - off, w, h),
                     rectPath(-w / 2 + off, -h / 2, w, h),
                     rectPath(-w / 2, -h / 2 + off, w, h)]
    result.labelDx = -off
    result.labelDy = off

  of "bowTieRect":
    let h = th + 2 * LY
    let ry = h / 2
    let sag = ry / (2.5 + h / 50)
    let w = tw + 2 * LX + sag
    var p = newPath()
    p.mv(-w / 2, -h / 2); p.ln(w / 2, -h / 2)
    p.arcTo(w / 2, 0, sag, ry, -90, -270)
    p.ln(-w / 2, h / 2)
    p.arcTo(-w / 2, 0, sag, ry, 90, -90)
    p.cl()
    result = geomFrom(w, h, @[p])

  of "taggedRect":
    let h = th + 2 * LY
    let tg = 0.2 * h
    let w = tw + 2 * LX + tg
    result = geomFrom(w, h, @[rectPath(-w / 2, -h / 2, w, h),
                              polyPath([(w / 2 - tg, h / 2), (w / 2, h / 2 - tg), (w / 2, h / 2)], fmBorder)])
    result.labelDx = -tg / 2
    result.kind = okRect

  of "rect_left_inv_arrow":
    let h = th + pd
    let notch = h / 4
    let w = tw + pd + notch
    result = geomFrom(w, h, @[polyPath([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2),
                                        (-w / 2 + notch, 0.0)])], 0, notch / 2, 0)

  else:
    result = rectGeom(tw + 2 * LX, th + 2 * LY)


# ---------------------------------------------------------------------------
# class / entity boxes: title + sections (class members) or table rows (ER)
# ---------------------------------------------------------------------------
proc buildBoxGeom*(spec: BoxSpec, tw: proc(s: string, size: float): float): Geom =
  let rowSize = 14.0
  let titleSize = 16.0
  let rowH = rowSize * 1.5
  let titleH = titleSize * 1.5
  var texts: seq[TextItem]
  var paths: seq[GPath]
  if spec.kind == "er":
    let pad = 8.0
    var ncols = 0
    for sec in spec.sections:
      for r in sec: ncols = max(ncols, r.len)
    var colW = newSeq[float](ncols)
    for sec in spec.sections:
      for r in sec:
        for c, cell in r: colW[c] = max(colW[c], tw(cell, rowSize) + 2 * pad)
    var tableW = 0.0
    for c in colW: tableW += c
    let w = max(max(tableW, tw(spec.title, titleSize) + 4 * pad), 80.0)
    if ncols > 0:
      let extra = (w - tableW) / float(ncols)
      for c in 0 ..< ncols: colW[c] += extra
    let headH = titleH + 12
    var rows: seq[seq[string]]
    for sec in spec.sections:
      for r in sec: rows.add r
    let rh = rowH + 10
    let h = headH + float(rows.len) * rh
    paths.add rectPath(-w / 2, -h / 2, w, h)
    for i in 0 ..< rows.len:
      if i mod 2 == 1:
        paths.add rectPath(-w / 2, -h / 2 + headH + float(i) * rh, w, rh, fmAlt, false)
    paths.add linePath(-w / 2, -h / 2 + headH, w / 2, -h / 2 + headH)
    var x = -w / 2
    for c in 0 ..< ncols - 1:
      x += colW[c]
      paths.add linePath(x, -h / 2 + headH, x, h / 2)
    texts.add TextItem(text: spec.title, x: 0, y: -h / 2 + headH / 2, size: titleSize)
    for i, r in rows:
      var cx = -w / 2
      for c, cell in r:
        if cell.len > 0:
          texts.add TextItem(text: cell, x: cx + pad, y: -h / 2 + headH + (float(i) + 0.5) * rh, size: rowSize, alignLeft: true)
        cx += colW[c]
    result = Geom(w: w, h: h, kind: okRect, paths: paths, noLabel: true, texts: texts)
  else:
    let pad = 12.0
    var w = tw(spec.title, titleSize) + 2 * pad
    if spec.annotation.len > 0: w = max(w, tw(spec.annotation, rowSize) + 2 * pad)
    for sec in spec.sections:
      for r in sec:
        if r.len > 0: w = max(w, tw(r[0], rowSize) + 2 * pad)
    w = max(w, 90.0)
    let headH = titleH + (if spec.annotation.len > 0: rowH else: 0.0) + 8
    var secH: seq[float]
    var total = headH
    for sec in spec.sections:
      let hh = max(float(sec.len) * rowH + 12, 14.0)
      secH.add hh
      total += hh
    if spec.sections.len == 0:
      total += 14
      secH.add 14
    let h = total
    paths.add rectPath(-w / 2, -h / 2, w, h)
    var y = -h / 2
    var ty = y + 4
    if spec.annotation.len > 0:
      texts.add TextItem(text: spec.annotation, x: 0, y: ty + rowH / 2, size: rowSize)
      ty += rowH
    texts.add TextItem(text: spec.title, x: 0, y: ty + titleH / 2, size: titleSize)
    y += headH
    paths.add linePath(-w / 2, y, w / 2, y)
    for si, sec in spec.sections:
      for i, r in sec:
        if r.len > 0: texts.add TextItem(text: r[0], x: -w / 2 + pad, y: y + 6 + (float(i) + 0.5) * rowH, size: rowSize, alignLeft: true)
      y += secH[si]
      if si < spec.sections.len - 1: paths.add linePath(-w / 2, y, w / 2, y)
    result = Geom(w: w, h: h, kind: okRect, paths: paths, noLabel: true, texts: texts)
