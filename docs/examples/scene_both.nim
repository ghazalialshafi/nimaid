## Draw ONCE into a recording scene, then export it as raster pixels AND as SVG.
## `gfx` has the same pvg_* API as the engine, but records a scene graph instead of drawing.
import nimaid/[gfx, svg, png]
from nimaid/purevg import pvg_engine_init, pvg_font_load

discard pvg_engine_init(0)
discard pvg_font_load("fonts/DejaVuSans.ttf")

let root = pvg_scene_new()
let bg = pvg_shape_new()
discard pvg_shape_append_rect(bg, 0, 0, 240, 120, 0, 0, true)
discard pvg_shape_set_fill_color(bg, 255, 255, 255, 255)
discard pvg_scene_add(root, bg)

let box = pvg_shape_new()
discard pvg_shape_append_rect(box, 20, 20, 200, 80, 12, 12, true)
discard pvg_shape_set_fill_color(box, 235, 235, 255, 255)
discard pvg_shape_set_stroke_width(box, 2)
discard pvg_shape_set_stroke_color(box, 140, 100, 220, 255)
discard pvg_scene_add(root, box)

let t = pvg_text_new()
discard pvg_text_set_font(t, "DejaVuSans")
discard pvg_text_set_size(t, 14)
discard pvg_text_set_text(t, "One scene,\ntwo formats")
discard pvg_text_set_color(t, 50, 50, 50)
discard pvg_text_align(t, 0.5, 0.5)
discard pvg_paint_translate(t, 120, 60)
discard pvg_scene_add(root, t)

# raster
let rgba = renderRgba(root, 240, 120)
writePng("scene_both.png", rgba, 240, 120)
# vector (outlined text by default; pass textMode = stText for live <text>)
writeFile("scene_both.svg", toSvg(root, 240, 120, [255'u8, 255, 255, 255]))
echo "wrote scene_both.png and scene_both.svg"
