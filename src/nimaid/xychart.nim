## XY charts (Mermaid `xychart` / `xychart-beta`): bar + line plots, band/linear axes, legend, horizontal orientation.
## Port of xychart.jison, xychartDb.ts and chartBuilder/* (orchestrator, axes, plots, title, legend).
import std/[strutils, math, options, json, tables, algorithm, sequtils]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  AxisKind = enum akBand, akLinear
  AxisPos = enum apLeft, apBottom, apTop
  PlotKind = enum pkBar, pkLine

  Plot = object
    kind: PlotKind
    title: string
    color: Color
    xs: seq[string]
    ys: seq[float]
    pointLabels: seq[string]

  AxisData = object
    kind: AxisKind
    title: string
    cats: seq[string]
    lo, hi: float

  AxisCfg = object
    showLabel, showTitle, showTick, showAxisLine: bool
    labelFontSize, labelPadding, titleFontSize, titlePadding, tickLength, tickWidth, axisLineWidth, labelRotation: float

  AxisColors = object
    title, label, tick, line: Color

  Axis = ref object
    kind: AxisKind
    cfg: AxisCfg
    col: AxisColors
    title: string
    cats: seq[string]
    lo, hi: float
    pos: AxisPos
    range: (float, float)
    outerPadding: float
    rx, ry, rw, rh: float
    showTitle, showLabel, showTick, showLine: bool
    titleTextH: float
    rotRad: float
    sA, sB: float            ## final scale range (after outer padding)

# ------------------------------------------------------------------ number helpers (d3 ticks, JS number formatting)
proc jsNum(v: float): string =
  if v == floor(v) and abs(v) < 1e15: return $int64(v)
  var t = formatFloat(v, ffDecimal, 10)
  t = t.strip(leading = false, chars = {'0'})
  t.strip(leading = false, chars = {'.'})

proc tickIncrement(start, stop: float, count: int): float =
  let step = (stop - start) / float(max(0, count))
  if step == 0 or step != step: return 0
  let power = floor(log10(step))
  let error = step / pow(10.0, power)
  let factor = if error >= sqrt(50.0): 10.0 elif error >= sqrt(10.0): 5.0 elif error >= sqrt(2.0): 2.0 else: 1.0
  if power >= 0: factor * pow(10.0, power) else: -pow(10.0, -power) / factor

proc d3Ticks(a, b: float, count: int): seq[float] =
  var start = a
  var stop = b
  if start == stop and count > 0: return @[start]
  let rev = stop < start
  if rev: swap(start, stop)
  let inc0 = tickIncrement(start, stop, count)
  if inc0 == 0 or classify(inc0) in {fcInf, fcNegInf}: return @[]
  if inc0 > 0:
    var r0 = round(start / inc0)
    var r1 = round(stop / inc0)
    if r0 * inc0 < start: r0 += 1
    if r1 * inc0 > stop: r1 -= 1
    for i in 0 .. int(r1 - r0): result.add (r0 + float(i)) * inc0
  else:
    let s = -inc0
    var r0 = round(start * s)
    var r1 = round(stop * s)
    if r0 / s < start: r0 += 1
    if r1 / s > stop: r1 -= 1
    for i in 0 .. int(r1 - r0): result.add (r0 + float(i)) / s
  if rev: result.reverse()

# ------------------------------------------------------------------ text dimensions (CSS px)
proc dim(texts: seq[string], px: float): (float, float) =
  var w = 0.0
  for t in texts: w = max(w, textW(t, px))
  (w, if texts.len > 0: px * 1.164 else: 0.0)

# ------------------------------------------------------------------ axis
proc ticksOf(a: Axis): seq[string] =
  if a.kind == akBand: return a.cats
  for v in d3Ticks(a.lo, a.hi, 10): result.add jsNum(v)

proc getRange(a: Axis): (float, float) = (a.range[0] + a.outerPadding, a.range[1] - a.outerPadding)

proc recalc(a: Axis) =
  let (r0, r1) = a.getRange()
  a.sA = r0; a.sB = r1

proc scaleVal(a: Axis, v: string): float =
  let (r0, r1) = a.getRange()
  if a.kind == akBand:
    let n = a.cats.len
    let i = a.cats.find(v)
    if i < 0 or n == 0: return r0
    let step = (r1 - r0) / float(max(1, n - 1))
    let start = r0 + ((r1 - r0) - step * float(n - 1)) * 0.5
    return start + step * float(i)
  let x = try: parseFloat(v) except ValueError: 0.0
  var (d0, d1) = (a.lo, a.hi)
  if a.pos == apLeft: swap(d0, d1)
  if d1 == d0: return r0 + (r1 - r0) * 0.5
  r0 + (x - d0) * (r1 - r0) / (d1 - d0)

proc tickDistance(a: Axis): float =
  let (r0, r1) = a.getRange()
  abs(r0 - r1) / float(max(1, a.ticksOf().len))

proc setRange(a: Axis, r: (float, float)) =
  a.range = r
  if a.pos in {apLeft}: a.rh = r[1] - r[0] else: a.rw = r[1] - r[0]
  a.recalc()

proc setPos(a: Axis, p: AxisPos) =
  a.pos = p
  a.setRange(a.range)

proc labelDim(a: Axis): (float, float) = dim(a.ticksOf(), a.cfg.labelFontSize)

proc calcSpace(a: Axis, availW, availH: float): (float, float) =
  let c = a.cfg
  if a.pos == apLeft:
    var aw = availW
    if c.showAxisLine and aw > c.axisLineWidth: aw -= c.axisLineWidth; a.showLine = true
    if c.showLabel:
      let (lw, lh) = a.labelDim()
      a.outerPadding = min(lh / 2, 0.2 * availH)
      let req = lw + c.labelPadding * 2
      if req <= aw: aw -= req; a.showLabel = true
    if c.showTick and aw >= c.tickLength: a.showTick = true; aw -= c.tickLength
    if c.showTitle and a.title.len > 0:
      let (_, th) = dim(@[a.title], c.titleFontSize)
      a.titleTextH = th
      let req = th + c.titlePadding * 2
      if req <= aw: aw -= req; a.showTitle = true
    a.rw = availW - aw; a.rh = availH
  else:
    var ah = availH
    if c.showAxisLine and ah > c.axisLineWidth: ah -= c.axisLineWidth; a.showLine = true
    if c.showLabel:
      let (lw, lh) = a.labelDim()
      a.outerPadding = min(lw / 2, 0.2 * availW)
      var req = lh
      if a.pos == apBottom and a.rotRad != 0:
        req = max(req, abs(sin(a.rotRad) * lw) + abs(cos(a.rotRad) * lh))
      req += c.labelPadding * 2
      if req <= ah: ah -= req; a.showLabel = true
    if c.showTick and ah >= c.tickLength: a.showTick = true; ah -= c.tickLength
    if c.showTitle and a.title.len > 0:
      let (_, th) = dim(@[a.title], c.titleFontSize)
      a.titleTextH = th
      let req = th + c.titlePadding * 2
      if req <= ah: ah -= req; a.showTitle = true
    a.rw = availW; a.rh = availH - ah
  a.recalc()
  (a.rw, a.rh)

proc recalcOuterPaddingForBars(a: Axis) =
  if 0.7 * a.tickDistance() > a.outerPadding * 2:
    a.outerPadding = floor(0.7 * a.tickDistance() / 2)
  a.recalc()

# ------------------------------------------------------------------ drawing primitives
proc seg(sc: Pvg_Paint, x0, y0, x1, y1: float, color: Color, w: float) =
  kPath(sc, [(x0, y0), (x1, y1)], false, none(Color), some(color), w)

proc drawAxis(sc: Pvg_Paint, a: Axis) =
  let c = a.cfg
  let ticks = a.ticksOf()
  case a.pos
  of apLeft:
    if a.showLine:
      let x = a.rx + a.rw - c.axisLineWidth / 2
      seg(sc, x, a.ry, x, a.ry + a.rh, a.col.line, c.axisLineWidth)
    if a.showLabel:
      let x = a.rx + a.rw - (if a.showLabel: c.labelPadding else: 0.0) - (if a.showTick: c.tickLength else: 0.0) - (if a.showLine: c.axisLineWidth else: 0.0)
      for t in ticks: drawT(sc, t, x, a.scaleVal(t), c.labelFontSize, a.col.label, vMiddle, aEnd)
    if a.showTick:
      let x = a.rx + a.rw - (if a.showLine: c.axisLineWidth else: 0.0)
      for t in ticks: seg(sc, x, a.scaleVal(t), x - c.tickLength, a.scaleVal(t), a.col.tick, c.tickWidth)
    if a.showTitle:
      drawT(sc, a.title, a.rx + c.titlePadding, a.ry + a.rh / 2, c.titleFontSize, a.col.title, vTop, aMiddle, 270)
  of apBottom:
    if a.showLine:
      let y = a.ry + c.axisLineWidth / 2
      seg(sc, a.rx, y, a.rx + a.rw, y, a.col.line, c.axisLineWidth)
    if a.showLabel:
      let (lw, lh) = a.labelDim()
      let offH = if a.rotRad == 0: 0.0 else: sin(a.rotRad) * lh / 2
      let offW = if a.rotRad == 0: 0.0 else: sin(a.rotRad) * lw / 2
      let y = a.ry + c.labelPadding + (if a.showTick: c.tickLength else: 0.0) + (if a.showLine: c.axisLineWidth else: 0.0) + abs(offW)
      for t in ticks: drawT(sc, t, a.scaleVal(t) + offH, y, c.labelFontSize, a.col.label, vTop, aMiddle, a.rotRad * 180 / PI)
    if a.showTick:
      let y = a.ry + (if a.showLine: c.axisLineWidth else: 0.0)
      for t in ticks: seg(sc, a.scaleVal(t), y, a.scaleVal(t), y + c.tickLength, a.col.tick, c.tickWidth)
    if a.showTitle:
      drawT(sc, a.title, a.range[0] + (a.range[1] - a.range[0]) / 2, a.ry + a.rh - c.titlePadding - a.titleTextH,
            c.titleFontSize, a.col.title, vTop, aMiddle)
  of apTop:
    if a.showLine:
      let y = a.ry + a.rh - c.axisLineWidth / 2
      seg(sc, a.rx, y, a.rx + a.rw, y, a.col.line, c.axisLineWidth)
    if a.showLabel:
      let y = a.ry + (if a.showTitle: a.titleTextH + c.titlePadding * 2 else: 0.0) + c.labelPadding
      for t in ticks: drawT(sc, t, a.scaleVal(t), y, c.labelFontSize, a.col.label, vTop, aMiddle)
    if a.showTick:
      let y = a.ry
      let lw = if a.showLine: c.axisLineWidth else: 0.0
      for t in ticks: seg(sc, a.scaleVal(t), y + a.rh - lw, a.scaleVal(t), y + a.rh - c.tickLength - lw, a.col.tick, c.tickWidth)
    if a.showTitle:
      drawT(sc, a.title, a.rx + a.rw / 2, a.ry + c.titlePadding, c.titleFontSize, a.col.title, vTop, aMiddle)

# ------------------------------------------------------------------ parsing
proc splitTop(s: string, sep: char): seq[string] =
  var cur = ""
  var q = '\0'
  for ch in s:
    if q != '\0':
      cur.add ch
      if ch == q: q = '\0'
    elif ch in {'"', '\''}: q = ch; cur.add ch
    elif ch == sep: result.add cur; cur = ""
    else: cur.add ch
  result.add cur

proc bracketOf(s: string): (int, int) =
  ## first '[' outside quotes and its matching ']' (or -1)
  var q = '\0'
  var o = -1
  for i, ch in s:
    if q != '\0':
      if ch == q: q = '\0'
    elif ch in {'"', '\''}: q = ch
    elif ch == '[' and o < 0: o = i
    elif ch == ']' and o >= 0: return (o, i)
  (o, -1)

proc rangeOf(s: string): Option[(string, float, float)] =
  ## "<title> a --> b"
  let ai = s.find("-->")
  if ai < 0: return none((string, float, float))
  let right = s[ai + 3 .. ^1].strip()
  var left = s[0 ..< ai].strip()
  var j = left.len
  while j > 0 and left[j - 1] in {'0'..'9', '.', '-', '+'}: dec j
  let loS = left[j .. ^1]
  if loS.len == 0: return none((string, float, float))
  try: some((left[0 ..< j].strip(), parseFloat(loS), parseFloat(right)))
  except ValueError: none((string, float, float))

type ParsedXY = object
  title: string
  horizontal: bool
  x: AxisData
  y: AxisData
  xSet, ySet: bool
  plots: seq[Plot]

proc parseXY(text, fmTitle: string, palette: seq[Color]): ParsedXY =
  result.title = fmTitle
  result.x = AxisData(kind: akBand)
  result.y = AxisData(kind: akLinear, lo: Inf, hi: -Inf)
  var started = false
  var plotIdx = 0
  var lines: seq[string]
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    for part in splitTop(l, ';'): lines.add part
  for raw in lines:
    let l = raw.strip()
    if l.len == 0: continue
    let low = l.toLowerAscii
    if not started:
      if low.startsWith("xychart"):
        started = true
        let rest = low["xychart".len .. ^1].replace("-beta", "").strip()
        if rest.startsWith("horizontal"): result.horizontal = true
        continue
      raise newException(ChartError, "Parse error: expecting 'xychart-beta'")
    if low.startsWith("title"):
      result.title = unquote(l[5 .. ^1]); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    if low.startsWith("x-axis"):
      let rest = l[6 .. ^1].strip()
      let (o, c) = bracketOf(rest)
      if o >= 0:
        result.x.title = unquote(rest[0 ..< o])
        var cats: seq[string]
        for p in splitTop(rest[o + 1 ..< (if c < 0: rest.len else: c)], ','):
          if p.strip().len > 0: cats.add unquote(p)
        result.x = AxisData(kind: akBand, title: result.x.title, cats: cats)
      else:
        let r = rangeOf(rest)
        if r.isSome:
          result.x = AxisData(kind: akLinear, title: unquote(r.get[0]), lo: r.get[1], hi: r.get[2])
        else: result.x.title = unquote(rest)
      result.xSet = o >= 0 or rangeOf(rest).isSome
      continue
    if low.startsWith("y-axis"):
      let rest = l[6 .. ^1].strip()
      let r = rangeOf(rest)
      if r.isSome:
        result.y = AxisData(kind: akLinear, title: unquote(r.get[0]), lo: r.get[1], hi: r.get[2]); result.ySet = true
      else: result.y.title = unquote(rest)
      continue
    var kind = pkBar
    var kw = 0
    if low.startsWith("bar"): kw = 3
    elif low.startsWith("line"): kind = pkLine; kw = 4
    else: raise newException(ChartError, "Parse error: unexpected '" & l & "'")
    let rest = l[kw .. ^1].strip()
    let (o, c) = bracketOf(rest)
    if o < 0: raise newException(ChartError, "Parse error: expecting '[' with data after '" & l[0 ..< kw] & "'")
    var vals: seq[float]
    var labels: seq[string]
    for p in splitTop(rest[o + 1 ..< (if c < 0: rest.len else: c)], ','):
      let t = p.strip()
      if t.len == 0: continue
      var numPart = t
      var lab = ""
      let sp = t.find({' ', '\t', '"', '\''})
      if sp > 0: numPart = t[0 ..< sp]; lab = unquote(t[sp .. ^1])
      vals.add num2(numPart, "plot data")
      labels.add lab
    var plot = Plot(kind: kind, title: unquote(rest[0 ..< o]), color: palette[plotIdx mod palette.len])
    # Mermaid: transformDataWithoutCategory
    if vals.len > 0:
      if not result.xSet:
        let pmin = if result.x.kind == akLinear: result.x.lo else: Inf
        let pmax = if result.x.kind == akLinear: result.x.hi else: -Inf
        result.x = AxisData(kind: akLinear, title: result.x.title, lo: min(pmin, 1.0), hi: max(pmax, float(vals.len)))
        result.xSet = true
      if result.x.kind == akBand and vals.len > result.x.cats.len:
        vals.setLen(result.x.cats.len); labels.setLen(result.x.cats.len)
      if not result.ySet:
        var mn = Inf
        var mx = -Inf
        for v in vals: mn = min(mn, v); mx = max(mx, v)
        result.y.lo = min(result.y.lo, mn); result.y.hi = max(result.y.hi, mx)
      if result.x.kind == akBand:
        for i, cat in result.x.cats:
          plot.xs.add cat
          plot.ys.add (if i < vals.len: vals[i] else: NaN)
      else:
        let step = if vals.len > 1: (result.x.hi - result.x.lo) / float(vals.len - 1) else: 0.0
        for i, v in vals:
          plot.xs.add (if vals.len == 1: jsNum(result.x.lo) else: jsNum(result.x.lo + float(i) * step))
          plot.ys.add v
      if kind == pkLine and labels.anyIt(it.len > 0): plot.pointLabels = labels
    result.plots.add plot
    inc plotIdx

# ------------------------------------------------------------------ scene
proc xychartScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let xc = cv.cfg.cfgSub("xyChart")
  var palette: seq[Color]
  for p in cv.str("xyChart.plotColorPalette", "#3498db,#2ecc71,#e74c3c").split(','):
    let c = parseCssColor(p)
    if c.isSome: palette.add c.get
  if palette.len == 0: palette.add rgba(52, 152, 219)
  var d = parseXY(text, fmTitle, palette)
  if d.plots.len == 0: raise newException(ChartError, "No Plot to render, please provide a plot with some data")
  let horizontal = d.horizontal or xc.cfgStr("chartOrientation", "vertical") == "horizontal"

  let W = xc.cfgFloat("width", 700)
  let H = xc.cfgFloat("height", 500)
  let titlePx = xc.cfgFloat("titleFontSize", 20)
  let titlePad = xc.cfgFloat("titlePadding", 10)
  let showTitle = xc.cfgBool("showTitle", true)
  let showLegend = xc.cfgBool("showLegend", true)
  let legendPx = xc.cfgFloat("legendFontSize", 14)
  let legendPad = xc.cfgFloat("legendPadding", 10)
  let reserved = xc.cfgFloat("plotReservedSpacePercent", 50)

  proc mkAxis(ad: AxisData, key, pre: string, rot: bool): Axis =
    let ac = xc.cfgSub(key)
    new(result)
    result.kind = ad.kind; result.title = ad.title; result.cats = ad.cats; result.lo = ad.lo; result.hi = ad.hi
    result.cfg = AxisCfg(showLabel: ac.cfgBool("showLabel", true), showTitle: ac.cfgBool("showTitle", true),
      showTick: ac.cfgBool("showTick", true), showAxisLine: ac.cfgBool("showAxisLine", true),
      labelFontSize: ac.cfgFloat("labelFontSize", 14), labelPadding: ac.cfgFloat("labelPadding", 5),
      titleFontSize: ac.cfgFloat("titleFontSize", 16), titlePadding: ac.cfgFloat("titlePadding", 5),
      tickLength: ac.cfgFloat("tickLength", 5), tickWidth: ac.cfgFloat("tickWidth", 2),
      axisLineWidth: ac.cfgFloat("axisLineWidth", 2), labelRotation: ac.cfgFloat("labelRotation", 0))
    result.col = AxisColors(title: cv.color("xyChart." & pre & "AxisTitleColor"), label: cv.color("xyChart." & pre & "AxisLabelColor"),
      tick: cv.color("xyChart." & pre & "AxisTickColor"), line: cv.color("xyChart." & pre & "AxisLineColor"))
    let r = result.cfg.labelRotation
    result.rotRad = if r >= -90 and r <= 90: r * PI / 180 else: 0.0
  let xAxis = mkAxis(d.x, "xAxis", "x", true)
  let yAxis = mkAxis(d.y, "yAxis", "y", false)

  # title
  var titleShown = false
  var titleW, titleBW, titleBH, titleBX = 0.0
  proc titleSpace(availW, availH: float): float =
    let (tw, th) = dim(@[d.title], titlePx)
    let wreq = max(tw, availW)
    let hreq = th + 2 * titlePad
    if hreq <= availH and showTitle and d.title.len > 0:
      titleBW = wreq; titleBH = hreq; titleW = tw; titleShown = true
    titleBH

  # legend
  var legendPlots: seq[Plot]
  var legendW, legendH, legendX, legendY = 0.0
  let markerSize = legendPx * 0.75
  let markerSpacing = legendPx * 0.35
  let itemSpacing = legendPx * 0.5
  proc legendSpace(availW, availH: float) =
    legendPlots = @[]
    if showLegend:
      for p in d.plots:
        if p.title.len > 0: legendPlots.add p
    if legendPlots.len == 0: return
    var tw = 0.0
    for p in legendPlots: tw = max(tw, textW(p.title, legendPx))
    let wreq = legendPad * 2 + markerSize + markerSpacing + tw
    let hreq = legendPad * 2 + float(legendPlots.len) * legendPx + float(legendPlots.len - 1) * itemSpacing
    if wreq <= availW and hreq <= availH: legendW = wreq; legendH = hreq
    else: legendPlots = @[]

  var availW = W
  var availH = H
  var chartW = floor(availW * reserved / 100)
  var chartH = floor(availH * reserved / 100)
  availW -= chartW; availH -= chartH
  var plotX, plotY = 0.0
  var titleYEnd = 0.0
  if not horizontal:
    let used = titleSpace(W, availH)
    plotY = used; availH -= used
    xAxis.setPos(apBottom)
    let (_, xh) = xAxis.calcSpace(availW, availH)
    availH -= xh
    yAxis.setPos(apLeft)
    let (yw, _) = yAxis.calcSpace(availW, availH)
    plotX = yw; availW -= yw
  else:
    titleYEnd = titleSpace(W, availH)
    availH -= titleYEnd
    xAxis.setPos(apLeft)
    let (xw, _) = xAxis.calcSpace(availW, availH)
    availW -= xw; plotX = xw
    yAxis.setPos(apTop)
    let (_, yh) = yAxis.calcSpace(availW, availH)
    availH -= yh
    plotY = titleYEnd + yh
  legendSpace(availW, chartH)
  availW -= legendW
  if availW > 0: chartW += availW
  if availH > 0: chartH += availH
  # title alignment
  let halfW = min(titleW, W) / 2
  let center = min(max((plotX + plotX + chartW) / 2, halfW), W - halfW)
  titleBX = center - halfW; titleBW = halfW * 2
  legendX = plotX + chartW
  legendY = plotY + max((chartH - legendH) / 2, 0)
  if not horizontal:
    xAxis.setRange((plotX, plotX + chartW)); xAxis.rx = plotX; xAxis.ry = plotY + chartH
    yAxis.setRange((plotY, plotY + chartH)); yAxis.rx = 0; yAxis.ry = plotY
  else:
    yAxis.setRange((plotX, plotX + chartW)); yAxis.rx = plotX; yAxis.ry = titleYEnd
    xAxis.setRange((plotY, plotY + chartH)); xAxis.rx = 0; xAxis.ry = plotY
  if d.plots.anyIt(it.kind == pkBar): xAxis.recalcOuterPaddingForBars()

  # ---- draw
  let root = pvg_scene_new()
  let bg = cv.color("xyChart.backgroundColor", rgba(255, 255, 255))
  kRect(root, 0, 0, W, H, some(bg), none(Color), 0)
  if titleShown:
    drawT(root, d.title, titleBX + titleBW / 2, titleBH / 2, titlePx, cv.color("xyChart.titleColor"), vMiddle, aMiddle)
  # plots
  let dataLabelColor = cv.color("xyChart.dataLabelColor")
  let showDataLabel = xc.cfgBool("showDataLabel", false)
  let outside = xc.cfgBool("showDataLabelOutsideBar", false)
  for pi, p in d.plots:
    var pts: seq[(float, float)]
    for i in 0 ..< p.xs.len:
      if p.ys[i] != p.ys[i]: continue
      pts.add (xAxis.scaleVal(p.xs[i]), yAxis.scaleVal(jsNum(p.ys[i])))
    case p.kind
    of pkLine:
      var path: seq[(float, float)]
      for (a, b) in pts: path.add (if horizontal: (b, a) else: (a, b))
      kPath(root, path, false, none(Color), some(p.color), 2)
      for i, lab in p.pointLabels:
        if lab.len == 0 or i >= pts.len: continue
        let (px0, py0) = pts[i]
        if horizontal: drawT(root, lab, py0 + 10, px0, 12, p.color, vMiddle, aStart)
        else: drawT(root, lab, px0, py0 - 10, 12, p.color, vMiddle, aMiddle)
    of pkBar:
      let bw = min(xAxis.outerPadding * 2, xAxis.tickDistance()) * (1 - 0.05)
      var rects: seq[(float, float, float, float, string)]
      for i, (a, b) in pts:
        let lab = jsNum(p.ys[i])
        if horizontal: rects.add (plotX, a - bw / 2, b - plotX, bw, lab)
        else: rects.add (a - bw / 2, b, bw, plotY + chartH - b, lab)
      for r in rects: kRect(root, r[0], r[1], r[2], r[3], some(p.color), none(Color), 0)
      if showDataLabel:
        var fs = Inf
        for r in rects:
          if r[2] <= 0 or r[3] <= 0: continue
          var f: float
          if horizontal:
            f = r[3] * 0.7
            while f > 0 and f * float(r[4].len) * 0.7 > r[2] - 10: f -= 1
          else:
            f = r[2] / (float(r[4].len) * 0.7)
            while f > 0 and not (r[0] + r[2] / 2 - f * float(r[4].len) * 0.7 / 2 >= r[0] and r[0] + r[2] / 2 + f * float(r[4].len) * 0.7 / 2 <= r[0] + r[2] and 10 + f <= r[3]): f -= 1
          fs = min(fs, f)
        if fs < Inf and floor(fs) > 0:
          fs = floor(fs)
          for r in rects:
            if r[2] <= 0 or r[3] <= 0: continue
            if horizontal:
              drawT(root, r[4], (if outside: r[0] + r[2] + 10 else: r[0] + r[2] - 10), r[1] + r[3] / 2, fs, dataLabelColor, vMiddle, (if outside: aStart else: aEnd))
            else:
              # 'hanging' baseline ~ top of the em box; 'auto' = alphabetic baseline
              if outside: drawTextPx(root, r[4], r[0] + r[2] / 2, r[1] - 10, fs, dataLabelColor, aMiddle)
              else: drawTextPx(root, r[4], r[0] + r[2] / 2, r[1] + 10 + AscentEm * fs, fs, dataLabelColor, aMiddle)
  # legend
  if legendPlots.len > 0:
    let startX = legendX + legendPad
    let startY = legendY + legendPad
    let rowH = legendPx + itemSpacing
    for i, p in legendPlots:
      if p.kind == pkBar:
        kRect(root, startX, startY + float(i) * rowH, markerSize, markerSize, some(p.color), none(Color), 0)
      else:
        let my = startY + float(i) * rowH + markerSize / 2
        seg(root, startX, my, startX + markerSize, my, p.color, 2)
    for i, p in legendPlots:
      drawT(root, p.title, startX + markerSize + markerSpacing, startY + float(i) * rowH + markerSize / 2, legendPx,
            cv.color("xyChart.legendTextColor"), vMiddle, aStart)
  xAxis.rx = xAxis.rx; drawAxis(root, xAxis)
  drawAxis(root, yAxis)
  (root, (minX: 0.0, minY: 0.0, maxX: W, maxY: H))
