## Pie charts (Mermaid `pie`): grammar from pie.langium, geometry/colours from pieRenderer.ts + themes.
import std/[strutils, math, options, tables, json]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type PieData = object
  title: string
  showData: bool
  labels: seq[string]
  values: seq[float]

proc parsePie(text: string, fmTitle: string): PieData =
  result.title = fmTitle
  var started = false
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    l = l.strip()
    if l.len == 0: continue
    if not started:
      if not l.startsWith("pie"): raise newException(ChartError, "Parse error: expecting 'pie'")
      started = true
      var rest = l[3 .. ^1].strip()
      if rest.startsWith("showData"): result.showData = true; rest = rest[8 .. ^1].strip()
      if rest.toLowerAscii.startsWith("title"): result.title = rest[5 .. ^1].strip()
      elif rest.len > 0: raise newException(ChartError, "Parse error: unexpected '" & rest & "' after 'pie'")
      continue
    let low = l.toLowerAscii
    if low.startsWith("title ") or low == "title": result.title = l[5 .. ^1].strip(); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    # "label" : value
    if l[0] notin {'"', '\''}: raise newException(ChartError, "Parse error: expecting a quoted label, got '" & l & "'")
    let q = l[0]
    let e = l.find(q, 1)
    if e < 0: raise newException(ChartError, "Parse error: unterminated label in '" & l & "'")
    let label = l[1 ..< e]
    let rest = l[e + 1 .. ^1].strip()
    if not rest.startsWith(":"): raise newException(ChartError, "Parse error: expecting ':' after \"" & label & "\"")
    let v = num2(rest[1 .. ^1], "\"" & label & "\"")
    if v < 0:
      raise newException(ChartError, "\"" & label & "\" has invalid value: " & fmtNum(v) &
                         ". Negative values are not allowed in pie charts. All slice values must be >= 0.")
    if label notin result.labels:       # first occurrence wins, like Mermaid's Map
      result.labels.add label; result.values.add v

proc kRing*(sc: Pvg_Paint, cx, cy, ri, ro, a0, a1: float, fill, stroke: Option[Color], sw: float): Pvg_Paint =
  ## d3 arc with an inner radius: annular sector (or a full ring).
  let sh = pvg_shape_new()
  if a1 - a0 >= 2 * PI - 1e-6:
    let (ox, oy) = polar(cx, cy, ro, 0)
    discard pvg_shape_move_to(sh, cfloat(ox), cfloat(oy)); arcTo(sh, cx, cy, ro, 0, 2 * PI); discard pvg_shape_close(sh)
    let (ix, iy) = polar(cx, cy, ri, 2 * PI)
    discard pvg_shape_move_to(sh, cfloat(ix), cfloat(iy)); arcTo(sh, cx, cy, ri, 2 * PI, 0); discard pvg_shape_close(sh)
  else:
    let (ox, oy) = polar(cx, cy, ro, a0)
    discard pvg_shape_move_to(sh, cfloat(ox), cfloat(oy))
    arcTo(sh, cx, cy, ro, a0, a1)
    let (ix, iy) = polar(cx, cy, ri, a1)
    discard pvg_shape_line_to(sh, cfloat(ix), cfloat(iy))
    arcTo(sh, cx, cy, ri, a1, a0)
    discard pvg_shape_close(sh)
  styleShape(sh, fill, stroke, sw)
  sh

proc pieScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let d = parsePie(text, fmTitle)
  const Height = 450.0
  const PieWidth = 450.0
  const Margin = 40.0
  const LegendRect = 18.0
  const LegendSpacing = 4.0
  let pc = cv.cfg.cfgSub("pie")
  let legendPosition = pc.cfgStr("legendPosition", "right")
  let textPos = pc.cfgFloat("textPosition", 0.75)
  let hole = block:
    let h = pc.cfgFloat("donutHole", 0)
    if h > 0 and h <= 0.9: h else: 0.0
  let highlight = pc.cfgStr("highlightSlice", "")
  let radius = min(PieWidth, Height) / 2 - Margin
  let cx = PieWidth / 2
  let cy = Height / 2
  let outerW = cv.num("pieOuterStrokeWidth", 2)

  # ---- legend measurements first (positions of the pie group depend on them)
  let legendPx = cv.num("pieLegendTextSize", 17)
  let legendH = LegendRect + LegendSpacing
  var longest = 0.0
  var entries: seq[string]
  for i, lab in d.labels:
    entries.add (if d.showData: lab & " [" & fmtNum(d.values[i]) & "]" else: lab)
    longest = max(longest, textW(entries[^1], legendPx))
  let totalLegendH = float(entries.len) * legendH
  var chartH = Height
  var chartW = PieWidth + Margin
  var pdx, pdy = 0.0                                   # translation of the pie sub-group
  case legendPosition
  of "top": chartH += totalLegendH; pdy = totalLegendH + legendH
  of "bottom": chartH += totalLegendH
  of "left": chartW += LegendRect + LegendSpacing + longest; pdx = longest + LegendRect + LegendSpacing
  of "center": discard
  else: chartW += LegendRect + LegendSpacing + longest
  let root = pvg_scene_new()
  let pcx = cx + pdx
  let pcy = cy + pdy

  let outer = pvg_shape_new()
  discard pvg_shape_append_circle(outer, cfloat(pcx), cfloat(pcy), cfloat(radius + outerW / 2), cfloat(radius + outerW / 2), true)
  styleShape(outer, none(Color), some(cv.color("pieOuterStrokeColor")), outerW)
  discard pvg_scene_add(root, outer)

  var total = 0.0
  for v in d.values: total += v
  var colors: seq[Color]
  for i in 1 .. 12: colors.add cv.color("pie" & $i)
  # d3 pie over the slices >= 1 %, angles proportional to the *filtered* sum
  var idx: seq[int]
  var fsum = 0.0
  for i, v in d.values:
    if total > 0 and v / total * 100 >= 1: idx.add i; fsum += v
  let strokeC = cv.color("pieStrokeColor"); let strokeW = cv.num("pieStrokeWidth", 2)
  let opacity = uint8(round(clamp(cv.num("pieOpacity", 0.7), 0.0, 1.0) * 255))
  var a = 0.0
  var labels: seq[(float, float, string)]
  for i in idx:
    let sweep = d.values[i] / fsum * 2 * PI
    let pctStr = $int(floor(d.values[i] / total * 100 + 0.5))
    if pctStr != "0":
      # `.pieCircle { opacity }` applies to each slice element on its own
      let g = pvg_scene_new()
      if hole > 0:
        discard pvg_scene_add(g, kRing(g, pcx, pcy, hole * radius, radius, a, a + sweep, some(colors[i mod 12]), some(strokeC), strokeW))
      else:
        kWedge(g, pcx, pcy, radius, a, a + sweep, some(colors[i mod 12]), some(strokeC), strokeW)
      if d.labels[i] == highlight and highlight.len > 0:      # .highlighted { scale: 1.05; opacity: 1 }
        discard pvg_paint_translate(g, cfloat(pcx * (1 - 1.05)), cfloat(pcy * (1 - 1.05)))
        discard pvg_paint_scale(g, 1.05)
      else:
        discard pvg_paint_set_opacity(g, opacity)
      discard pvg_scene_add(root, g)
      let (lx, ly) = polar(pcx, pcy, radius * textPos, a + sweep / 2)       # labelArc centroid
      labels.add (lx, ly, pctStr & "%")
    a += sweep
  for (lx, ly, t) in labels:
    drawTextPx(root, t, lx, ly, cv.num("pieSectionTextSize", 17), cv.color("pieSectionTextColor"))

  # title (x = centre of the 450 px canvas, baseline 25) - not affected by the legend position
  let titlePx = cv.num("pieTitleTextSize", 25)
  drawTextPx(root, d.title, cx, -(Height - 50) / 2 + cy, titlePx, cv.color("pieTitleTextColor"))

  for i, e in entries:
    var lx, ly: float
    case legendPosition
    of "center": lx = cx - longest / 2 - (LegendRect + LegendSpacing); ly = cy + float(i) * legendH - legendH * float(entries.len) / 2
    of "top": lx = cx - longest / 2 - (LegendRect + LegendSpacing); ly = cy + float(i) * legendH - radius
    of "bottom": lx = cx - longest / 2 - (LegendRect + LegendSpacing); ly = cy + float(i) * legendH + radius + legendH
    of "left": lx = cx - radius - (LegendRect + LegendSpacing); ly = cy + float(i) * legendH - legendH * float(entries.len) / 2
    else: lx = cx + 12 * LegendRect; ly = cy + float(i) * legendH - legendH * float(entries.len) / 2
    kRect(root, lx, ly, LegendRect, LegendRect, some(colors[i mod 12]), some(colors[i mod 12]), 1.0)
    drawTextPx(root, e, lx + LegendRect + LegendSpacing, ly + LegendRect - LegendSpacing, legendPx,
               cv.color("pieLegendTextColor"), aStart)

  let titleW = textW(d.title, titlePx)
  let vbx = min(0.0, PieWidth / 2 - titleW / 2)
  let right = max(chartW, PieWidth / 2 + titleW / 2)
  (root, (minX: vbx, minY: 0.0, maxX: right, maxY: chartH))
