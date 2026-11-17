# nimaid vector engine (PureVG)

`src/nimaid/purevg.nim` is a pure-Nim 2D vector engine with a small C-style API (`pvg_*`). No shared libraries.
Internals in `src/nimaid/purevg/`:

| File | Role |
|---|---|
| core.nim | matrices, path segments (M/L/Q/C/Z), Bezier flattening |
| raster.nim | scanline rasteriser (nonzero/even-odd), layers, gradients |
| stroke.nim | caps, joins, miter limit, dashes |
| ttf.nim | TrueType reader: cmap, glyf, hmtx, legacy `kern` kerning |
| svgload.nim | `<use>` inliner + nanosvg bridge (emoji SVG) |
| nanosvg.nim | vendored nanosvg-nim parser |

## SVG output (`src/nimaid/svg.nim`)
* Default: text outlined from the same TTF engine as the PNG (glyphs defined once, placed with `<use>`): font-independent, exact layout.
* `--svg-text=text`: live selectable `<text>` (explicit baseline, `textLength`).
* Emoji flattened to native paths + gradients, defined once per distinct emoji. Compact relative path data.

Build: `./build.sh` (or `nim c -d:release -o:bin/nimaid src/nimaid_cli.nim`)
Run:   `bin/nimaid [--svg-text=text] in.mmd out.{png,gif,svg}`
