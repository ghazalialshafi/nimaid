## Small drawing helpers shared by the non-graph diagrams (gantt, gitgraph, mindmap).
import std/[options, math, strutils]
import gfx, theme

proc hsl*(h, s, l: float, a = 255): Color =
  let c = (1 - abs(2 * l - 1)) * s
  let hp = (h mod 360.0) / 60.0
  let x = c * (1 - abs(hp mod 2.0 - 1))
  var (r, g, b) = (0.0, 0.0, 0.0)
  if hp < 1: (r, g, b) = (c, x, 0.0)
  elif hp < 2: (r, g, b) = (x, c, 0.0)
  elif hp < 3: (r, g, b) = (0.0, c, x)
  elif hp < 4: (r, g, b) = (0.0, x, c)
  elif hp < 5: (r, g, b) = (x, 0.0, c)
  else: (r, g, b) = (c, 0.0, x)
  let m = l - c / 2
  rgba(uint8(round((r + m) * 255)), uint8(round((g + m) * 255)), uint8(round((b + m) * 255)), uint8(a))

proc styleShape(sh: Pvg_Paint, fill, stroke: Option[Color], sw: float, dash: seq[float]) =
  if fill.isSome: discard pvg_shape_set_fill_color(sh, fill.get.r, fill.get.g, fill.get.b, fill.get.a)
  if stroke.isSome and sw > 0:
    discard pvg_shape_set_stroke_width(sh, cfloat(sw))
    discard pvg_shape_set_stroke_color(sh, stroke.get.r, stroke.get.g, stroke.get.b, stroke.get.a)
    discard pvg_shape_set_stroke_join(sh, PVG_STROKE_JOIN_ROUND)
    if dash.len > 0:
      var d = newSeq[cfloat](dash.len)
      for i, v in dash: d[i] = cfloat(v)
      discard pvg_shape_set_stroke_dash(sh, addr d[0], uint32(d.len), 0.0)

proc kRect*(sc: Pvg_Paint, x, y, w, h: float, fill, stroke: Option[Color], sw = 1.0, r = 0.0) =
  let sh = pvg_shape_new()
  discard pvg_shape_append_rect(sh, cfloat(x), cfloat(y), cfloat(w), cfloat(h), cfloat(r), cfloat(r), true)
  styleShape(sh, fill, stroke, sw, @[])
  discard pvg_scene_add(sc, sh)

proc kLine*(sc: Pvg_Paint, x1, y1, x2, y2: float, c: Color, w = 1.0, dash: seq[float] = @[], round = false) =
  let sh = pvg_shape_new()
  discard pvg_shape_move_to(sh, cfloat(x1), cfloat(y1))
  discard pvg_shape_line_to(sh, cfloat(x2), cfloat(y2))
  styleShape(sh, none(Color), some(c), w, dash)
  if round: discard pvg_shape_set_stroke_cap(sh, PVG_STROKE_CAP_ROUND)
  discard pvg_scene_add(sc, sh)

proc kCurve*(sc: Pvg_Paint, x1, y1, c1x, c1y, c2x, c2y, x2, y2: float, c: Color, w = 1.0, round = true) =
  let sh = pvg_shape_new()
  discard pvg_shape_move_to(sh, cfloat(x1), cfloat(y1))
  discard pvg_shape_cubic_to(sh, cfloat(c1x), cfloat(c1y), cfloat(c2x), cfloat(c2y), cfloat(x2), cfloat(y2))
  styleShape(sh, none(Color), some(c), w, @[])
  if round: discard pvg_shape_set_stroke_cap(sh, PVG_STROKE_CAP_ROUND)
  discard pvg_scene_add(sc, sh)

proc kCircle*(sc: Pvg_Paint, cx, cy, r: float, fill, stroke: Option[Color], sw = 1.0) =
  let sh = pvg_shape_new()
  discard pvg_shape_append_circle(sh, cfloat(cx), cfloat(cy), cfloat(r), cfloat(r), true)
  styleShape(sh, fill, stroke, sw, @[])
  discard pvg_scene_add(sc, sh)

proc kPoly*(sc: Pvg_Paint, pts: openArray[(float, float)], fill, stroke: Option[Color], sw = 1.0) =
  let sh = pvg_shape_new()
  for i, p in pts:
    if i == 0: discard pvg_shape_move_to(sh, cfloat(p[0]), cfloat(p[1]))
    else: discard pvg_shape_line_to(sh, cfloat(p[0]), cfloat(p[1]))
  discard pvg_shape_close(sh)
  styleShape(sh, fill, stroke, sw, @[])
  discard pvg_scene_add(sc, sh)
