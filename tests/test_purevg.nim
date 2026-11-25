## Unit + end-to-end tests for the PureVG engine and the SVG writer.
## Run from the project root:   nim c -r tests/test_purevg.nim
import std/[unittest, strutils, math, os, json, options]
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


suite "chart diagrams":
  const pie = "pie showData title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Rats\" : 15\n"
  const xy = "xychart-beta\n title \"Sales\"\n x-axis [jan, feb, mar]\n y-axis \"Revenue\" 0 --> 100\n bar [10, 50, 100]\n line [20, 40, 90]\n"
  const tl = "timeline\n title History\n section Early\n 2002 : LinkedIn\n 2004 : Facebook : Google\n"
  const qd = "quadrantChart\n title Reach\n x-axis Low --> High\n y-axis Bad --> Good\n quadrant-1 A\n quadrant-2 B\n quadrant-3 C\n quadrant-4 D\n P1: [0.3, 0.6]\n"
  const jr = "journey\n title Day\n section Work\n Make tea: 5: Me\n Do work: 1: Me, Cat\n"
  test "css colours: hex, rgb, hsl, names":
    check parseCssColor("#ECECFF").get == rgba(0xEC, 0xEC, 0xFF)
    check parseCssColor("#f00").get == rgba(255, 0, 0)
    check parseCssColor("rgb(10, 20, 30)").get == rgba(10, 20, 30)
    check parseCssColor("hsl(120, 100%, 50%)").get == rgba(0, 255, 0)
    check parseCssColor("hsl(-120, 100%, 50%)").get == rgba(0, 0, 255)   # negative hues wrap: -120 == 240
    check parseCssColor("lightgrey").get == rgba(211, 211, 211)
    check parseCssColor("not-a-colour").isNone
  test "structured config: front matter + init directive, nested objects":
    let c = readConfig("---\nconfig:\n  theme: dark\n  xyChart:\n    width: 900\n    xAxis:\n      showLabel: false\n---\n%%{init: {'xyChart': {'height': 400}}}%%\nxychart-beta\n")
    check c.cfgStr("theme", "") == "dark"
    check c.cfgSub("xyChart").cfgFloat("width", 0) == 900 and c.cfgSub("xyChart").cfgFloat("height", 0) == 400
    check not c.cfgSub("xyChart").cfgSub("xAxis").cfgBool("showLabel", true)
  test "theme variables come from Mermaid's themes and are overridable":
    check chartVars("pie\n", "dark").str("pie1") != chartVars("pie\n", "default").str("pie1")
    check chartVars("%%{init: {'themeVariables': {'pie1': '#123456'}}}%%\npie\n").str("pie1") == "#123456"
  test "detection":
    check detectDiagramType(pie) == "pie" and detectDiagramType(xy) == "xychart" and detectDiagramType(tl) == "timeline"
    check detectDiagramType(qd) == "quadrant" and detectDiagramType(jr) == "journey"
  test "every chart renders to non-blank pixels":
    for chart in [pie, xy, tl, qd, jr]:
      let img = renderMermaidToImage(chart, fontPath, 1.0)
      var ink = 0
      for i in 0 ..< img.width * img.height:
        if img.rgba[i * 4 + 3] > 0 and (img.rgba[i * 4] < 235 or img.rgba[i * 4 + 1] < 235): inc ink
      check img.width > 200 and img.height > 150 and ink > 1000
  test "pie: slices below 1 % are dropped, percentages use the total, showData appears in the legend":
    let s = renderMermaidToSvg("pie showData\n \"A\" : 98\n \"B\" : 1\n \"C\" : 100\n", fontPath, svgText = true)
    check ">49%</text>" in s and ">50%</text>" in s and ">1%</text>" notin s and ">A [98]</text>" in s
  test "pie: invalid input raises a clear error":
    expect ChartError: discard renderMermaidToSvg("pie\n \"A\" : -3\n", fontPath)
    expect ChartError: discard renderMermaidToSvg("pie\n A : 3\n", fontPath)
  test "xychart: d3-style ticks, rotated y title, legend names":
    let s = renderMermaidToSvg("xychart-beta\n x-axis [a, b]\n y-axis \"Units\" 0 --> 100\n bar \"Series\" [10, 100]\n", fontPath, svgText = true)
    for tick in ["0", "10", "50", "100"]: check ">" & tick & "</text>" in s
    check "rotate(270)" in s and ">Series</text>" in s
  test "xychart: horizontal orientation and linear x-axis render":
    check renderMermaidToSvg("xychart-beta horizontal\n x-axis [a, b]\n bar [1, 2]\n", fontPath).len > 500
    check renderMermaidToSvg("xychart-beta\n x-axis 0 --> 10\n line [1, 5, 2]\n", fontPath).len > 500
  test "timeline: sections, wrapped period boxes, several events per period":
    let s = renderMermaidToSvg(tl, fontPath, svgText = true)
    for w in [">History</text>", ">Early</text>", ">Facebook</text>", ">Google</text>"]: check w in s
  test "quadrant: labels, points and rotated axis labels":
    let s = renderMermaidToSvg(qd, fontPath, svgText = true)
    check ">P1</text>" in s and ">A</text>" in s and "rotate(-90)" in s
    expect ChartError: discard renderMermaidToSvg("quadrantChart\n P: [1.5, 0.2]\n", fontPath)
  test "journey: actors, faces, section header":
    let s = renderMermaidToSvg(jr, fontPath, svgText = true)
    check ">Me</text>" in s and ">Cat</text>" in s and ">Work</text>" in s
  test "chart SVGs are well-formed XML and outlined mode has no <text>":
    for chart in [pie, xy, tl, qd, jr]:
      let s = renderMermaidToSvg(chart, fontPath)
      check s.startsWith("<svg") and s.endsWith("</svg>\n") and "<text" notin s
  test "rotated text is replayed by the rasteriser: a y-axis label forms a tall, narrow strip of ink":
    let img = renderMermaidToImage("quadrantChart\n y-axis Bottom --> Top\n quadrant-1 A\n", fontPath, 1.0)
    var rows = 0
    for y in 0 ..< img.height:
      var ink = false
      for x in 0 ..< 24:
        let i = (y * img.width + x) * 4
        if img.rgba[i + 3] > 0 and img.rgba[i] < 120 and img.rgba[i + 1] < 120: ink = true
      if ink: inc rows
    check rows > 40          # unrotated text would touch only ~15 rows

suite "gradient fills and strokes (engine)":
  test "linear gradient fill interpolates across the shape":
    var buf = newSeq[uint32](40 * 10)
    let cv = vg.pvg_swcanvas_create(vg.PVG_ENGINE_OPTION_DEFAULT)
    discard vg.pvg_swcanvas_set_target(cv, addr buf[0], 40, 40, 10, vg.PVG_COLORSPACE_ABGR8888S)
    let sq = vg.pvg_shape_new()
    discard vg.pvg_shape_append_rect(sq, 0, 0, 40, 10, 0, 0, true)
    let g = vg.pvg_linear_gradient_new(0, 0, 40, 0)
    discard vg.pvg_gradient_add_stop(g, 0, 255, 0, 0, 255)
    discard vg.pvg_gradient_add_stop(g, 1, 0, 0, 255, 255)
    discard vg.pvg_shape_set_fill_gradient(sq, g)
    discard vg.pvg_canvas_add(cv, sq)
    discard vg.pvg_canvas_draw(cv, true)
    let left = buf[5 * 40 + 1]
    let right = buf[5 * 40 + 38]
    check (left and 255) > 230 and ((left shr 16) and 255) < 25          # red end (R low byte, B high)
    check (right and 255) < 25 and ((right shr 16) and 255) > 230        # blue end
  test "gradient strokes appear as gradients in the SVG output too":
    let s = renderMermaidToSvg("sankey-beta\na,b,5\nb,c,5\n", fontPath)
    check "<linearGradient" in s and "stroke=\"url(#lg" in s

suite "more chart diagrams":
  test "detection of the newer types":
    check detectDiagramType("packet-beta\n0-7: \"a\"") == "packet" and detectDiagramType("kanban\n a") == "kanban"
    check detectDiagramType("radar-beta\n") == "radar" and detectDiagramType("treemap-beta\n") == "treemap"
    check detectDiagramType("sankey-beta\n") == "sankey"
  test "packet: fields wider than a row continue on the next row; gaps are rejected":
    let s = renderMermaidToSvg("packet\n0-31: \"A\"\n32-95: \"B\"\n", fontPath, svgText = true)
    check ">32</text>" in s and ">64</text>" in s and ">95</text>" in s      # B is split 32-63 / 64-95
    expect ChartError: discard renderMermaidToSvg("packet\n0-7: \"A\"\n9-15: \"B\"\n", fontPath)
  test "kanban: sections, cards, tickets, assignees":
    let s = renderMermaidToSvg("kanban\n  Todo\n    t1[Write docs]@{ ticket: MC-1, assigned: 'ann', priority: 'High' }\n  Done\n    t2[Ship it]\n", fontPath, svgText = true)
    for w in [">Todo</text>", ">Done</text>", ">Write docs</text>", ">MC-1</text>", ">ann</text>"]: check w in s
  test "radar: axes, legend and validation":
    let s = renderMermaidToSvg("radar-beta\n axis a, b, c\n curve x[\"Xs\"]{1, 2, 3}\n max 5\n", fontPath, svgText = true)
    check ">Xs</text>" in s and ">a</text>" in s and ">c</text>" in s
    expect ChartError: discard renderMermaidToSvg("radar-beta\n axis a, b\n curve x{1, 2}\n", fontPath)
  test "treemap: section values are sums, classDef may follow its use":
    let s = renderMermaidToSvg("treemap\n\"A\"\n  \"x\": 30\n  \"y\": 12:::hot\n\"B\"\n  \"z\": 8\nclassDef hot fill:red\n", fontPath, svgText = true)
    check ">42</text>" in s and ">8</text>" in s and "rgb(255,0,0)" in s
  test "sankey: link widths conserve flow, circular links are rejected":
    let s = renderMermaidToSvg("sankey-beta\nA,B,10\nA,C,30\nB,D,10\nC,D,30\n", fontPath, svgText = true)
    check ">A</text>" in s and ">D</text>" in s and s.count(">40</text>") >= 2
    expect ChartError: discard renderMermaidToSvg("sankey-beta\na,b,1\nb,a,1\n", fontPath)
  test "pie options: bottom legend is taller, donut and highlight render":
    let base = "pie\n \"A\" : 60\n \"B\" : 40\n"
    let plain = renderMermaidToImage(base, fontPath, 1.0)
    let bottom = renderMermaidToImage("%%{init: {'pie': {'legendPosition': 'bottom'}}}%%\n" & base, fontPath, 1.0)
    check bottom.height > plain.height
    let donut = renderMermaidToSvg("%%{init: {'pie': {'donutHole': 0.5, 'highlightSlice': 'A'}}}%%\n" & base, fontPath)
    check donut.len > 500 and "scale(1.05)" in donut
  test "sankey: busy diagrams get an automatic height (no hairline ribbons), a configured height is respected":
    var csv = "sankey-beta\n"
    for i in 1 .. 14: csv.add "src" & $i & ",hub," & $(i * 3) & "\n"
    csv.add "hub,out,10\nhub,out2,20\n"
    let auto = renderMermaidToImage(csv, fontPath, 1.0)
    let fixed = renderMermaidToImage("%%{init: {'sankey': {'height': 400}}}%%\n" & csv, fontPath, 1.0)
    check auto.height > fixed.height
  test "kanban and journey support the classic Mermaid colours":
    let a = renderMermaidToSvg("kanban\n A\n  b\n", fontPath)
    let b = renderMermaidToSvg("%%{init: {'kanban': {'classicColors': true}}}%%\nkanban\n A\n  b\n", fontPath)
    check a != b
    let j1 = renderMermaidToSvg("journey\n section S\n T: 3: Me\n", fontPath)
    let j2 = renderMermaidToSvg("%%{init: {'journey': {'classicColors': true}}}%%\njourney\n section S\n T: 3: Me\n", fontPath)
    check j1 != j2
  test "journey: legend widens the left margin for long actor names":
    let narrow = renderMermaidToImage("journey\n section S\n T: 3: Me\n", fontPath, 1.0)
    let wide = renderMermaidToImage("journey\n section S\n T: 3: A really long actor name here\n", fontPath, 1.0)
    check wide.width > narrow.width
