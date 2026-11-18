# Output formats reference

The format is chosen by the output file extension (`.png`, `.gif`, `.svg`). All formats come from one drawing pass into a recording scene graph, so they always agree.

## PNG

* Truecolour RGBA, 8 bits per channel, **straight alpha**.
* Encoder is in-repo (`png.nim` + `deflate.nim`): for every row the best of the five PNG filters (None/Sub/Up/Average/Paeth) is chosen by a minimum-sum-of-absolute-differences score, followed by a real DEFLATE compressor.
* `--colors=N` (2…256) quantises with a median-cut palette and writes a palette PNG (`PLTE`, plus `tRNS` when needed). Transparency in palette mode is **binary**: pixels with alpha < 128 become fully transparent (palette index 0), all others fully opaque. Diagrams normally have an opaque background, so this only matters for transparent-background themes.
* `--scale=N` sets the pixel scale (default 2).

Library: `encodePng(rgba, w, h, colors = 0): seq[byte]`, `writePng(path, rgba, w, h, colors = 0)`.

## GIF

* Static GIF89a, one frame, 256-colour (or fewer with `--colors=N`) median-cut palette, LZW compression.
* Binary transparency, as for palette PNG: pixels with alpha < 128 map to a reserved transparent index (graphic control extension); all others are opaque.

Library: `encodeGif(rgba, w, h, colors = 256): seq[byte]`, `writeGif(path, rgba, w, h, colors = 256)`.

## SVG

* Scale-free; `width`/`height` are the 1× pixel size with a matching `viewBox`.
* Declares `xmlns` and `xmlns:xlink`; `role="img"`.
* Self-contained: no external references, no scripts, no fonts required (in the default mode).
* Paths are written with compact relative commands.

### Text modes

| `--svg-text=` | Representation | Pros | Cons |
|---|---|---|---|
| `paths` (default) | Each glyph defined once in `<defs>` as a `<path>`, placed with `<use>`; each text group has an `aria-label` | Exactly the PNG layout, kerning included; identical in every viewer; no font needed | Text isn't selectable/searchable; slightly larger |
| `text` | `<text>` lines with explicit baseline, `font-family` list, `textLength` + `lengthAdjust="spacing"` | Selectable, searchable, editable; smallest files | Needs a similar font on the viewer's machine; fallback fonts change glyph shapes (not widths) |

### Emoji

Each distinct emoji is converted once to a `<g id="eN">` of `<path>` elements with `<linearGradient>`/`<radialGradient>` definitions and referenced via `<use>` — the same in both text modes.

### Structure of a typical file

```xml
<svg xmlns=… xmlns:xlink=… width="535" height="214" viewBox="0 0 535 214" role="img">
<defs>
  <path id="g1" d="…"/> …                  glyph outlines (outlined mode)
  <g id="e1">…</g> <linearGradient …/>     emoji (if any)
</defs>
<path d="…" fill="rgb(…)" stroke=…/>       shapes, in painting order
<g aria-label="Start" transform="matrix(…)" fill=…><use xlink:href="#g12" x=… y=…/>…</g>
</svg>
```

Library: `renderMermaidToSvg(text, fontPath, emojiFontPath = "", themeName = "", svgText = false): string`; for your own scenes `toSvg(root, w, h, bg, fontFamily, textMode)`.

## Choosing

See the table in [Tutorial 6](../tutorials/06-output-formats.md#choosing-a-format).

## Not supported

Animated GIF, JPEG, WebP, PDF. (PDF can be produced by converting the SVG with any SVG-to-PDF tool.)
