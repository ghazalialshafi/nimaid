# PureVG API reference

PureVG is nimaid's built-in 2-D vector engine: a software rasteriser with strokes, TrueType text and SVG pictures behind a small C-style API.
Import it with `import nimaid/purevg` (or qualified, `from nimaid/purevg import …`, when you also import `nimaid`, because the scene recorder `nimaid/gfx` exports the same names).
For a guided tour see [Tutorial 8](../tutorials/08-purevg-engine.md).

## Conventions

* Units are pixels; origin top-left; **y grows downward**; angles in degrees (positive = clockwise on screen).
* Colours are bytes `r, g, b, a` (0–255), **straight** alpha.
* Text size is in **points** (× 96/72 = pixels).
* Every function returns a `Pvg_Result`. `PVG_RESULT_SUCCESS` = ok.
* Paints are reference-counted by Nim's GC; `pvg_paint_rel` is a no-op kept for API symmetry.
* Paint transform order: **scale, then rotate, then translate** (all about the origin). Order of the setter calls does not matter.

## Results

| Value | Typical cause |
|---|---|
| `PVG_RESULT_SUCCESS` | OK |
| `PVG_RESULT_INVALID_ARGUMENT` | nil paint, wrong paint kind, file not found, SVG with no shapes |
| `PVG_RESULT_INSUFFICIENT_CONDITION` | no canvas target set, no font, no geometry to measure |
| `PVG_RESULT_NOT_SUPPORTED` | font not TrueType-`glyf`, picture MIME type is not SVG |

(The other enum members exist for API completeness.)

## Engine and fonts

| Function | Description |
|---|---|
| `pvg_engine_init(threads: cuint)` | Initialise. The thread count is ignored (single-threaded). |
| `pvg_engine_term()` | Terminate (no-op; safe to call). |
| `pvg_font_load(path: cstring)` | Load a TrueType font from disk. Registered under the **file name without extension** (`DejaVuSans.ttf` → `"DejaVuSans"`). |
| `pvg_font_load_data(name, data, size, mimetype, copy)` | Load a font from memory under `name`. |
| `pvg_font_unload(path)` | Forget a font registered from `path`. |

The first font loaded becomes the default for text paints that name an unknown font.

## Canvas

| Function | Description |
|---|---|
| `pvg_swcanvas_create(op: Pvg_Engine_Option)` | Create a software canvas. The option is accepted and ignored. |
| `pvg_swcanvas_set_target(canvas, buffer: ptr uint32, stride, w, h: uint32, cs: Pvg_Colorspace)` | Attach a pixel buffer (`stride` in pixels). |
| `pvg_canvas_add(canvas, paint)` | Append a paint (drawn in insertion order). |
| `pvg_canvas_remove(canvas, paint)` | Remove all paints from the canvas. |
| `pvg_canvas_update(canvas)` / `pvg_canvas_sync(canvas)` | No-ops; drawing is synchronous. |
| `pvg_canvas_draw(canvas, clear: bool)` | Render. `clear = true` starts from transparent; `false` composites over the existing buffer. |
| `pvg_canvas_destroy(canvas)` | No-op. |

### Colour spaces

| Value | Bytes in memory | Alpha |
|---|---|---|
| `PVG_COLORSPACE_ABGR8888S` | R G B A | straight — **use this for PNG output** |
| `PVG_COLORSPACE_ABGR8888` | R G B A | premultiplied |
| `PVG_COLORSPACE_ARGB8888S` / `ARGB8888` | B G R A | straight / premultiplied |
| `PVG_COLORSPACE_XBGR8888` / `XRGB8888` | R G B x / B G R x | opaque |

`PVG_COLORSPACE_GRAYSCALE8` is declared but not implemented.

## Paints (common)

| Function | Description |
|---|---|
| `pvg_scene_new()` / `pvg_scene_add(scene, paint)` | A group of paints; transforms and opacity apply to the whole group. A scene with opacity < 255 is composited as one layer. |
| `pvg_shape_new()` / `pvg_text_new()` / `pvg_picture_new()` | Create a paint. |
| `pvg_paint_translate(p, x, y)` | Move by (x, y). |
| `pvg_paint_scale(p, factor)` | Uniform scale (stroke widths scale too). |
| `pvg_paint_rotate(p, degrees)` | Rotate. |
| `pvg_paint_set_opacity(p, 0..255)` | Opacity. For shapes it multiplies fill and stroke alpha. |
| `pvg_paint_get_aabb(p, &x, &y, &w, &h)` | Axis-aligned bounding box in canvas coordinates (shapes, text, scenes). |
| `pvg_paint_rel(p)` | No-op. |

## Shapes

| Function | Description |
|---|---|
| `pvg_shape_move_to(p, x, y)` · `pvg_shape_line_to(p, x, y)` · `pvg_shape_cubic_to(p, x1, y1, x2, y2, x, y)` · `pvg_shape_close(p)` | Build a path. |
| `pvg_shape_append_rect(p, x, y, w, h, rx, ry, cw)` | Rectangle; `rx`,`ry` > 0 give rounded corners (clamped to half the size). |
| `pvg_shape_append_circle(p, cx, cy, rx, ry, cw)` | Ellipse / circle. |
| `pvg_shape_reset(p)` | Clear the path. |
| `pvg_shape_set_fill_color(p, r, g, b, a)` | Fill (nonzero rule). Without a fill call the shape is not filled. |
| `pvg_shape_set_stroke_width(p, w)` · `pvg_shape_set_stroke_color(p, r, g, b, a)` | Stroke (a width of 0 disables it). |
| `pvg_shape_set_stroke_dash(p, ptr cfloat, count, offset)` | Dash lengths (on, off, on, …). An odd count is repeated. `nil` clears. |
| `pvg_shape_set_stroke_cap(p, cap)` | `BUTT`, `ROUND`, `SQUARE` — default **square**. |
| `pvg_linear_gradient_new(x1, y1, x2, y2)` · `pvg_gradient_add_stop(g, offset, r, g, b, a)` | Create a linear gradient in the shape's own coordinates (offsets 0–1, per-stop alpha). |
| `pvg_shape_set_fill_gradient(p, g)` · `pvg_shape_set_stroke_gradient(p, g)` | Use a gradient instead of the solid fill / stroke colour (the stroke gradient follows the outline, e.g. sankey ribbons). The SVG writer emits matching `<linearGradient>` definitions. |
| `pvg_shape_set_stroke_join(p, join)` | `MITER`, `ROUND`, `BEVEL` — default **bevel**; miter limit is 4. |

Fill is drawn first, then the stroke centred on the outline. Both are anti-aliased.

## Text

| Function | Description |
|---|---|
| `pvg_text_set_font(p, name)` | Registered font name (see `pvg_font_load`). |
| `pvg_text_set_size(p, points)` | Size in points. |
| `pvg_text_set_text(p, utf8)` | Text; `\n` starts a new line. |
| `pvg_text_set_color(p, r, g, b)` | Text colour (opaque). |
| `pvg_text_align(p, x, y)` | Alignment 0…1 relative to the paint origin. Per-line horizontal alignment, block vertical alignment. |
| `pvg_text_layout(p, w, h)` | Accepted, no-op (no wrapping/box layout). |
| `pvg_text_get_text_metrics(p, &metrics)` | `ascent`, `descent`, `linegap`, `advance` (line advance) in pixels. |
| `pvg_text_line_count(p)` | Number of lines. |

Layout rules: pixel scale `= size × 96/72 / unitsPerEm`; baseline of the first line at `ascent`; line advance `= ascent − descent + lineGap`; kerning from the `kern` table; codepoints the font lacks are skipped.

## Pictures

| Function | Description |
|---|---|
| `pvg_picture_load_data(pic, data, size, mimetype, rpath, copy)` | Load an SVG from memory. `mimetype` must be `"svg"`, `"svg+xml"` or `"image/svg+xml"`. Parsed pictures are cached by content. |
| `pvg_picture_set_size(pic, w, h)` | Fit the picture into a `w × h` box, aspect ratio preserved, centred. Without it the SVG's own size is used. |

Supported SVG: paths (all commands), `rect circle ellipse line polyline polygon`, `g`, `defs`, `use` (also nested), `transform`, `style` and presentation attributes, `opacity`, `fill-rule`, strokes (width, caps, joins, dashes, miter limit), solid colours, and linear/radial gradients (`gradientTransform`, `xlink:href`; spread mode is always *pad*).
Not supported: filters, masks, clip-paths, patterns, `<image>`, `<text>`.

## Internal modules (`nimaid/purevg/*`)

These are the building blocks behind the API above. They are importable and covered by `tests/test_purevg.nim`.

| Module | Key procs |
|---|---|
| `core` | `Mat`, `Pt`, `Seg` (`M L Q C Z`), `Poly`; `*` (matrix product), `apply`, `inverse`, `scaleOf`, `translateM`, `scaleM`, `rotateM`, `flatten(segs, matrix, tol)`, `bounds` |
| `raster` | `rasterize(polys, evenOdd, w, h): Mask` (coverage 0…1), `Layer` (premultiplied float RGBA), `blend`, `blendGradient`, `compositeGroup` |
| `stroke` | `strokePolys(polys, width, cap, join, dash, dashOffset, miter)` → polygons to fill with the nonzero rule |
| `ttf` | `parseFont(data)`, `gidOf(font, codepoint)`, `glyph(font, codepoint)` (outline + advance), `kernPair(font, leftGid, rightGid)`, `lineAdvance`, `codepoints(utf8)` |
| `svgload` | `inlineUse(svg)`, `loadSvg(svg): Picture` (shapes with fills, strokes, gradient stops) |

## Limitations

* Software rendering, single thread.
* TrueType (`glyf`) fonts only; no CFF/`.otf`, no `.ttc`, no GPOS/GSUB shaping (kerning comes from the legacy `kern` table; no ligatures, no complex scripts).
* Linear gradients only (no radial gradients on shapes — use an SVG picture for those); no clipping/masking; no blend modes (e.g. `multiply`).
