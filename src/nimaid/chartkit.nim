## Drawing helpers for the "chart" diagrams (pie, xychart, timeline, quadrant, journey, ...).
## Geometry follows Mermaid's SVG renderers, which use CSS pixels; the engine takes text sizes in points,
## so everything here converts (px * 0.75) and places text by BASELINE like SVG does.
import std/[math, options, strutils]
import gfx, theme, textmetrics, drawkit

type
  ChartError* = object of CatchableError
  Anchor* = enum aStart, aMiddle, aEnd

const BaselineShift = 0.346   ## (ascent+descent)/2 of the bundled font, in em: line-box centre sits this far above the baseline

proc pt*(px: float): float = px * 0.75
proc textW*(text: string, px: float): float = measureLine(text, pt(px))

proc drawTextPx*(sc: Pvg_Paint, text: string, x, yBase, px: float, color: Color,
                 anchor = aMiddle, rotate = 0.0) =
  ## Text of `px` CSS pixels with its baseline at `yBase`, anchored like SVG `text-anchor`; optional rotation (degrees,
  ## clockwise) about (x, yBase).
  if text.len == 0: return
  let cy = yBase - BaselineShift * px
  if rotate == 0:
    case anchor
    of aMiddle: drawLabel(sc, text, x, cy, pt(px), color)
    of aStart: drawLabel(sc, text, x, cy, pt(px), color, alignLeft = true)
    of aEnd: drawLabel(sc, text, x - textW(text, px), cy, pt(px), color, alignLeft = true)
  else:
    let g = pvg_scene_new()
    discard pvg_paint_translate(g, cfloat(x), cfloat(yBase))
    discard pvg_paint_rotate(g, cfloat(rotate))
    drawLabel(g, text, (case anchor
                        of aMiddle: 0.0
                        of aStart: 0.0
                        of aEnd: -textW(text, px)), -BaselineShift * px, pt(px), color, alignLeft = anchor != aMiddle)
    discard pvg_scene_add(sc, g)

proc styleShape*(sh: Pvg_Paint, fill, stroke: Option[Color], sw = 1.0, dash: seq[float] = @[],
                 join = PVG_STROKE_JOIN_MITER, cap = PVG_STROKE_CAP_BUTT) =
  if fill.isSome: discard pvg_shape_set_fill_color(sh, fill.get.r, fill.get.g, fill.get.b, fill.get.a)
  if stroke.isSome and sw > 0:
    discard pvg_shape_set_stroke_width(sh, cfloat(sw))
    discard pvg_shape_set_stroke_color(sh, stroke.get.r, stroke.get.g, stroke.get.b, stroke.get.a)
    discard pvg_shape_set_stroke_join(sh, join)
    discard pvg_shape_set_stroke_cap(sh, cap)
    if dash.len > 0:
      var d = newSeq[cfloat](dash.len)
      for i, v in dash: d[i] = cfloat(v)
      discard pvg_shape_set_stroke_dash(sh, addr d[0], uint32(d.len), 0.0)

proc polar*(cx, cy, r, a: float): (float, float) =
  ## Angle measured clockwise from 12 o'clock (d3 convention).
  (cx + r * sin(a), cy - r * cos(a))

proc arcTo*(sh: Pvg_Paint, cx, cy, r, a0, a1: float) =
  ## Appends cubic Beziers from the current point (assumed at polar(a0)) to polar(a1), <= 90 degrees per piece.
  let n = max(1, int(ceil(abs(a1 - a0) / (PI / 2))))
  let da = (a1 - a0) / float(n)
  let k = 4.0 / 3.0 * tan(da / 4)
  for i in 0 ..< n:
    let t0 = a0 + da * float(i)
    let t1 = t0 + da
    let (x0, y0) = polar(cx, cy, r, t0)
    let (x3, y3) = polar(cx, cy, r, t1)
    discard pvg_shape_cubic_to(sh, cfloat(x0 + k * r * cos(t0)), cfloat(y0 + k * r * sin(t0)),
                               cfloat(x3 - k * r * cos(t1)), cfloat(y3 - k * r * sin(t1)), cfloat(x3), cfloat(y3))

proc kWedge*(sc: Pvg_Paint, cx, cy, r, a0, a1: float, fill, stroke: Option[Color], sw = 1.0) =
  let sh = pvg_shape_new()
  if a1 - a0 >= 2 * PI - 1e-6:
    discard pvg_shape_append_circle(sh, cfloat(cx), cfloat(cy), cfloat(r), cfloat(r), true)
  else:
    discard pvg_shape_move_to(sh, cfloat(cx), cfloat(cy))
    let (x0, y0) = polar(cx, cy, r, a0)
    discard pvg_shape_line_to(sh, cfloat(x0), cfloat(y0))
    arcTo(sh, cx, cy, r, a0, a1)
    discard pvg_shape_close(sh)
  styleShape(sh, fill, stroke, sw)
  discard pvg_scene_add(sc, sh)

proc kPath*(sc: Pvg_Paint, pts: openArray[(float, float)], closed: bool, fill, stroke: Option[Color],
            sw = 1.0, dash: seq[float] = @[], join = PVG_STROKE_JOIN_MITER, cap = PVG_STROKE_CAP_BUTT) =
  if pts.len < 2: return
  let sh = pvg_shape_new()
  discard pvg_shape_move_to(sh, cfloat(pts[0][0]), cfloat(pts[0][1]))
  for i in 1 ..< pts.len: discard pvg_shape_line_to(sh, cfloat(pts[i][0]), cfloat(pts[i][1]))
  if closed: discard pvg_shape_close(sh)
  styleShape(sh, fill, stroke, sw, dash, join, cap)
  discard pvg_scene_add(sc, sh)

proc num2*(s: string, what: string): float =
  try: parseFloat(s.strip())
  except ValueError: raise newException(ChartError, "Parse error: expected a number for " & what & ", got '" & s.strip() & "'")

proc fmtNum*(v: float, decimals = 2): string =
  ## Compact number formatting like JS (no trailing zeros).
  var t = formatFloat(v, ffDecimal, decimals)
  if '.' in t: t = t.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  if t == "-0" or t.len == 0: "0" else: t

type VPos* = enum vTop, vMiddle, vHang
const AscentEm* = 0.928    ## SVG 'text-before-edge': the baseline sits one ascent below y
const HangEm* = 0.74       ## SVG 'dominant-baseline: hanging' (0.8 x ascent)
const MidEm* = 0.27        ## SVG 'dominant-baseline: middle': the baseline sits ~half an x-height below y

proc drawT*(sc: Pvg_Paint, text: string, x, y, px: float, color: Color, vp: VPos, anchor: Anchor, rot = 0.0) =
  ## Text positioned like Mermaid's xychart/timeline renderers: (x, y) + vertical reference + anchor, optional rotation
  ## (degrees, clockwise) about (x, y).
  let dy = (case vp
            of vTop: AscentEm * px
            of vMiddle: MidEm * px
            of vHang: HangEm * px)
  if rot == 0:
    drawTextPx(sc, text, x, y + dy, px, color, anchor)
  else:
    let g = pvg_scene_new()
    discard pvg_paint_translate(g, cfloat(x), cfloat(y))
    discard pvg_paint_rotate(g, cfloat(rot))
    drawTextPx(g, text, 0, dy, px, color, anchor)
    discard pvg_scene_add(sc, g)

proc brighten*(c: Color, f: float): Color =
  ## CSS filter: brightness(f)
  rgba(uint8(clamp(float(c.r) * f, 0.0, 255.0)), uint8(clamp(float(c.g) * f, 0.0, 255.0)), uint8(clamp(float(c.b) * f, 0.0, 255.0)), c.a)

proc arrowHead*(sc: Pvg_Paint, x, y, dx, dy, w: float, color: Color) =
  ## Mermaid's marker 'M 0,0 V 4 L6,2 Z' (markerWidth 6, markerHeight 4, refX 5, refY 2) at the end (x, y) of a line
  ## with unit direction (dx, dy) and stroke width w (markers scale with the stroke width).
  let nx = -dy
  let ny = dx
  kPath(sc, [(x - 5 * w * dx + 2 * w * nx, y - 5 * w * dy + 2 * w * ny),
             (x - 5 * w * dx - 2 * w * nx, y - 5 * w * dy - 2 * w * ny),
             (x + w * dx, y + w * dy)], true, some(color), none(Color), 0)

proc unquote*(s: string): string =
  let t = s.strip()
  if t.len >= 2 and t[0] in {'"', '\''} and t[^1] == t[0]: t[1 ..< t.len - 1]
  elif t.len >= 4 and t.startsWith("`\"") and t.endsWith("\"`"): t[2 ..< t.len - 2]
  else: t

proc wrapWords*(text: string, width, px: float): seq[string] =
  ## Greedy word wrap at `width` px (text of `px` CSS pixels); `<br>` forces a break.
  var line = ""
  for word in text.replace("<br/>", "<br>").replace("<br />", "<br>").split({' ', '\t'}):
    if word.len == 0: continue
    var pieces = @[word]
    if "<br>" in word: pieces = word.replace("<br>", " <br> ").split(' ')
    for piece in pieces:
      if piece.len == 0: continue
      if piece == "<br>": result.add line; line = ""; continue
      let trial = if line.len == 0: piece else: line & " " & piece
      if line.len > 0 and textW(trial, px) > width: result.add line; line = piece
      else: line = trial
  result.add line

proc mixColor*(a, b: Color, t: float): Color =
  ## Linear blend: t = 0 -> a, t = 1 -> b (alpha mixed too).
  proc ch(x, y: uint8): uint8 = uint8(clamp(round(float(x) * (1 - t) + float(y) * t), 0.0, 255.0))
  rgba(ch(a.r, b.r), ch(a.g, b.g), ch(a.b, b.b), ch(a.a, b.a))

proc kShadow*(sc: Pvg_Paint, x, y, w, h, r: float, alpha = 0.10, dx = 0.0, dy = 2.0) =
  ## Soft card shadow: a few stacked translucent rounded rects.
  for i in 0 .. 3:
    let g = float(i) * 0.9
    kRect(sc, x + dx - g, y + dy - g + 0.5, w + 2 * g, h + 2 * g, some(rgba(0, 0, 0, uint8(alpha * 255 / float(i + 2)))), none(Color), 0, r + g)
