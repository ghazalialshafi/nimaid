## Unit + end-to-end tests for the PureVG engine and the SVG writer.
## Run from the project root:   nim c -r tests/test_purevg.nim
import std/[unittest, strutils, math, os]
import nimaid
import nimaid/purevg/[core, raster, stroke, ttf, svgload]
import nimaid/purevg as vg      # qualified: `nimaid` also exports the recording-scene (gfx) pvg_* names

const fontPath = "fonts/DejaVuSans.ttf"
const emojiPath = "fonts/NotoColorEmoji-Regular.ttf"

proc rect(x0, y0, x1, y1: float): Poly =
  Poly(pts: @[pt(x0, y0), pt(x1, y0), pt(x1, y1), pt(x0, y1)], closed: true)

proc total(m: Mask): float =
  for c in m.cov: result += c.float

suite "math":
  test "matrix multiply and inverse round-trip":
    let m = translateM(10, 5) * scaleM(2)
    let p = m.apply(3, 4)
    check p.x == 16 and p.y == 13
    let q = inverse(m).apply(p.x, p.y)
    check abs(q.x - 3) < 1e-9 and abs(q.y - 4) < 1e-9
  test "cubic flattening stays on the curve":
    let polys = flatten(@[Seg(op: 'M', v: [0.0, 0, 0, 0, 0, 0]), Seg(op: 'C', v: [0.0, 10, 10, 10, 10, 0])], Ident)
    check polys.len == 1 and polys[0].pts.len > 4
    check abs(polys[0].pts[^1].x - 10) < 1e-9

suite "rasteriser":
  test "pixel-aligned rect has exact coverage":
    check abs(total(rasterize(@[rect(2, 2, 6, 5)], false, 20, 20)) - 12.0) < 1e-3
  test "fractional edges give proportional coverage":
    check abs(total(rasterize(@[rect(1.5, 1, 3.5, 3)], false, 10, 10)) - 4.0) < 1e-2
  test "nonzero fills a nested same-direction ring, even-odd leaves a hole":
    let polys = @[rect(0, 0, 10, 10), rect(3, 3, 7, 7)]
    check abs(total(rasterize(polys, false, 12, 12)) - 100.0) < 1e-2
    check abs(total(rasterize(polys, true, 12, 12)) - 84.0) < 1e-2
  test "geometry outside the canvas is clipped, not crashed":
    check total(rasterize(@[rect(-50, -50, -10, -10)], false, 10, 10)) == 0
    check total(rasterize(@[rect(-5, -5, 5, 5)], false, 10, 10)) > 24

suite "stroker":
  let line = @[Poly(pts: @[pt(10, 10), pt(50, 10)], closed: false)]
  test "butt-capped line covers length x width":
    let s = strokePolys(line, 4, cButt, jMiter)
    check abs(total(rasterize(s, false, 80, 30)) - 160.0) < 0.5
  test "square caps extend by half the width":
    let s = strokePolys(line, 4, cSquare, jMiter)
    check abs(total(rasterize(s, false, 80, 30)) - 176.0) < 0.5
  test "dashes remove roughly half of a 50/50 pattern":
    let s = strokePolys(line, 4, cButt, jMiter, dash = @[5.0, 5.0])
    let t = total(rasterize(s, false, 80, 30))
    check t > 70 and t < 90

suite "truetype":
  let f = parseFont(readFile(fontPath))
  test "font parses and exposes metrics":
    check f != nil and f.unitsPerEm == 2048 and f.ascent > 0 and f.descent < 0
  test "kerning pairs are applied (A,V tighten)":
    check f.kernPair(f.gidOf(ord('A')), f.gidOf(ord('V'))) < 0
    check f.kernPair(f.gidOf(ord('A')), f.gidOf(ord('B'))) == 0
  test "unmapped codepoints resolve to glyph 0":
    check f.gidOf(0x65E5) == 0           # CJK is not in DejaVu Sans
    check f.gidOf(ord('a')) != 0
  test "glyph outlines are non-empty for letters and empty for space":
    check f.glyph(ord('g')).segs.len > 10
    check f.glyph(ord(' ')).segs.len == 0
  test "text layout through the C-style API":
    check vg.pvg_font_load(fontPath) == vg.PVG_RESULT_SUCCESS
    let t = vg.pvg_text_new()
    discard vg.pvg_text_set_font(t, "DejaVuSans"); discard vg.pvg_text_set_size(t, 16); discard vg.pvg_text_set_text(t, "AV")
    var x, y, w, h: cfloat
    check vg.pvg_paint_get_aabb(t, addr x, addr y, addr w, addr h) == vg.PVG_RESULT_SUCCESS
    check w > 10 and h > 10
    var m: vg.Pvg_Text_Metrics
    check vg.pvg_text_get_text_metrics(t, addr m) == vg.PVG_RESULT_SUCCESS
    check m.advance > m.ascent

suite "canvas":
  test "draw(clear=false) composites over existing pixels; clear=true resets":
    var buf = newSeq[uint32](16 * 16)
    let cv = vg.pvg_swcanvas_create(vg.PVG_ENGINE_OPTION_DEFAULT)
    discard vg.pvg_swcanvas_set_target(cv, addr buf[0], 16, 16, 16, vg.PVG_COLORSPACE_ABGR8888S)
    let sq = vg.pvg_shape_new()
    discard vg.pvg_shape_append_rect(sq, 0, 0, 8, 8, 0, 0, true)
    discard vg.pvg_shape_set_fill_color(sq, 255, 0, 0, 255)
    discard vg.pvg_canvas_add(cv, sq)
    discard vg.pvg_canvas_draw(cv, true)
    check buf[0] == 0xFF0000FF'u32 and buf[15 * 16 + 15] == 0   # opaque red (R in low byte); rest transparent
    let sq2 = vg.pvg_shape_new()
    discard vg.pvg_shape_append_rect(sq2, 8, 8, 8, 8, 0, 0, true)
    discard vg.pvg_shape_set_fill_color(sq2, 0, 0, 255, 255)
    discard vg.pvg_canvas_remove(cv, sq); discard vg.pvg_canvas_add(cv, sq2)
    discard vg.pvg_canvas_draw(cv, false)
    check buf[0] == 0xFF0000FF'u32 and buf[15 * 16 + 15] == 0xFFFF0000'u32
    discard vg.pvg_canvas_draw(cv, true)
    check buf[0] == 0

suite "svg loader":
  const svg = """<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="20" height="20" viewBox="0 0 20 20">
    <defs><path id="p" d="M0 0 L10 0 L10 10 Z" fill="#f00"/>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#fff"/></linearGradient></defs>
    <use xlink:href="#p" x="5" y="5"/><rect width="4" height="4" fill="url(#g)"/></svg>"""
  test "<use> is inlined":
    let s = inlineUse(svg)
    check "<use" notin s
  test "shapes, colours and gradients are parsed":
    let pic = loadSvg(svg)
    check pic != nil and pic.w == 20 and pic.shapes.len == 2
    check pic.shapes[0].fill.kind == 1
    check pic.shapes[1].fill.kind == 2 and pic.shapes[1].fill.stops.len == 2

suite "end to end":
  let chart = readFile("examples/basic.mmd")
  test "PNG: dimensions and non-blank pixels":
    let img = renderMermaidToImage(chart, fontPath, 1.0)
    check img.width > 100 and img.height > 100
    check img.rgba.len == img.width * img.height * 4
    var ink = 0
    for i in 0 ..< img.width * img.height:
      if img.rgba[i * 4 + 3] > 0 and img.rgba[i * 4] < 100: inc ink
    check ink > 500
  test "SVG (outlined): self-contained, no <text>, glyphs reused":
    let s = renderMermaidToSvg(chart, fontPath)
    check s.startsWith("<svg") and s.endsWith("</svg>\n")
    check "<text" notin s and "<use" in s and "<defs>" in s
  test "SVG (live text): <text> with explicit baseline and textLength":
    let s = renderMermaidToSvg(chart, fontPath, svgText = true)
    check "<text x=" in s and "textLength=" in s and "dominant-baseline" notin s
  test "emoji become native paths, not nested <svg>":
    let s = renderMermaidToSvg("flowchart LR\n A[😀 hi] --> B[🚀]", fontPath, emojiPath)
    check "<linearGradient" in s or "<radialGradient" in s
    check s.count("<svg") == 1
  test "all formats come from one call":
    for ext in ["png", "gif", "svg"]:
      let p = getTempDir() / ("nimaid_test." & ext)
      renderMermaidToFile(chart, p, fontPath, 1.0)
      check getFileSize(p) > 500
      removeFile(p)
  test "themes change the output":
    check renderMermaidToSvg(chart, fontPath, themeName = "dark") != renderMermaidToSvg(chart, fontPath)
