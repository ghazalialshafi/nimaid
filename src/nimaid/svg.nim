## Serialises a gfx scene graph to SVG (vector output).
##
## * Text is outlined by default: glyphs are defined once (<defs>) and placed with <use>, using the same
##   TTF layout engine as the raster output, so the SVG is pixel-faithful and needs no installed font.
##   `stText` emits live <text> instead (explicit baseline + textLength so it still fits the boxes).
## * Emoji are flattened into native <path>/gradient definitions (no nested <svg>, no id rewriting),
##   defined once per distinct emoji and re-used with <use>.
import std/[strutils, strformat, tables, math]
import gfx, purevg as real
import purevg/[svgload, core]

type SvgTextMode* = enum stPaths, stText

const PtToPx = 96.0 / 72.0   # PureVG font sizes are points

proc f(v: float): string =
  var s = formatFloat(v, ffDecimal, 2)
  if '.' in s:
    s = s.strip(leading = false, chars = {'0'})
    s = s.strip(leading = false, chars = {'.'})
  if s == "" or s == "-0": "0" else: s

proc ff(v: float): string =
  ## high-precision number for matrices / gradient transforms
  var s = formatFloat(v, ffDecimal, 6)
  if '.' in s:
    s = s.strip(leading = false, chars = {'0'})
    s = s.strip(leading = false, chars = {'.'})
  if s == "" or s == "-0": "0" else: s

proc num(v: float, dec: int): string =
  ## shortest decimal form, no leading zero (".5", "-.5")
  var t = formatFloat(v, ffDecimal, dec)
  if '.' in t:
    t = t.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  if t == "" or t == "-0": return "0"
  if t.startsWith("0."): t = t[1 .. ^1]
  elif t.startsWith("-0."): t = "-" & t[2 .. ^1]
  t

proc relPath(segs: openArray[Seg], dec: int): string =
  ## Relative-command path data. Rounding is tracked on the rounded current point, so it never drifts.
  let q = pow(10.0, dec.float)
  template rd(v: float): float = round(v * q) / q
  var cxp, cyp, sx, sy = 0.0
  var last = ' '
  var first = true
  proc put(o: var string, v: float, dec: int) =
    let t = num(v, dec)
    if o.len > 0 and o[^1] in {'0' .. '9', '.'} and t[0] != '-': o.add ' '
    o.add t
  for sg in segs:
    case sg.op
    of 'M':
      let x = rd(sg.v[0]); let y = rd(sg.v[1])
      if first: result.add "M"; result.put(x, dec); result.put(y, dec)
      else: result.add "m"; result.put(x - cxp, dec); result.put(y - cyp, dec)
      cxp = x; cyp = y; sx = x; sy = y; last = 'm'; first = false
    of 'L':
      let x = rd(sg.v[0]); let y = rd(sg.v[1])
      if y == cyp and x != cxp:
        if last != 'h': result.add "h"
        result.put(x - cxp, dec); last = 'h'
      elif x == cxp and y != cyp:
        if last != 'v': result.add "v"
        result.put(y - cyp, dec); last = 'v'
      elif x == cxp and y == cyp: continue
      else:
        if last != 'l': result.add "l"
        result.put(x - cxp, dec); result.put(y - cyp, dec); last = 'l'
      cxp = x; cyp = y
    of 'Q':
      let x1 = rd(sg.v[0]); let y1 = rd(sg.v[1]); let x = rd(sg.v[2]); let y = rd(sg.v[3])
      if last != 'q': result.add "q"
      for v in [x1 - cxp, y1 - cyp, x - cxp, y - cyp]: result.put(v, dec)
      cxp = x; cyp = y; last = 'q'
    of 'C':
      let a = rd(sg.v[0]); let b = rd(sg.v[1]); let c = rd(sg.v[2]); let d = rd(sg.v[3])
      let x = rd(sg.v[4]); let y = rd(sg.v[5])
      if last != 'c': result.add "c"
      for v in [a - cxp, b - cyp, c - cxp, d - cyp, x - cxp, y - cyp]: result.put(v, dec)
      cxp = x; cyp = y; last = 'c'
    else:
      result.add "z"; cxp = sx; cyp = sy; last = 'z'

proc f3(v: float): string =
  ## opacities need 3 decimals so the SVG matches the exact 8-bit alpha used by the rasteriser
  var s = formatFloat(v, ffDecimal, 3)
  if '.' in s:
    s = s.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  if s == "" or s == "-0": "0" else: s

proc esc(s: string): string =
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")

proc rgbAttr(c: array[4, uint8], name: string): string =
  result = &" {name}=\"rgb({c[0]},{c[1]},{c[2]})\""
  if c[3] != 255: result.add &" {name}-opacity=\"{f3(float(c[3]) / 255.0)}\""

proc transformStr(n: Node): string =
  var parts: seq[string]
  if n.hasT and (n.tx != 0 or n.ty != 0): parts.add &"translate({f(n.tx)} {f(n.ty)})"
  if n.rot != 0: parts.add &"rotate({f(n.rot)})"
  if n.hasS and n.sc != 1: parts.add &"scale({ff(n.sc)})"
  parts.join(" ")

proc transformAttr(n: Node): string =
  let t = transformStr(n)
  if t.len > 0: &" transform=\"{t}\"" else: ""

type Ctx = object
  defs: string
  glyphIds: Table[string, string]      ## "font:code" -> id ("" = blank glyph)
  picIds: Table[string, string]        ## emoji svg text -> def id
  picCache: Table[string, Picture]
  mode: SvgTextMode
  fontFamily: string
  nGlyph, nPic, nGrad: int
var cx: Ctx

proc gradAttr(g: real.Pvg_Gradient, name: string): string =
  inc cx.nGrad
  let id = &"lg{cx.nGrad}"
  var stops = ""
  for st in g.stops:
    stops.add &"<stop offset=\"{ff(st.offset)}\" stop-color=\"rgb({st.r},{st.g},{st.b})\""
    if st.a != 255: stops.add &" stop-opacity=\"{f3(float(st.a) / 255.0)}\""
    stops.add "/>"
  cx.defs.add &"<linearGradient id=\"{id}\" gradientUnits=\"userSpaceOnUse\" x1=\"{f(g.x1)}\" y1=\"{f(g.y1)}\" x2=\"{f(g.x2)}\" y2=\"{f(g.y2)}\">{stops}</linearGradient>\n"
  &" {name}=\"url(#{id})\""

# ---------------------------------------------------------------- emoji / pictures
proc paintAttr(pp: PicPaint, name, picId: string): string =
  case pp.kind
  of 1:
    let r = int(round(pp.rgba[0] * 255)); let g = int(round(pp.rgba[1] * 255)); let b = int(round(pp.rgba[2] * 255))
    result = &" {name}=\"rgb({r},{g},{b})\""
    if pp.rgba[3] < 0.999: result.add &" {name}-opacity=\"{f(pp.rgba[3])}\""
  of 2, 3:
    inc cx.nGrad
    let id = &"{picId}g{cx.nGrad}"
    let inv = inverse(Mat(a: pp.xf[0], b: pp.xf[1], c: pp.xf[2], d: pp.xf[3], e: pp.xf[4], f: pp.xf[5]))
    let tr = &"matrix({ff(inv.a)} {ff(inv.b)} {ff(inv.c)} {ff(inv.d)} {ff(inv.e)} {ff(inv.f)})"
    var stops = ""
    for (off, c) in pp.stops:
      stops.add &"<stop offset=\"{ff(off)}\" stop-color=\"rgb({int(round(c[0] * 255))},{int(round(c[1] * 255))},{int(round(c[2] * 255))})\""
      if c[3] < 0.999: stops.add &" stop-opacity=\"{f(c[3])}\""
      stops.add "/>"
    if pp.kind == 2:
      cx.defs.add &"<linearGradient id=\"{id}\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\" gradientTransform=\"{tr}\">{stops}</linearGradient>\n"
    else:
      cx.defs.add &"<radialGradient id=\"{id}\" gradientUnits=\"userSpaceOnUse\" cx=\"0\" cy=\"0\" r=\"1\" gradientTransform=\"{tr}\">{stops}</radialGradient>\n"
    result = &" {name}=\"url(#{id})\""
  else:
    if name == "fill": result = " fill=\"none\""

proc pictureDef(svg: string): tuple[id: string, pic: Picture] =
  if svg in cx.picIds: return (cx.picIds[svg], cx.picCache[svg])
  var pic: Picture
  try: pic = loadSvg(svg) except CatchableError: pic = nil
  if pic == nil or pic.shapes.len == 0: return ("", nil)
  inc cx.nPic
  let id = &"e{cx.nPic}"
  let dec = if pic.w >= 1000: 0 elif pic.w >= 100: 1 else: 2   # large-viewBox emoji need fewer decimals
  var body = &"<g id=\"{id}\">"
  for sh in pic.shapes:
    if sh.segs.len == 0: continue
    var a = &"<path d=\"{relPath(sh.segs, dec)}\"" & paintAttr(sh.fill, "fill", id)
    if sh.fill.kind != 0 and sh.evenOdd: a.add " fill-rule=\"evenodd\""
    if sh.stroke.kind != 0 and sh.sw > 0:
      a.add paintAttr(sh.stroke, "stroke", id) & &" stroke-width=\"{f(sh.sw)}\""
      if sh.join == 1: a.add " stroke-linejoin=\"round\""
      elif sh.join == 2: a.add " stroke-linejoin=\"bevel\""
      if sh.cap == 1: a.add " stroke-linecap=\"round\""
      elif sh.cap == 2: a.add " stroke-linecap=\"square\""
      if sh.dash.len > 0:
        var ds: seq[string]
        for v in sh.dash: ds.add f(v)
        a.add &" stroke-dasharray=\"{ds.join(\",\")}\""
    if sh.opacity < 0.999: a.add &" opacity=\"{f(sh.opacity)}\""
    body.add a & "/>"
  body.add "</g>\n"
  cx.defs.add body
  cx.picIds[svg] = id; cx.picCache[svg] = pic
  (id, pic)

# ---------------------------------------------------------------- text
proc glyphId(font: string, code: int): string =
  let key = font & ":" & $code
  if key in cx.glyphIds: return cx.glyphIds[key]
  let d = relPath(real.glyphSegs(font, code), 0)
  if d.len == 0: cx.glyphIds[key] = ""; return ""
  inc cx.nGlyph
  let id = &"g{cx.nGlyph}"
  cx.defs.add &"<path id=\"{id}\" d=\"{d}\"/>\n"
  cx.glyphIds[key] = id
  id

proc emitText(n: Node, o: var string, op: string) =
  if n.text.strip().len == 0: return
  let tp = real.pvg_text_new()
  discard real.pvg_text_set_font(tp, n.font.cstring)
  discard real.pvg_text_set_size(tp, cfloat(n.size))
  discard real.pvg_text_set_text(tp, n.text.cstring)
  discard real.pvg_text_align(tp, cfloat(n.ax), cfloat(n.ay))
  let pl = real.placeGlyphs(tp)
  let tx = if n.hasT: n.tx else: 0.0
  let ty = if n.hasT: n.ty else: 0.0
  let sc = if n.hasS: n.sc else: 1.0
  let fill = &" fill=\"rgb({n.color[0]},{n.color[1]},{n.color[2]})\""
  case cx.mode
  of stPaths:
    if pl.glyphs.len == 0: return
    var uses = ""
    for g in pl.glyphs:
      let id = glyphId(n.font, g.code)
      if id.len == 0: continue
      let xs = if g.x == 0: "" else: &" x=\"{f(g.x)}\""
      let ys = if g.y == 0: "" else: &" y=\"{f(g.y)}\""
      uses.add &"<use xlink:href=\"#{id}\"{xs}{ys}/>"
    if uses.len == 0: return
    let m = translateM(tx, ty) * rotateM(n.rot) * scaleM(sc) * Mat(a: pl.scale, d: pl.scale, f: pl.ascentPx)
    o.add &"<g aria-label=\"{esc(n.text)}\" transform=\"matrix({ff(m.a)} {ff(m.b)} {ff(m.c)} {ff(m.d)} {f(m.e)} {f(m.f)})\"{fill}{op}>{uses}</g>\n"
  of stText:
    var t = ""
    for ln in pl.lines:
      if ln.text.len == 0: continue
      let x = ln.x * pl.scale
      let y = ln.y * pl.scale + pl.ascentPx
      var a = &"<text x=\"{f(x)}\" y=\"{f(y)}\""
      if not ln.unmapped and ln.width > 0: a.add &" textLength=\"{f(ln.width * pl.scale)}\" lengthAdjust=\"spacing\""
      t.add a & &">{esc(ln.text)}</text>"
    if t.len == 0: return
    o.add &"<g xml:space=\"preserve\" font-family=\"{cx.fontFamily}\" font-size=\"{f(n.size * PtToPx)}\"{fill}{transformAttr(n)}{op}>{t}</g>\n"

# ---------------------------------------------------------------- scene
proc emit(n: Node, o: var string) =
  let op = if n.opacity != 255: &" opacity=\"{f3(float(n.opacity) / 255.0)}\"" else: ""
  case n.kind
  of nkScene:
    let open = n.hasT or n.hasS or n.rot != 0 or n.opacity != 255
    if open: o.add &"<g{transformAttr(n)}{op}>\n"
    for k in n.kids: emit(k, o)
    if open: o.add "</g>\n"
  of nkShape:
    if n.cmds.len == 0: return
    var segs: seq[Seg]
    for c in n.cmds: segs.add Seg(op: c.op, v: c.v)
    var a = &"<path d=\"{relPath(segs, 2)}\""
    if n.fillGrad != nil: a.add gradAttr(n.fillGrad, "fill")
    elif n.hasFill: a.add rgbAttr(n.fill, "fill")
    else: a.add " fill=\"none\""
    if n.hasStroke and n.sw > 0:
      if n.strokeGrad != nil: a.add gradAttr(n.strokeGrad, "stroke")
      else: a.add rgbAttr(n.stroke, "stroke")
      a.add &" stroke-width=\"{f(n.sw)}\""
      if n.join == real.PVG_STROKE_JOIN_ROUND: a.add " stroke-linejoin=\"round\""
      elif n.join == real.PVG_STROKE_JOIN_BEVEL: a.add " stroke-linejoin=\"bevel\""
      if n.cap == real.PVG_STROKE_CAP_ROUND: a.add " stroke-linecap=\"round\""
      elif n.cap == real.PVG_STROKE_CAP_SQUARE: a.add " stroke-linecap=\"square\""
      if n.dash.len > 0:
        var ds: seq[string]
        for v in n.dash: ds.add f(v)
        a.add &" stroke-dasharray=\"{ds.join(\",\")}\""
    o.add a & transformAttr(n) & op & "/>\n"
  of nkText:
    emitText(n, o, op)
  of nkPicture:
    if n.svg.len == 0: return
    let (id, pic) = pictureDef(n.svg)
    if id.len == 0: return
    let pw = if n.pw > 0: n.pw else: pic.w
    let ph = if n.ph > 0: n.ph else: pic.h
    let ps = min(pw / pic.w, ph / pic.h)
    var parts: seq[string]
    let t = transformStr(n)
    if t.len > 0: parts.add t
    let ox = (pw - pic.w * ps) / 2; let oy = (ph - pic.h * ps) / 2
    if abs(ox) > 1e-6 or abs(oy) > 1e-6: parts.add &"translate({f(ox)} {f(oy)})"
    parts.add &"scale({ff(ps)})"
    o.add &"<use xlink:href=\"#{id}\" transform=\"{parts.join(\" \")}\"{op}/>\n"

proc toSvg*(root: Node, w, h: int, bg: array[4, uint8],
            fontFamily = "'DejaVu Sans', Verdana, 'Trebuchet MS', Arial, sans-serif",
            textMode = stPaths): string =
  cx = Ctx(mode: textMode, fontFamily: fontFamily)
  var body = ""
  emit(root, body)
  result = &"<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"{w}\" height=\"{h}\" viewBox=\"0 0 {w} {h}\" role=\"img\">\n"
  if cx.defs.len > 0: result.add "<defs>\n" & cx.defs & "</defs>\n"
  result.add body
  result.add "</svg>\n"
