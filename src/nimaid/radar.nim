## Radar charts (Mermaid `radar-beta`): radar.langium + db.ts + renderer.ts + styles.ts.
import std/[strutils, math, options, json, tables]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  Axis = object
    name, label: string
  Curve = object
    name, label: string
    entries: seq[float]

proc splitTopLevel(s: string, sep: char): seq[string] =
  var depth = 0
  var q = '\0'
  var cur = ""
  for ch in s:
    if q != '\0':
      cur.add ch
      if ch == q: q = '\0'
    elif ch in {'"', '\''}: q = ch; cur.add ch
    elif ch in {'{', '['}: inc depth; cur.add ch
    elif ch in {'}', ']'}: dec depth; cur.add ch
    elif ch == sep and depth == 0: result.add cur; cur = ""
    else: cur.add ch
  if cur.strip().len > 0: result.add cur

proc nameLabel(s: string): (string, string) =
  ## `name["Label"]` or `name`
  let t = s.strip()
  let o = t.find('[')
  if o < 0: return (t, t)
  let c = t.rfind(']')
  (t[0 ..< o].strip(), unquote(t[o + 1 ..< (if c < o: t.len else: c)]))

proc parseRadar(text, fmTitle: string): (string, seq[Axis], seq[Curve], Table[string, string]) =
  var title = fmTitle
  var axes: seq[Axis]
  var curves: seq[Curve]
  var opts = initTable[string, string]()
  var started = false
  var pending = ""            # multi-line `curve ... { ... }`
  var lines: seq[string]
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    if l.strip().len > 0: lines.add l.strip()
  var i = 0
  while i < lines.len:
    var t = lines[i]
    inc i
    let low = t.toLowerAscii
    if not started:
      if not low.startsWith("radar"): raise newException(ChartError, "Parse error: expecting 'radar-beta'")
      started = true
      continue
    if low.startsWith("title"): title = t[5 .. ^1].strip(); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    if low.startsWith("axis "):
      for part in splitTopLevel(t[5 .. ^1], ','):
        let (n, lab) = nameLabel(part)
        if n.len > 0: axes.add Axis(name: n, label: lab)
      continue
    if low.startsWith("curve "):
      # gather until braces balance
      var body = t[6 .. ^1]
      while body.count('{') > body.count('}') and i < lines.len:
        body.add " " & lines[i]; inc i
      for part in splitTopLevel(body, ','):
        let o = part.find('{')
        let c = part.rfind('}')
        if o < 0 or c < o: raise newException(ChartError, "Parse error: a curve is 'curve name[\"Label\"]{1, 2, 3}'")
        let (n, lab) = nameLabel(part[0 ..< o])
        var cur = Curve(name: n, label: lab)
        let entries = part[o + 1 ..< c].split(',')
        var detailed = initTable[string, float]()
        var plain: seq[float]
        for e in entries:
          let et = e.strip()
          if et.len == 0: continue
          let ci = et.find({':', ' '})
          try:
            if ci > 0:
              detailed[et[0 ..< ci].strip()] = parseFloat(et[ci + 1 .. ^1].strip(chars = {':', ' '}))
            else: plain.add parseFloat(et)
          except ValueError: raise newException(ChartError, "Parse error: bad radar entry '" & et & "'")
        if detailed.len > 0:
          for a in axes:
            if a.name notin detailed: raise newException(ChartError, "Missing entry for axis " & a.label)
            cur.entries.add detailed[a.name]
        else: cur.entries = plain
        curves.add cur
      continue
    # options: showLegend true, ticks 5, max 100, min 0, graticule polygon (comma separated)
    for part in t.split(','):
      let w = part.strip().splitWhitespace()
      if w.len == 2 and w[0] in ["showLegend", "ticks", "max", "min", "graticule"]: opts[w[0]] = w[1]
      elif part.strip().len > 0: raise newException(ChartError, "Parse error: unexpected '" & part.strip() & "'")
  (title, axes, curves, opts)

proc closedRoundCurve(sh: Pvg_Paint, pts: seq[(float, float)], tension: float) =
  let n = pts.len
  discard pvg_shape_move_to(sh, cfloat(pts[0][0]), cfloat(pts[0][1]))
  for i in 0 ..< n:
    let p0 = pts[(i - 1 + n) mod n]
    let p1 = pts[i]
    let p2 = pts[(i + 1) mod n]
    let p3 = pts[(i + 2) mod n]
    discard pvg_shape_cubic_to(sh,
      cfloat(p1[0] + (p2[0] - p0[0]) * tension), cfloat(p1[1] + (p2[1] - p0[1]) * tension),
      cfloat(p2[0] - (p3[0] - p1[0]) * tension), cfloat(p2[1] - (p3[1] - p1[1]) * tension),
      cfloat(p2[0]), cfloat(p2[1]))
  discard pvg_shape_close(sh)

proc radarScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let (title, axes, curves, opts) = parseRadar(text, fmTitle)
  if axes.len < 3: raise newException(ChartError, "A radar chart needs at least three axes")
  let rc = cv.cfg.cfgSub("radar")
  let W = rc.cfgFloat("width", 600)
  let H = rc.cfgFloat("height", 600)
  let mt = rc.cfgFloat("marginTop", 50)
  let mr = rc.cfgFloat("marginRight", 50)
  let mb = rc.cfgFloat("marginBottom", 50)
  let ml = rc.cfgFloat("marginLeft", 50)
  let axisScale = rc.cfgFloat("axisScaleFactor", 1)
  let labelFactor = rc.cfgFloat("axisLabelFactor", 1.05)
  let tension = rc.cfgFloat("curveTension", 0.17)
  let showLegend = opts.getOrDefault("showLegend", "true") == "true"
  let ticks = min(int(parseFloat(opts.getOrDefault("ticks", "5"))), 10)
  let minV = parseFloat(opts.getOrDefault("min", "0"))
  var maxV = -Inf
  if "max" in opts: maxV = parseFloat(opts["max"])
  else:
    for c in curves:
      for e in c.entries: maxV = max(maxV, e)
  if maxV == -Inf or maxV == minV: maxV = minV + 1
  let polygon = opts.getOrDefault("graticule", "circle") == "polygon"
  let totalW = W + ml + mr
  let totalH = H + mt + mb
  let cx = ml + W / 2
  let cy = mt + H / 2
  let radius = min(W, H) / 2
  let root = pvg_scene_new()
  let textColor = cv.color("textColor")
  let gratColor = cv.color("radar.graticuleColor", rgba(0xDE, 0xDE, 0xDE))
  let gratOpacity = cv.num("radar.graticuleOpacity", 0.3)
  let axisColor = cv.color("radar.axisColor", rgba(0x33, 0x33, 0x33))
  let axisW = cv.num("radar.axisStrokeWidth", 2)
  let axisPx = cv.num("radar.axisLabelFontSize", 12)
  let legendPx = cv.num("radar.legendFontSize", 12)
  let curveOpacity = cv.num("radar.curveOpacity", 0.5)
  let curveW = cv.num("radar.curveStrokeWidth", 2)
  let n = axes.len

  # graticule
  for i in 0 ..< ticks:
    let r = radius * float(i + 1) / float(ticks)
    if not polygon:
      let sh = pvg_shape_new()
      discard pvg_shape_append_circle(sh, cfloat(cx), cfloat(cy), cfloat(r), cfloat(r), true)
      styleShape(sh, some(withAlpha(gratColor, gratOpacity)), some(gratColor), cv.num("radar.graticuleStrokeWidth", 1))
      discard pvg_scene_add(root, sh)
    else:
      var pts: seq[(float, float)]
      for j in 0 ..< n:
        let a = 2 * float(j) * PI / float(n) - PI / 2
        pts.add (cx + r * cos(a), cy + r * sin(a))
      kPath(root, pts, true, some(withAlpha(gratColor, gratOpacity)), some(gratColor), cv.num("radar.graticuleStrokeWidth", 1))
  # axes + labels
  for i, a in axes:
    let ang = 2 * float(i) * PI / float(n) - PI / 2
    let ca = cos(ang)
    let sa = sin(ang)
    kPath(root, [(cx, cy), (cx + radius * axisScale * ca, cy + radius * axisScale * sa)], false, none(Color), some(axisColor), axisW)
    let anchor = if ca > 0.01: aStart elif ca < -0.01: aEnd else: aMiddle
    let lx = cx + radius * labelFactor * ca + 4 * ca
    let ly = cy + radius * labelFactor * sa + 4 * sa
    if sa > 0.01: drawT(root, a.label, lx, ly, axisPx, textColor, vHang, anchor)
    elif sa < -0.01: drawTextPx(root, a.label, lx, ly, axisPx, textColor, anchor)
    else: drawTextPx(root, a.label, lx, ly + 0.346 * axisPx, axisPx, textColor, anchor)       # dominant-baseline: central
  # curves
  for ci, c in curves:
    if c.entries.len != n: continue
    let col = cv.color("cScale" & $(ci mod 12))
    var pts: seq[(float, float)]
    for i, e in c.entries:
      let ang = 2 * PI * float(i) / float(n) - PI / 2
      let r = radius * (clamp(e, minV, maxV) - minV) / (maxV - minV)
      pts.add (cx + r * cos(ang), cy + r * sin(ang))
    if polygon:
      kPath(root, pts, true, some(withAlpha(col, curveOpacity)), some(col), curveW)
    else:
      let sh = pvg_shape_new()
      var rel: seq[(float, float)]
      closedRoundCurve(sh, pts, tension)
      styleShape(sh, some(withAlpha(col, curveOpacity)), some(col), curveW)
      discard pvg_scene_add(root, sh)
  # legend
  if showLegend:
    let lx = cx + ((W / 2 + mr) * 3) / 4
    let ly = cy - ((H / 2 + mt) * 3) / 4
    for ci, c in curves:
      let col = cv.color("cScale" & $(ci mod 12))
      let y = ly + float(ci) * 20
      kRect(root, lx, y, 12, 12, some(withAlpha(col, curveOpacity)), some(col), 1)
      drawT(root, c.label, lx + 16, y, legendPx, textColor, vHang, aStart)
  # title: x = centre, hanging at y = -height/2 - marginTop (relative to the centre) => top of the canvas
  drawT(root, title, cx, 0, cv.num("fontSize", 16), textColor, vHang, aMiddle)
  (root, (minX: 0.0, minY: 0.0, maxX: totalW, maxY: totalH))
