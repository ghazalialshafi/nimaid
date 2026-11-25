## Recording scene graph exposing the same function names the painters already use (pvg_shape_*, pvg_scene_*, ...).
## One drawing pass can be replayed to PureVG (raster: PNG/GIF) or serialised to SVG (svg.nim).
import std/math
import purevg as real
export real.Pvg_Result, real.Pvg_Stroke_Cap, real.Pvg_Stroke_Join

type
  NodeKind* = enum nkScene, nkShape, nkText, nkPicture
  Cmd* = object
    op*: char                       ## 'M' 'L' 'C' 'Z'
    v*: array[6, float]
  Node* = ref object
    kind*: NodeKind
    kids*: seq[Node]
    tx*, ty*, sc*: float
    hasT*, hasS*: bool
    rot*: float          ## degrees, clockwise on screen; applied after scale, before translate
    opacity*: int
    cmds*: seq[Cmd]
    hasFill*: bool
    fill*: array[4, uint8]
    sw*: float
    hasStroke*: bool
    fillGrad*, strokeGrad*: real.Pvg_Gradient     ## optional linear gradients (override the solid colours)
    stroke*: array[4, uint8]
    dash*: seq[float]
    join*: Pvg_Stroke_Join
    cap*: Pvg_Stroke_Cap
    text*, font*: string
    size*: float
    color*: array[3, uint8]
    ax*, ay*: float
    svg*: string
    pw*, ph*: float
  Pvg_Paint* = Node


proc pvg_scene_new*(): Node = Node(kind: nkScene, opacity: 255)
proc pvg_shape_new*(): Node = Node(kind: nkShape, opacity: 255, sw: 0)
proc pvg_text_new*(): Node = Node(kind: nkText, opacity: 255)
proc pvg_picture_new*(): Node = Node(kind: nkPicture, opacity: 255)
proc pvg_scene_add*(s, c: Node): Pvg_Result =
  s.kids.add c
  PVG_RESULT_SUCCESS
proc pvg_paint_rel*(n: Node): Pvg_Result = PVG_RESULT_SUCCESS
proc pvg_paint_translate*(n: Node, x, y: cfloat): Pvg_Result =
  n.tx = float(x); n.ty = float(y); n.hasT = true
  PVG_RESULT_SUCCESS
proc pvg_paint_scale*(n: Node, s: cfloat): Pvg_Result =
  n.sc = float(s); n.hasS = true
  PVG_RESULT_SUCCESS
proc pvg_paint_rotate*(n: Node, deg: cfloat): Pvg_Result =
  n.rot = float(deg); PVG_RESULT_SUCCESS
proc pvg_paint_set_opacity*(n: Node, o: uint8): Pvg_Result =
  n.opacity = int(o)
  PVG_RESULT_SUCCESS

proc cmd(n: Node, op: char, a: varargs[float]) =
  var c = Cmd(op: op)
  for i, v in a: c.v[i] = v
  n.cmds.add c

proc pvg_shape_move_to*(n: Node, x, y: cfloat): Pvg_Result =
  n.cmd('M', float(x), float(y))
  PVG_RESULT_SUCCESS
proc pvg_shape_line_to*(n: Node, x, y: cfloat): Pvg_Result =
  n.cmd('L', float(x), float(y))
  PVG_RESULT_SUCCESS
proc pvg_shape_cubic_to*(n: Node, a, b, c, d, e, f: cfloat): Pvg_Result =
  n.cmd('C', float(a), float(b), float(c), float(d), float(e), float(f))
  PVG_RESULT_SUCCESS
proc pvg_shape_close*(n: Node): Pvg_Result =
  n.cmd('Z')
  PVG_RESULT_SUCCESS

const kappa = 0.5522847498

proc pvg_shape_append_rect*(n: Node, x, y, w, h, rx, ry: cfloat, cw: bool): Pvg_Result =
  let (x, y, w, h) = (float(x), float(y), float(w), float(h))
  var rx = min(float(rx), w / 2)
  var ry = min(float(ry), h / 2)
  if rx <= 0 or ry <= 0:
    n.cmd('M', x, y); n.cmd('L', x + w, y); n.cmd('L', x + w, y + h); n.cmd('L', x, y + h); n.cmd('Z')
  else:
    let kx = rx * kappa
    let ky = ry * kappa
    n.cmd('M', x + rx, y)
    n.cmd('L', x + w - rx, y)
    n.cmd('C', x + w - rx + kx, y, x + w, y + ry - ky, x + w, y + ry)
    n.cmd('L', x + w, y + h - ry)
    n.cmd('C', x + w, y + h - ry + ky, x + w - rx + kx, y + h, x + w - rx, y + h)
    n.cmd('L', x + rx, y + h)
    n.cmd('C', x + rx - kx, y + h, x, y + h - ry + ky, x, y + h - ry)
    n.cmd('L', x, y + ry)
    n.cmd('C', x, y + ry - ky, x + rx - kx, y, x + rx, y)
    n.cmd('Z')
  PVG_RESULT_SUCCESS

proc pvg_shape_append_circle*(n: Node, cx, cy, rx, ry: cfloat, cw: bool): Pvg_Result =
  let (cx, cy, rx, ry) = (float(cx), float(cy), float(rx), float(ry))
  let kx = rx * kappa
  let ky = ry * kappa
  n.cmd('M', cx + rx, cy)
  n.cmd('C', cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
  n.cmd('C', cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
  n.cmd('C', cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
  n.cmd('C', cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
  n.cmd('Z')
  PVG_RESULT_SUCCESS

proc pvg_shape_set_fill_color*(n: Node, r, g, b, a: uint8): Pvg_Result =
  n.hasFill = true
  n.fill = [r, g, b, a]
  PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_width*(n: Node, w: cfloat): Pvg_Result =
  n.sw = float(w)
  PVG_RESULT_SUCCESS
proc pvg_shape_set_fill_gradient*(n: Node, g: real.Pvg_Gradient): Pvg_Result =
  n.fillGrad = g; PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_gradient*(n: Node, g: real.Pvg_Gradient): Pvg_Result =
  n.strokeGrad = g; n.hasStroke = true; PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_color*(n: Node, r, g, b, a: uint8): Pvg_Result =
  n.hasStroke = true
  n.stroke = [r, g, b, a]
  PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_join*(n: Node, j: Pvg_Stroke_Join): Pvg_Result =
  n.join = j
  PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_cap*(n: Node, c: Pvg_Stroke_Cap): Pvg_Result =
  n.cap = c
  PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_dash*(n: Node, d: ptr cfloat, cnt: uint32, offset: cfloat): Pvg_Result =
  n.dash = @[]
  let a = cast[ptr UncheckedArray[cfloat]](d)
  for i in 0 ..< int(cnt): n.dash.add float(a[i])
  PVG_RESULT_SUCCESS

proc pvg_text_set_font*(n: Node, f: cstring): Pvg_Result =
  n.font = $f
  PVG_RESULT_SUCCESS
proc pvg_text_set_size*(n: Node, s: cfloat): Pvg_Result =
  n.size = float(s)
  PVG_RESULT_SUCCESS
proc pvg_text_set_text*(n: Node, t: cstring): Pvg_Result =
  n.text = $t
  PVG_RESULT_SUCCESS
proc pvg_text_set_color*(n: Node, r, g, b: uint8): Pvg_Result =
  n.color = [r, g, b]
  PVG_RESULT_SUCCESS
proc pvg_text_align*(n: Node, x, y: cfloat): Pvg_Result =
  n.ax = float(x); n.ay = float(y)
  PVG_RESULT_SUCCESS
proc pvg_picture_load_data*(n: Node, data: cstring, size: uint32, mime: cstring, rpath: cstring, copy: bool): Pvg_Result =
  n.svg = newString(int(size))
  if size > 0: copyMem(addr n.svg[0], data, int(size))
  PVG_RESULT_SUCCESS
proc pvg_picture_set_size*(n: Node, w, h: cfloat): Pvg_Result =
  n.pw = float(w); n.ph = float(h)
  PVG_RESULT_SUCCESS

# ---------------------------------------------------------------------------
# replay to PureVG
# ---------------------------------------------------------------------------
proc toReal(n: Node): real.Pvg_Paint =
  var p: real.Pvg_Paint
  case n.kind
  of nkScene:
    p = real.pvg_scene_new()
    for k in n.kids: discard real.pvg_scene_add(p, toReal(k))
  of nkShape:
    p = real.pvg_shape_new()
    for c in n.cmds:
      case c.op
      of 'M': discard real.pvg_shape_move_to(p, cfloat(c.v[0]), cfloat(c.v[1]))
      of 'L': discard real.pvg_shape_line_to(p, cfloat(c.v[0]), cfloat(c.v[1]))
      of 'C': discard real.pvg_shape_cubic_to(p, cfloat(c.v[0]), cfloat(c.v[1]), cfloat(c.v[2]), cfloat(c.v[3]), cfloat(c.v[4]), cfloat(c.v[5]))
      else: discard real.pvg_shape_close(p)
    if n.hasFill: discard real.pvg_shape_set_fill_color(p, n.fill[0], n.fill[1], n.fill[2], n.fill[3])
    if n.fillGrad != nil: discard real.pvg_shape_set_fill_gradient(p, n.fillGrad)
    if n.hasStroke and n.sw > 0:
      discard real.pvg_shape_set_stroke_width(p, cfloat(n.sw))
      discard real.pvg_shape_set_stroke_color(p, n.stroke[0], n.stroke[1], n.stroke[2], n.stroke[3])
      if n.strokeGrad != nil: discard real.pvg_shape_set_stroke_gradient(p, n.strokeGrad)
      discard real.pvg_shape_set_stroke_join(p, n.join)
      discard real.pvg_shape_set_stroke_cap(p, n.cap)
      if n.dash.len > 0:
        var d = newSeq[cfloat](n.dash.len)
        for i, v in n.dash: d[i] = cfloat(v)
        discard real.pvg_shape_set_stroke_dash(p, addr d[0], uint32(d.len), 0.0)
  of nkText:
    p = real.pvg_text_new()
    discard real.pvg_text_set_font(p, n.font.cstring)
    discard real.pvg_text_set_size(p, cfloat(n.size))
    discard real.pvg_text_set_text(p, n.text.cstring)
    discard real.pvg_text_set_color(p, n.color[0], n.color[1], n.color[2])
    discard real.pvg_text_align(p, cfloat(n.ax), cfloat(n.ay))
  of nkPicture:
    p = real.pvg_picture_new()
    if real.pvg_picture_load_data(p, n.svg.cstring, uint32(n.svg.len), "svg", nil, true) == real.PVG_RESULT_SUCCESS:
      discard real.pvg_picture_set_size(p, cfloat(n.pw), cfloat(n.ph))
  if n.hasT: discard real.pvg_paint_translate(p, cfloat(n.tx), cfloat(n.ty))
  if n.hasS: discard real.pvg_paint_scale(p, cfloat(n.sc))
  if n.rot != 0: discard real.pvg_paint_rotate(p, cfloat(n.rot))
  if n.opacity != 255: discard real.pvg_paint_set_opacity(p, uint8(n.opacity))
  p

proc renderRgba*(root: Node, w, h: int): seq[byte] =
  ## Rasterises with PureVG's software canvas (pvg_engine_init must have been called).
  var buf = newSeq[uint32](w * h)
  let canvas = real.pvg_swcanvas_create(real.PVG_ENGINE_OPTION_DEFAULT)
  discard real.pvg_swcanvas_set_target(canvas, addr buf[0], uint32(w), uint32(w), uint32(h), real.PVG_COLORSPACE_ABGR8888S)
  discard real.pvg_canvas_add(canvas, toReal(root))
  discard real.pvg_canvas_update(canvas)
  discard real.pvg_canvas_draw(canvas, true)
  discard real.pvg_canvas_sync(canvas)
  result = newSeq[byte](w * h * 4)
  copyMem(addr result[0], addr buf[0], w * h * 4)
  discard real.pvg_canvas_destroy(canvas)
