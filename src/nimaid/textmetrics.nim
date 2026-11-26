## PureVG-backed text measurement and label drawing, with colour-emoji runs.
## Fonts are registered by file name (without extension).
import std/[os, strutils]
import gfx, label, emoji, theme
from purevg import nil

var loadedFontName* = ""

type Run = object
  text: string
  isEmoji: bool

proc splitRuns(line: string): seq[Run] =
  var i = 0
  var cur = ""
  while i < line.len:
    let n = if emojiReady(): clusterAt(line, i) else: 0
    if n > 0:
      if cur.len > 0:
        result.add Run(text: cur)
        cur = ""
      result.add Run(text: line.substr(i, i + n - 1), isEmoji: true)
      i += n
    else:
      cur.add line[i]
      inc i
  if cur.len > 0: result.add Run(text: cur)

proc textWidth(txt: string, size: float): float =
  if txt.len == 0: return 0
  let t = purevg.pvg_text_new()
  discard purevg.pvg_text_set_font(t, loadedFontName.cstring)
  discard purevg.pvg_text_set_size(t, cfloat(size))
  discard purevg.pvg_text_set_text(t, txt.cstring)
  var x, y, w, h: cfloat
  let ok = purevg.pvg_paint_get_aabb(t, addr x, addr y, addr w, addr h)
  discard purevg.pvg_paint_rel(t)
  if ok == purevg.PVG_RESULT_SUCCESS and w > 0: float(w + 2 * x)
  else: float(txt.len) * size * 0.6

proc lineWidth(line: string, size: float): float =
  for r in splitRuns(line):
    result += (if r.isEmoji: size * emojiAdvanceEm else: textWidth(r.text, size))

proc measureLine*(text: string, size: float): float = lineWidth(text, size)
  ## Width in px of one line of text at `size` (points, like every pvg_* text size); emoji advance included.

proc installMeasurer() =
  setTextMeasurer(proc(text: string, fontSize: float32, isTitle: bool): tuple[w, h: float32] =
    let lines = text.splitLines()
    var w = 0.0
    for l in lines: w = max(w, lineWidth(l, float(fontSize)))
    (float32(w), float32(float(fontSize) * 1.5 * float(max(1, lines.len)))))

proc initTextMetrics*(fontPath: string): bool =
  ## Loads a TTF through PureVG and routes label measurement through it.
  if not fileExists(fontPath): return false
  if purevg.pvg_font_load(fontPath.cstring) != purevg.PVG_RESULT_SUCCESS: return false
  loadedFontName = splitFile(fontPath).name
  installMeasurer()
  true

proc initTextMetricsData*(name, data: string): bool =
  ## Like initTextMetrics, but the TrueType font is already in memory; it is registered as `name`.
  if purevg.pvg_font_load_data(name.cstring, data.cstring, uint32(data.len), "ttf", true) != purevg.PVG_RESULT_SUCCESS: return false
  loadedFontName = name
  installMeasurer()
  true

proc drawLabel*(scene: Pvg_Paint, text: string, cx, cy, size: float, color: Color, alignTop = false, alignLeft = false) =
  ## Multi-line label centred on cx (and on cy, or hanging from cy when alignTop). Emoji drawn as SVG pictures.
  let lines = labelText(text).splitLines()
  let lineH = size * 1.5
  let top = if alignTop: cy else: cy - lineH * float(lines.len) / 2
  for i, line in lines:
    let y = top + (float(i) + 0.5) * lineH
    let runs = splitRuns(line)
    if runs.len == 1 and not runs[0].isEmoji:
      # text-only line: centre-anchored (robust in SVG viewers with different glyph widths)
      let t = pvg_text_new()
      discard pvg_text_set_font(t, loadedFontName.cstring)
      discard pvg_text_set_size(t, cfloat(size))
      discard pvg_text_set_text(t, runs[0].text.cstring)
      discard pvg_text_set_color(t, color.r, color.g, color.b)
      discard pvg_text_align(t, (if alignLeft: 0.0 else: 0.5), 0.5)
      discard pvg_paint_translate(t, cfloat(cx), cfloat(y))
      discard pvg_scene_add(scene, t)
      continue
    var x = if alignLeft: cx else: cx - lineWidth(line, size) / 2
    for r in runs:
      if r.isEmoji:
        let svg = emojiSvg(r.text)
        let ew = size * emojiAdvanceEm
        if svg.len > 0:
          let pic = pvg_picture_new()
          if pvg_picture_load_data(pic, svg.cstring, uint32(svg.len), "svg", nil, true) == PVG_RESULT_SUCCESS:
            let eh = size * emojiAdvanceEm
            discard pvg_picture_set_size(pic, cfloat(eh), cfloat(eh))
            discard pvg_paint_translate(pic, cfloat(x), cfloat(y - eh / 2))
            discard pvg_scene_add(scene, pic)
          else: discard pvg_paint_rel(pic)
        x += ew
      else:
        let t = pvg_text_new()
        discard pvg_text_set_font(t, loadedFontName.cstring)
        discard pvg_text_set_size(t, cfloat(size))
        discard pvg_text_set_text(t, r.text.cstring)
        discard pvg_text_set_color(t, color.r, color.g, color.b)
        discard pvg_text_align(t, 0.0, 0.5)
        discard pvg_paint_translate(t, cfloat(x), cfloat(y))
        discard pvg_scene_add(scene, t)
        x += textWidth(r.text, size)
