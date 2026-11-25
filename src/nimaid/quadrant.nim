## Quadrant charts (Mermaid `quadrantChart`): grammar from quadrant.jison, layout from quadrantBuilder.ts, drawing
## order from quadrantRenderer.ts.
import std/[strutils, math, options, json, tables]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  PointStyle = object
    radius: Option[float]
    color, strokeColor: Option[Color]
    strokeWidth: Option[float]
  QPoint = object
    text: string
    x, y: float
    cls: string
    style: PointStyle

proc parseStyles(s: string): PointStyle =
  for part in s.split(','):
    let ci = part.find(':')
    if ci <= 0: continue
    let k = part[0 ..< ci].strip()
    let v = part[ci + 1 .. ^1].strip()
    case k
    of "radius":
      try: result.radius = some(float(parseInt(v))) except ValueError: raise newException(ChartError, "radius must be a valid number")
    of "color": result.color = parseCssColor(v)
    of "stroke-color": result.strokeColor = parseCssColor(v)
    of "stroke-width":
      try: result.strokeWidth = some(parseFloat(v.replace("px", "")))
      except ValueError: raise newException(ChartError, "stroke-width must be a valid number with px")
    else: raise newException(ChartError, "style named " & k & " is not supported.")

proc quadrantScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  var title = fmTitle
  var xl, xr, yb, yt = ""
  var quad: array[4, string]
  var points: seq[QPoint]
  var classes = initTable[string, PointStyle]()
  var started = false
  for rawLine in text.replace("\r\n", "\n").split({'\n', ';'}):
    var l = rawLine
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    let t = l.strip()
    if t.len == 0: continue
    let low = t.toLowerAscii
    if not started:
      if not low.startsWith("quadrantchart"): raise newException(ChartError, "Parse error: expecting 'quadrantChart'")
      started = true; continue
    if low.startsWith("title"): title = t[5 .. ^1].strip(); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    if low.startsWith("classdef"):
      let rest = t[8 .. ^1].strip()
      let sp = rest.find({' ', '\t'})
      if sp > 0: classes[rest[0 ..< sp]] = parseStyles(rest[sp .. ^1])
      continue
    proc axisTexts(rest: string): (string, string) =
      let ai = rest.find("-->")
      if ai < 0: return (unquote(rest), "")
      let right = rest[ai ..< rest.len].replace("-", "").replace(">", "").strip()
      let left = unquote(rest[0 ..< ai])
      if right.len == 0: return (left & " \u27F6 ", "")
      (left, unquote(right))
    if low.startsWith("x-axis"): (xl, xr) = axisTexts(t[6 .. ^1].strip()); continue
    if low.startsWith("y-axis"): (yb, yt) = axisTexts(t[6 .. ^1].strip()); continue
    var matched = false
    for q in 1 .. 4:
      if low.startsWith("quadrant-" & $q):
        quad[q - 1] = unquote(t[10 .. ^1]); matched = true
    if matched: continue
    # point:  Name[:::class]: [x, y] [styles]
    let ob = t.find('[')
    let cb = t.find(']')
    if ob < 0 or cb < ob: raise newException(ChartError, "Parse error: unexpected '" & t & "'")
    var name = t[0 ..< ob].strip()
    if not name.endsWith(":"): raise newException(ChartError, "Parse error: expecting ':' before '[' in '" & t & "'")
    name = name[0 ..< name.len - 1].strip()
    var cls = ""
    let ci = name.find(":::")
    if ci >= 0: cls = name[ci + 3 .. ^1].strip(); name = name[0 ..< ci].strip()
    let xy = t[ob + 1 ..< cb].split(',')
    if xy.len != 2: raise newException(ChartError, "Parse error: a point needs [x, y]")
    var px, py: float
    try: px = parseFloat(xy[0].strip()); py = parseFloat(xy[1].strip())
    except ValueError: raise newException(ChartError, "Parse error: point coordinates must be numbers between 0 and 1")
    if px < 0 or px > 1 or py < 0 or py > 1:
      raise newException(ChartError, "Parse error: point coordinates must be between 0 and 1")
    points.insert(QPoint(text: unquote(name), x: px, y: py, cls: cls, style: parseStyles(t[cb + 1 .. ^1].strip().strip(chars = {','}))), 0)  # Mermaid prepends

  let qc = cv.cfg.cfgSub("quadrantChart")
  let W = qc.cfgFloat("chartWidth", 500)
  let H = qc.cfgFloat("chartHeight", 500)
  let titlePad = qc.cfgFloat("titlePadding", 10)
  let titlePx = qc.cfgFloat("titleFontSize", 20)
  let qPad = qc.cfgFloat("quadrantPadding", 5)
  let xPad = qc.cfgFloat("xAxisLabelPadding", 5)
  let yPad = qc.cfgFloat("yAxisLabelPadding", 5)
  let xPx = qc.cfgFloat("xAxisLabelFontSize", 16)
  let yPx = qc.cfgFloat("yAxisLabelFontSize", 16)
  let qLabelPx = qc.cfgFloat("quadrantLabelFontSize", 16)
  let qTopPad = qc.cfgFloat("quadrantTextTopPadding", 5)
  let pTextPad = qc.cfgFloat("pointTextPadding", 5)
  let pPx = qc.cfgFloat("pointLabelFontSize", 12)
  let pRad = qc.cfgFloat("pointRadius", 5)
  var xPos = qc.cfgStr("xAxisPosition", "top")
  let yPos = qc.cfgStr("yAxisPosition", "left")
  let intW = qc.cfgFloat("quadrantInternalBorderStrokeWidth", 1)
  let extW = qc.cfgFloat("quadrantExternalBorderStrokeWidth", 2)

  let showX = qc.cfgBool("showXAxis", true) and (xl.len > 0 or xr.len > 0)
  let showY = qc.cfgBool("showYAxis", true) and (yt.len > 0 or yb.len > 0)
  let showTitle = qc.cfgBool("showTitle", true) and title.len > 0
  if points.len > 0: xPos = "bottom"
  let xSpace = xPad * 2 + xPx
  let xTop = if xPos == "top" and showX: xSpace else: 0.0
  let xBottom = if xPos == "bottom" and showX: xSpace else: 0.0
  let ySpace = yPad * 2 + yPx
  let yLeft = if yPos == "left" and showY: ySpace else: 0.0
  let yRight = if yPos == "right" and showY: ySpace else: 0.0
  let titleTop = if showTitle: titlePx + titlePad * 2 else: 0.0
  let qLeft = qPad + yLeft
  let qTop = qPad + xTop + titleTop
  let qW = W - qPad * 2 - yLeft - yRight
  let qH = H - qPad * 2 - xTop - xBottom - titleTop
  let hw = qW / 2
  let hh = qH / 2

  let root = pvg_scene_new()
  # ---- quadrants (rect + label); order: quadrant 1 (top right), 2 (top left), 3 (bottom left), 4 (bottom right)
  let qx = [qLeft + hw, qLeft, qLeft, qLeft + hw]
  let qy = [qTop, qTop, qTop + hh, qTop + hh]
  for i in 0 .. 3:
    kRect(root, qx[i], qy[i], hw, hh, some(cv.color("quadrant" & $(i + 1) & "Fill")), none(Color), 0)
    let tx = qx[i] + hw / 2
    if points.len == 0:
      drawT(root, quad[i], tx, qy[i] + hh / 2, qLabelPx, cv.color("quadrant" & $(i + 1) & "TextFill"), vMiddle, aMiddle)
    else:
      drawT(root, quad[i], tx, qy[i] + qTopPad, qLabelPx, cv.color("quadrant" & $(i + 1) & "TextFill"), vHang, aMiddle)
  # ---- borders
  let eh = extW / 2
  let ext = cv.color("quadrantExternalBorderStrokeFill")
  let inn = cv.color("quadrantInternalBorderStrokeFill")
  proc ln(x1, y1, x2, y2: float, c: Color, w: float) = kPath(root, [(x1, y1), (x2, y2)], false, none(Color), some(c), w)
  ln(qLeft - eh, qTop, qLeft + qW + eh, qTop, ext, extW)
  ln(qLeft + qW, qTop + eh, qLeft + qW, qTop + qH - eh, ext, extW)
  ln(qLeft - eh, qTop + qH, qLeft + qW + eh, qTop + qH, ext, extW)
  ln(qLeft, qTop + eh, qLeft, qTop + qH - eh, ext, extW)
  ln(qLeft + hw, qTop + eh, qLeft + hw, qTop + qH - eh, inn, intW)
  ln(qLeft + eh, qTop + hh, qLeft + qW - eh, qTop + hh, inn, intW)
  # ---- points
  for p in points:
    var st = p.style
    if p.cls.len > 0 and p.cls in classes:
      let cs = classes[p.cls]
      if st.radius.isNone: st.radius = cs.radius
      if st.color.isNone: st.color = cs.color
      if st.strokeColor.isNone: st.strokeColor = cs.strokeColor
      if st.strokeWidth.isNone: st.strokeWidth = cs.strokeWidth
    let px = qLeft + p.x * qW
    let py = qTop + qH - p.y * qH
    let fill = st.color.get(cv.color("quadrantPointFill"))
    let sh = pvg_shape_new()
    let r = st.radius.get(pRad)
    discard pvg_shape_append_circle(sh, cfloat(px), cfloat(py), cfloat(r), cfloat(r), true)
    styleShape(sh, some(fill), (if st.strokeWidth.get(0.0) > 0: some(st.strokeColor.get(cv.color("quadrantPointFill"))) else: none(Color)),
               st.strokeWidth.get(0.0))
    discard pvg_scene_add(root, sh)
    drawT(root, p.text, px, py + pTextPad, pPx, cv.color("quadrantPointTextFill"), vHang, aMiddle)
  # ---- axis labels
  let midX = xr.len > 0
  let midY = yt.len > 0
  let xAxisY = if xPos == "top": xPad + titleTop else: xPad + qTop + qH + qPad
  let xc = cv.color("quadrantXAxisTextFill")
  let yc = cv.color("quadrantYAxisTextFill")
  if xl.len > 0 and showX:
    drawT(root, xl, qLeft + (if midX: hw / 2 else: 0.0), xAxisY, xPx, xc, vHang, (if midX: aMiddle else: aStart))
  if xr.len > 0 and showX:
    drawT(root, xr, qLeft + hw + (if midX: hw / 2 else: 0.0), xAxisY, xPx, xc, vHang, (if midX: aMiddle else: aStart))
  let yAxisX = if yPos == "left": yPad else: yPad + qLeft + qW + qPad
  if yb.len > 0 and showY:
    drawT(root, yb, yAxisX, qTop + qH - (if midY: hh / 2 else: 0.0), yPx, yc, vHang, (if midY: aMiddle else: aStart), -90)
  if yt.len > 0 and showY:
    drawT(root, yt, yAxisX, qTop + hh - (if midY: hh / 2 else: 0.0), yPx, yc, vHang, (if midY: aMiddle else: aStart), -90)
  if showTitle:
    drawT(root, title, W / 2, titlePad, titlePx, cv.color("quadrantTitleFill"), vHang, aMiddle)
  (root, (minX: 0.0, minY: 0.0, maxX: W, maxY: H))
