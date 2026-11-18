## Use the PureVG engine directly (no Mermaid): shapes, strokes, dashes, text and an SVG picture.
import nimaid/purevg, nimaid/png

const W = 480
const H = 300

discard pvg_engine_init(0)
discard pvg_font_load("fonts/DejaVuSans.ttf")          # registered under its file name: "DejaVuSans"

var pixels = newSeq[uint32](W * H)                      # one uint32 per pixel (R,G,B,A bytes)
let canvas = pvg_swcanvas_create(PVG_ENGINE_OPTION_DEFAULT)
discard pvg_swcanvas_set_target(canvas, addr pixels[0], W, W, H, PVG_COLORSPACE_ABGR8888S)

# background
let bg = pvg_shape_new()
discard pvg_shape_append_rect(bg, 0, 0, W, H, 0, 0, true)
discard pvg_shape_set_fill_color(bg, 250, 250, 252, 255)
discard pvg_canvas_add(canvas, bg)

# rounded rectangle with fill + stroke
let card = pvg_shape_new()
discard pvg_shape_append_rect(card, 20, 20, 200, 110, 16, 16, true)
discard pvg_shape_set_fill_color(card, 200, 220, 255, 255)
discard pvg_shape_set_stroke_width(card, 4)
discard pvg_shape_set_stroke_color(card, 40, 70, 170, 255)
discard pvg_canvas_add(canvas, card)

# translucent circle with a dashed outline
let dot = pvg_shape_new()
discard pvg_shape_append_circle(dot, 330, 75, 50, 50, true)
discard pvg_shape_set_fill_color(dot, 255, 170, 0, 190)
discard pvg_shape_set_stroke_width(dot, 3)
discard pvg_shape_set_stroke_color(dot, 0, 0, 0, 255)
var dashes = [8.0'f32, 5.0'f32]
discard pvg_shape_set_stroke_dash(dot, addr dashes[0], 2, 0)
discard pvg_canvas_add(canvas, dot)

# a Bezier path with round joins and caps
let wave = pvg_shape_new()
discard pvg_shape_move_to(wave, 30, 230)
discard pvg_shape_cubic_to(wave, 120, 140, 200, 320, 300, 210)
discard pvg_shape_line_to(wave, 450, 190)
discard pvg_shape_set_stroke_width(wave, 10)
discard pvg_shape_set_stroke_color(wave, 200, 40, 40, 255)
discard pvg_shape_set_stroke_join(wave, PVG_STROKE_JOIN_ROUND)
discard pvg_shape_set_stroke_cap(wave, PVG_STROKE_CAP_ROUND)
discard pvg_canvas_add(canvas, wave)

# text, centred on (120, 75)
let label = pvg_text_new()
discard pvg_text_set_font(label, "DejaVuSans")
discard pvg_text_set_size(label, 16)                    # points (x 96/72 = pixels)
discard pvg_text_set_text(label, "Hello, PureVG!\nKerned & aligned")
discard pvg_text_set_color(label, 20, 30, 80)
discard pvg_text_align(label, 0.5, 0.5)                 # 0..1 relative to the text's own box
discard pvg_paint_translate(label, 120, 75)
discard pvg_canvas_add(canvas, label)

# an SVG picture (gradients are supported), scaled into a 60x60 box
const badge = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs><radialGradient id="g" cx="50%" cy="40%" r="60%">
    <stop offset="0" stop-color="#fff6a8"/><stop offset="1" stop-color="#ff7a00"/></radialGradient></defs>
  <circle cx="50" cy="50" r="46" fill="url(#g)" stroke="#a04000" stroke-width="4"/></svg>"""
let pic = pvg_picture_new()
discard pvg_picture_load_data(pic, badge.cstring, uint32(badge.len), "svg", nil, true)
discard pvg_picture_set_size(pic, 60, 60)
discard pvg_paint_translate(pic, 400, 20)
discard pvg_canvas_add(canvas, pic)

discard pvg_canvas_draw(canvas, true)
discard pvg_canvas_sync(canvas)

var rgba = newSeq[byte](W * H * 4)
copyMem(addr rgba[0], addr pixels[0], rgba.len)
writePng("engine_demo.png", rgba, W, H)
echo "wrote engine_demo.png"
discard pvg_engine_term()
