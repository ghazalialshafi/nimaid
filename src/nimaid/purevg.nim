## PureVG: pure-Nim 2D vector engine (shapes, strokes, text, SVG pictures) with a small C-style API.
## No shared library. Layers: purevg/core (math) -> raster -> stroke -> ttf -> this scene/canvas.
import std/[tables, os, math, strutils, unicode]
import purevg/[core, raster, stroke, ttf, svgload]

type
  Pvg_Result* = enum
    PVG_RESULT_SUCCESS = 0, PVG_RESULT_INVALID_ARGUMENT, PVG_RESULT_INSUFFICIENT_CONDITION,
    PVG_RESULT_FAILED_ALLOCATION, PVG_RESULT_MEMORY_CORRUPTION, PVG_RESULT_NOT_SUPPORTED,
    PVG_RESULT_SYSTEM_ERROR, PVG_RESULT_UNKNOWN = 255
  Pvg_Colorspace* = enum
    PVG_COLORSPACE_ABGR8888 = 0, PVG_COLORSPACE_ARGB8888, PVG_COLORSPACE_ABGR8888S,
    PVG_COLORSPACE_ARGB8888S, PVG_COLORSPACE_GRAYSCALE8, PVG_COLORSPACE_XBGR8888,
    PVG_COLORSPACE_XRGB8888, PVG_COLORSPACE_UNKNOWN = 255
  Pvg_Engine_Option* = enum
    PVG_ENGINE_OPTION_NONE = 0, PVG_ENGINE_OPTION_DEFAULT = 1,
    PVG_ENGINE_OPTION_SMART_RENDER = 2, PVG_ENGINE_OPTION_ALIASED = 4
  Pvg_Stroke_Cap* = enum PVG_STROKE_CAP_BUTT = 0, PVG_STROKE_CAP_ROUND, PVG_STROKE_CAP_SQUARE
  Pvg_Stroke_Join* = enum PVG_STROKE_JOIN_MITER = 0, PVG_STROKE_JOIN_ROUND, PVG_STROKE_JOIN_BEVEL
  Pvg_Point* = object
    x*, y*: cfloat
  Pvg_Text_Metrics* = object
    ascent*, descent*, linegap*, advance*: cfloat

  Pvg_Stop* = object
    offset*: float
    r*, g*, b*, a*: uint8
  Pvg_Gradient* = ref object
    ## linear gradient in the shape's own coordinate space (like SVG gradientUnits="userSpaceOnUse")
    x1*, y1*, x2*, y2*: float
    stops*: seq[Pvg_Stop]
    ramp: ref Ramp
  PaintKind = enum pkScene, pkShape, pkText, pkPicture
  PaintObj = object
    kind: PaintKind
    kids: seq[Pvg_Paint]
    tx, ty, sc, rot: float
    hasT, hasS: bool
    opacity: uint8
    segs: seq[Seg]
    fill: array[4, uint8]
    hasFill: bool
    fillGrad, strokeGrad: Pvg_Gradient
    stroke: array[4, uint8]
    sw: float
    dash: seq[float]
    cap: Pvg_Stroke_Cap
    join: Pvg_Stroke_Join
    text, font: string
    size: float
    color: array[3, uint8]
    ax, ay: float
    pw, ph: float
    pic: Picture
  Pvg_Paint* = ref PaintObj
  CanvasObj = object
    buf: ptr uint32
    stride, w, h: int
    cs: Pvg_Colorspace
    root: seq[Pvg_Paint]
  Pvg_Canvas* = ref CanvasObj
  Pvg_Animation* = pointer
  Pvg_Saver* = pointer

const DPI = 96.0 / 72.0
var fonts: Table[string, Font]
var defaultFont: Font

# ---------------------------------------------------------------- engine / fonts
proc pvg_engine_init*(threads: cuint): Pvg_Result = PVG_RESULT_SUCCESS
proc pvg_engine_term*(): Pvg_Result = PVG_RESULT_SUCCESS

proc pvg_font_load_data*(name: cstring, data: cstring, size: uint32, mimetype: cstring, copy: bool): Pvg_Result =
  var s = newString(size.int)
  if size > 0: copyMem(addr s[0], data, size.int)
  let f = parseFont(s)
  if f == nil: return PVG_RESULT_NOT_SUPPORTED
  fonts[$name] = f
  if defaultFont == nil: defaultFont = f
  PVG_RESULT_SUCCESS
proc pvg_font_load*(path: cstring): Pvg_Result =
  if not fileExists($path): return PVG_RESULT_INVALID_ARGUMENT
  let s = readFile($path)
  pvg_font_load_data(cstring(splitFile($path).name), cstring(s), uint32(s.len), "ttf", true)
proc pvg_font_unload*(path: cstring): Pvg_Result =
  fonts.del(splitFile($path).name); PVG_RESULT_SUCCESS

# ---------------------------------------------------------------- paint construction
proc newPaint(k: PaintKind): Pvg_Paint =
  ## PureVG defaults: stroke cap = square, join = bevel, miter limit 4
  Pvg_Paint(kind: k, opacity: 255, sc: 1, cap: PVG_STROKE_CAP_SQUARE, join: PVG_STROKE_JOIN_BEVEL)
proc pvg_scene_new*(): Pvg_Paint = newPaint(pkScene)
proc pvg_shape_new*(): Pvg_Paint = newPaint(pkShape)
proc pvg_text_new*(): Pvg_Paint = newPaint(pkText)
proc pvg_picture_new*(): Pvg_Paint = newPaint(pkPicture)
proc pvg_scene_add*(scene, paint: Pvg_Paint): Pvg_Result =
  if scene == nil or paint == nil or scene.kind != pkScene: return PVG_RESULT_INVALID_ARGUMENT
  scene.kids.add paint; PVG_RESULT_SUCCESS
proc pvg_paint_rel*(paint: Pvg_Paint): Pvg_Result = PVG_RESULT_SUCCESS
proc pvg_paint_translate*(p: Pvg_Paint, x, y: cfloat): Pvg_Result =
  p.tx = x; p.ty = y; p.hasT = true; PVG_RESULT_SUCCESS
proc pvg_paint_scale*(p: Pvg_Paint, f: cfloat): Pvg_Result =
  p.sc = f; p.hasS = true; PVG_RESULT_SUCCESS
proc pvg_paint_rotate*(p: Pvg_Paint, deg: cfloat): Pvg_Result =
  p.rot = deg; PVG_RESULT_SUCCESS
proc pvg_paint_set_opacity*(p: Pvg_Paint, o: uint8): Pvg_Result =
  p.opacity = o; PVG_RESULT_SUCCESS

proc ownMat(p: Pvg_Paint): Mat =
  translateM(p.tx, p.ty) * rotateM(p.rot) * scaleM(p.sc)

# ---------------------------------------------------------------- shape
proc seg[T: SomeFloat](p: Pvg_Paint, op: char, v: varargs[T]): Pvg_Result =
  var s = Seg(op: op)
  for i, x in v: s.v[i] = float(x)
  p.segs.add s; PVG_RESULT_SUCCESS
proc segZ(p: Pvg_Paint): Pvg_Result = p.segs.add Seg(op: 'Z'); PVG_RESULT_SUCCESS
proc pvg_shape_reset*(p: Pvg_Paint): Pvg_Result = p.segs.setLen(0); PVG_RESULT_SUCCESS
proc pvg_shape_move_to*(p: Pvg_Paint, x, y: cfloat): Pvg_Result = seg(p, 'M', x, y)
proc pvg_shape_line_to*(p: Pvg_Paint, x, y: cfloat): Pvg_Result = seg(p, 'L', x, y)
proc pvg_shape_cubic_to*(p: Pvg_Paint, a, b, c, d, e, f: cfloat): Pvg_Result = seg(p, 'C', a, b, c, d, e, f)
proc pvg_shape_close*(p: Pvg_Paint): Pvg_Result = segZ(p)

const K = 0.5522847498307936
proc ell(p: Pvg_Paint, cx, cy, rx, ry: float, cw: bool) =
  discard seg(p, 'M', cx, cy - ry)
  let q = [(cx + rx, cy - ry, cx + rx, cy), (cx + rx, cy + ry, cx, cy + ry), (cx - rx, cy + ry, cx - rx, cy), (cx - rx, cy - ry, cx, cy - ry)]
  discard (cx, cy)
  # quadrants as cubics (clockwise in screen space)
  discard seg(p, 'C', cx + rx*K, cy - ry, cx + rx, cy - ry*K, cx + rx, cy)
  discard seg(p, 'C', cx + rx, cy + ry*K, cx + rx*K, cy + ry, cx, cy + ry)
  discard seg(p, 'C', cx - rx*K, cy + ry, cx - rx, cy + ry*K, cx - rx, cy)
  discard seg(p, 'C', cx - rx, cy - ry*K, cx - rx*K, cy - ry, cx, cy - ry)
  discard segZ(p); discard q
proc pvg_shape_append_circle*(p: Pvg_Paint, cx, cy, rx, ry: cfloat, cw: bool): Pvg_Result =
  ell(p, cx, cy, rx, ry, cw); PVG_RESULT_SUCCESS
proc pvg_shape_append_rect*(p: Pvg_Paint, x, y, w, h, rx, ry: cfloat, cw: bool): Pvg_Result =
  let rx = min(rx.float, w / 2); let ry = min(ry.float, h / 2)
  if rx <= 0 or ry <= 0:
    discard seg(p, 'M', x, y); discard seg(p, 'L', x + w, y); discard seg(p, 'L', x + w, y + h)
    discard seg(p, 'L', x, y + h); discard segZ(p)
  else:
    let (x0, y0, x1, y1) = (x.float, y.float, x.float + w, y.float + h)
    discard seg(p, 'M', x0 + rx, y0); discard seg(p, 'L', x1 - rx, y0)
    discard seg(p, 'C', x1 - rx + rx*K, y0, x1, y0 + ry - ry*K, x1, y0 + ry)
    discard seg(p, 'L', x1, y1 - ry)
    discard seg(p, 'C', x1, y1 - ry + ry*K, x1 - rx + rx*K, y1, x1 - rx, y1)
    discard seg(p, 'L', x0 + rx, y1)
    discard seg(p, 'C', x0 + rx - rx*K, y1, x0, y1 - ry + ry*K, x0, y1 - ry)
    discard seg(p, 'L', x0, y0 + ry)
    discard seg(p, 'C', x0, y0 + ry - ry*K, x0 + rx - rx*K, y0, x0 + rx, y0)
    discard segZ(p)
  PVG_RESULT_SUCCESS
proc pvg_shape_set_fill_color*(p: Pvg_Paint, r, g, b, a: uint8): Pvg_Result =
  p.fill = [r, g, b, a]; p.hasFill = true; PVG_RESULT_SUCCESS
proc pvg_linear_gradient_new*(x1, y1, x2, y2: cfloat): Pvg_Gradient =
  Pvg_Gradient(x1: x1, y1: y1, x2: x2, y2: y2)
proc pvg_gradient_add_stop*(g: Pvg_Gradient, offset: cfloat, r, gr, b, a: uint8): Pvg_Result =
  if g == nil: return PVG_RESULT_INVALID_ARGUMENT
  g.stops.add Pvg_Stop(offset: offset, r: r, g: gr, b: b, a: a); g.ramp = nil; PVG_RESULT_SUCCESS
proc pvg_shape_set_fill_gradient*(p: Pvg_Paint, g: Pvg_Gradient): Pvg_Result =
  p.fillGrad = g; PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_gradient*(p: Pvg_Paint, g: Pvg_Gradient): Pvg_Result =
  p.strokeGrad = g; PVG_RESULT_SUCCESS

proc rampOf(g: Pvg_Gradient): ref Ramp =
  if g.ramp != nil: return g.ramp
  new(g.ramp)
  let n = g.stops.len
  proc col(st: Pvg_Stop): array[4, float32] = [st.r.float32 / 255, st.g.float32 / 255, st.b.float32 / 255, st.a.float32 / 255]
  for i in 0 .. 255:
    let u = i.float / 255
    if n == 0: g.ramp[][i] = [0'f32, 0, 0, 0]
    elif u <= g.stops[0].offset: g.ramp[][i] = col(g.stops[0])
    elif u >= g.stops[n - 1].offset: g.ramp[][i] = col(g.stops[n - 1])
    else:
      for k in 0 ..< n - 1:
        let a = g.stops[k]
        let b = g.stops[k + 1]
        if u >= a.offset and u <= b.offset:
          let t = if b.offset == a.offset: 0.0 else: (u - a.offset) / (b.offset - a.offset)
          let ca = col(a)
          let cb = col(b)
          for c in 0 .. 3: g.ramp[][i][c] = ca[c] + (cb[c] - ca[c]) * t.float32
          break
  g.ramp

proc gradientXf(g: Pvg_Gradient): array[6, float] =
  ## nanosvg-style unit-space transform for a linear gradient: parameter = t1*x + t3*y + t5
  let dx = g.x2 - g.x1
  let dy = g.y2 - g.y1
  let l2 = max(dx * dx + dy * dy, 1e-12)
  [0.0, dx / l2, 0.0, dy / l2, 0.0, -(g.x1 * dx + g.y1 * dy) / l2]

proc pvg_shape_set_stroke_width*(p: Pvg_Paint, w: cfloat): Pvg_Result = p.sw = w; PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_color*(p: Pvg_Paint, r, g, b, a: uint8): Pvg_Result =
  p.stroke = [r, g, b, a]; PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_dash*(p: Pvg_Paint, d: ptr cfloat, cnt: uint32, offset: cfloat): Pvg_Result =
  p.dash.setLen(0)
  let a = cast[ptr UncheckedArray[cfloat]](d)
  if d != nil:
    for i in 0..<cnt.int: p.dash.add a[i].float
  PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_cap*(p: Pvg_Paint, c: Pvg_Stroke_Cap): Pvg_Result = p.cap = c; PVG_RESULT_SUCCESS
proc pvg_shape_set_stroke_join*(p: Pvg_Paint, j: Pvg_Stroke_Join): Pvg_Result = p.join = j; PVG_RESULT_SUCCESS

# ---------------------------------------------------------------- text
proc pvg_text_set_font*(p: Pvg_Paint, name: cstring): Pvg_Result = p.font = $name; PVG_RESULT_SUCCESS
proc pvg_text_set_size*(p: Pvg_Paint, s: cfloat): Pvg_Result = p.size = s; PVG_RESULT_SUCCESS
proc pvg_text_set_text*(p: Pvg_Paint, t: cstring): Pvg_Result = p.text = $t; PVG_RESULT_SUCCESS
proc pvg_text_set_color*(p: Pvg_Paint, r, g, b: uint8): Pvg_Result = p.color = [r, g, b]; PVG_RESULT_SUCCESS
proc pvg_text_align*(p: Pvg_Paint, x, y: cfloat): Pvg_Result = p.ax = x; p.ay = y; PVG_RESULT_SUCCESS
proc pvg_text_layout*(p: Pvg_Paint, w, h: cfloat): Pvg_Result = PVG_RESULT_SUCCESS

proc fontOf(p: Pvg_Paint): Font =
  if p.font in fonts: fonts[p.font] else: defaultFont

type
  GlyphPlace* = object
    code*: int
    x*, y*: float            ## baseline origin in font units (y-down), alignment applied
    line*: int
  LinePlace* = object
    text*: string
    x*, y*, width*: float    ## font units; (x, y) = line start on the baseline-relative grid
    unmapped*: bool          ## line has characters the font lacks
  TextPlace* = object
    scale*: float            ## px per font unit
    ascentPx*: float
    lineAdvance*: float      ## font units
    lineCount*: int
    glyphs*: seq[GlyphPlace]
    lines*: seq[LinePlace]

proc placeGlyphs*(p: Pvg_Paint): TextPlace =
  ## Text layout: kerning, line advance (ascent - descent + lineGap), per-line alignment.
  let f = fontOf(p)
  result.lineCount = 1
  if f == nil or p.size <= 0: return
  let s = p.size * DPI / f.unitsPerEm.float
  result.scale = s; result.ascentPx = f.ascent.float * s; result.lineAdvance = f.lineAdvance
  var cursor, y = 0.0
  var lastGid = -1
  var cur = LinePlace()
  template endLine() =
    cur.width = cursor; cur.y = y; result.lines.add cur
  for code in codepoints(p.text):
    if code == 10:
      endLine(); cursor = 0; y += f.lineAdvance; cur = LinePlace(); inc result.lineCount
      continue
    if code == 13: continue
    cur.text.add $Rune(code)
    let g = f.glyph(code)
    if g.gid == 0: cur.unmapped = true; continue     # unmapped: skipped, no advance
    let kx = if lastGid >= 0: f.kernPair(lastGid, g.gid) else: 0.0
    result.glyphs.add GlyphPlace(code: code, x: cursor + kx, y: y, line: result.lines.len)
    cursor += g.advance + kx
    lastGid = g.gid
  endLine()
  let h = result.lineCount.float * f.lineAdvance
  for ln in result.lines.mitems:
    ln.x = -ln.width * p.ax; ln.y -= h * p.ay
  for g in result.glyphs.mitems:
    g.x += result.lines[g.line].x; g.y -= h * p.ay

proc glyphSegs*(fontName: string, code: int): seq[Seg] =
  ## One glyph outline in font units (y-down); moveTo/lineTo/quadTo(Q)/close.
  let f = if fontName in fonts: fonts[fontName] else: defaultFont
  if f != nil: result = f.glyph(code).segs

type TextLayout = object
  segs: seq[Seg]          ## font units, y-down, align applied
  lines: int
  mat: Mat                ## font units -> paint-local px

proc layoutText(p: Pvg_Paint): TextLayout =
  let pl = placeGlyphs(p)
  result.lines = pl.lineCount
  let f = fontOf(p)
  if f == nil or p.size <= 0: return
  result.mat = Mat(a: pl.scale, d: pl.scale, f: pl.ascentPx)
  for g in pl.glyphs:
    for sg in f.glyph(g.code).segs:
      var t = sg
      for k in 0..<npts(sg.op):
        t.v[2*k] += g.x; t.v[2*k + 1] += g.y
      result.segs.add t

proc pvg_text_get_text_metrics*(p: Pvg_Paint, m: ptr Pvg_Text_Metrics): Pvg_Result =
  let f = fontOf(p)
  if f == nil: return PVG_RESULT_INSUFFICIENT_CONDITION
  let s = p.size * DPI / f.unitsPerEm.float
  m.ascent = f.ascent.float * s; m.descent = f.descent.float * s
  m.linegap = f.lineGap.float * s; m.advance = f.lineAdvance * s
  PVG_RESULT_SUCCESS
proc pvg_text_line_count*(p: Pvg_Paint): uint32 = uint32(layoutText(p).lines)

# ---------------------------------------------------------------- picture (SVG loader: phase 5)
var picCache: Table[string, Picture]
proc pvg_picture_load_data*(pic: Pvg_Paint, data: cstring, size: uint32, mimetype: cstring, rpath: cstring, copy: bool): Pvg_Result =
  let mt = ($mimetype).toLowerAscii
  if mt notin ["svg", "svg+xml", "image/svg+xml"]: return PVG_RESULT_NOT_SUPPORTED
  var s = newString(size.int)
  if size > 0: copyMem(addr s[0], data, size.int)
  if s notin picCache:
    picCache[s] = (try: loadSvg(s) except CatchableError: nil)
  pic.pic = picCache[s]
  if pic.pic == nil or pic.pic.shapes.len == 0: return PVG_RESULT_INVALID_ARGUMENT
  PVG_RESULT_SUCCESS
proc pvg_picture_set_size*(pic: Pvg_Paint, w, h: cfloat): Pvg_Result = pic.pw = w; pic.ph = h; PVG_RESULT_SUCCESS

# ---------------------------------------------------------------- bounds
proc paintPolys(p: Pvg_Paint, m: Mat): seq[Poly] =
  case p.kind
  of pkShape: result = flatten(p.segs, m)
  of pkText:
    let t = layoutText(p)
    result = flatten(t.segs, m * t.mat)
  of pkScene:
    for k in p.kids: result.add paintPolys(k, m * ownMat(k))
  else: discard

proc pvg_paint_get_aabb*(p: Pvg_Paint, x, y, w, h: ptr cfloat): Pvg_Result =
  let b = bounds(paintPolys(p, ownMat(p)))
  if not b.ok: return PVG_RESULT_INSUFFICIENT_CONDITION
  x[] = b.x0; y[] = b.y0; w[] = b.x1 - b.x0; h[] = b.y1 - b.y0
  PVG_RESULT_SUCCESS

# ---------------------------------------------------------------- canvas / render
proc pvg_swcanvas_create*(op: Pvg_Engine_Option): Pvg_Canvas = Pvg_Canvas()
proc pvg_swcanvas_set_target*(c: Pvg_Canvas, buffer: ptr uint32, stride, w, h: uint32, cs: Pvg_Colorspace): Pvg_Result =
  c.buf = buffer; c.stride = stride.int; c.w = w.int; c.h = h.int; c.cs = cs; PVG_RESULT_SUCCESS
proc pvg_canvas_destroy*(c: Pvg_Canvas): Pvg_Result = PVG_RESULT_SUCCESS
proc pvg_canvas_add*(c: Pvg_Canvas, p: Pvg_Paint): Pvg_Result = c.root.add p; PVG_RESULT_SUCCESS
proc pvg_canvas_remove*(c: Pvg_Canvas, p: Pvg_Paint): Pvg_Result = c.root.setLen(0); PVG_RESULT_SUCCESS
proc pvg_canvas_update*(c: Pvg_Canvas): Pvg_Result = PVG_RESULT_SUCCESS
proc pvg_canvas_sync*(c: Pvg_Canvas): Pvg_Result = PVG_RESULT_SUCCESS

proc cvt(c: array[4, uint8]): (float, float, float, float) =
  (c[0].float / 255, c[1].float / 255, c[2].float / 255, c[3].float / 255)

proc render(L: var Layer, p: Pvg_Paint, parent: Mat) =
  let m = parent * ownMat(p)
  let op = p.opacity.float / 255
  case p.kind
  of pkScene:
    if p.opacity == 255:
      for k in p.kids: render(L, k, m)
    elif p.opacity > 0:
      var g = newLayer(L.w, L.h)
      for k in p.kids: render(g, k, m)
      compositeGroup(L, g, op)
  of pkShape:
    let polys = flatten(p.segs, m)
    if p.fillGrad != nil:
      L.blendGradient(rasterize(polys, false, L.w, L.h), rampOf(p.fillGrad), false, gradientXf(p.fillGrad), inverse(m), op)
    elif p.hasFill and p.fill[3] > 0:
      let (r, g, b, a) = cvt(p.fill)
      L.blend(rasterize(polys, false, L.w, L.h), r, g, b, a * op)
    if p.sw > 0 and (p.stroke[3] > 0 or p.strokeGrad != nil):
      let sc = scaleOf(m)
      var d: seq[float]
      for v in p.dash: d.add v * sc
      let sp = strokePolys(polys, p.sw * sc, Cap(ord(p.cap)), Join(ord(p.join)), d)
      if p.strokeGrad != nil:
        L.blendGradient(rasterize(sp, false, L.w, L.h), rampOf(p.strokeGrad), false, gradientXf(p.strokeGrad), inverse(m), op)
      else:
        let (r, g, b, a) = cvt(p.stroke)
        L.blend(rasterize(sp, false, L.w, L.h), r, g, b, a * op)
  of pkText:
    let t = layoutText(p)
    let polys = flatten(t.segs, m * t.mat)
    L.blend(rasterize(polys, false, L.w, L.h), p.color[0].float / 255, p.color[1].float / 255, p.color[2].float / 255, op)
  of pkPicture:
    if p.pic == nil: return
    let pw = if p.pw > 0: p.pw else: p.pic.w
    let ph = if p.ph > 0: p.ph else: p.pic.h
    let ps = min(pw / p.pic.w, ph / p.pic.h)
    let pm = m * translateM((pw - p.pic.w * ps) / 2, (ph - p.pic.h * ps) / 2) * scaleM(ps)
    let inv = inverse(pm)
    proc paintMask(L: var Layer, mk: Mask, pp: PicPaint, a: float) =
      case pp.kind
      of 1: L.blend(mk, pp.rgba[0], pp.rgba[1], pp.rgba[2], pp.rgba[3] * a)
      of 2, 3: L.blendGradient(mk, pp.ramp, pp.kind == 3, pp.xf, inv, a)
      else: discard
    for sh in p.pic.shapes:
      let polys = flatten(sh.segs, pm)
      let a = sh.opacity * op
      if sh.fill.kind != 0: paintMask(L, rasterize(polys, sh.evenOdd, L.w, L.h), sh.fill, a)
      if sh.stroke.kind != 0 and sh.sw > 0:
        let sc = scaleOf(pm)
        var d: seq[float]
        for v in sh.dash: d.add v * sc
        let sp = strokePolys(polys, sh.sw * sc, Cap(sh.cap), Join(sh.join), d, 0, max(1.0, sh.miter))
        paintMask(L, rasterize(sp, false, L.w, L.h), sh.stroke, a)

proc pack(r, g, b, a: float32, cs: Pvg_Colorspace): uint32 =
  let A = clamp(a, 0'f32, 1'f32)
  let straight = cs in {PVG_COLORSPACE_ABGR8888S, PVG_COLORSPACE_ARGB8888S}
  let (R, G, B) = if straight and A > 0: (r / A, g / A, b / A) else: (r, g, b)
  let ri = uint32(round(clamp(R, 0'f32, 1'f32) * 255)); let gi = uint32(round(clamp(G, 0'f32, 1'f32) * 255))
  let bi = uint32(round(clamp(B, 0'f32, 1'f32) * 255)); let ai = uint32(round(A * 255))
  if cs in {PVG_COLORSPACE_ARGB8888, PVG_COLORSPACE_ARGB8888S, PVG_COLORSPACE_XRGB8888}:
    bi or (gi shl 8) or (ri shl 16) or (ai shl 24)
  else: ri or (gi shl 8) or (bi shl 16) or (ai shl 24)

proc unpack(v: uint32, cs: Pvg_Colorspace): array[4, float32] =
  ## inverse of `pack`: pixel -> premultiplied float RGBA
  let straight = cs in {PVG_COLORSPACE_ABGR8888S, PVG_COLORSPACE_ARGB8888S}
  let argb = cs in {PVG_COLORSPACE_ARGB8888, PVG_COLORSPACE_ARGB8888S, PVG_COLORSPACE_XRGB8888}
  let lo = float32(v and 255) / 255
  let mid = float32((v shr 8) and 255) / 255
  let hi = float32((v shr 16) and 255) / 255
  let a = if cs in {PVG_COLORSPACE_XBGR8888, PVG_COLORSPACE_XRGB8888}: 1'f32 else: float32((v shr 24) and 255) / 255
  var (r, g, b) = if argb: (hi, mid, lo) else: (lo, mid, hi)
  if straight: r *= a; g *= a; b *= a
  [r, g, b, a]

proc pvg_canvas_draw*(c: Pvg_Canvas, clear: bool): Pvg_Result =
  if c.buf == nil: return PVG_RESULT_INSUFFICIENT_CONDITION
  var L = newLayer(c.w, c.h)
  let dst = cast[ptr UncheckedArray[uint32]](c.buf)
  if not clear:   # composite on top of the pixels already in the target buffer
    for y in 0..<c.h:
      for x in 0..<c.w:
        let u = unpack(dst[y * c.stride + x], c.cs)
        let i = (y * c.w + x) * 4
        L.px[i] = u[0]; L.px[i + 1] = u[1]; L.px[i + 2] = u[2]; L.px[i + 3] = u[3]
  for p in c.root: render(L, p, Ident)
  for y in 0..<c.h:
    for x in 0..<c.w:
      let i = (y * c.w + x) * 4
      dst[y * c.stride + x] = pack(L.px[i], L.px[i + 1], L.px[i + 2], L.px[i + 3], c.cs)
  PVG_RESULT_SUCCESS
