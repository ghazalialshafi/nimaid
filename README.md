# nimaid

Mermaid **flowchart, sequence, state, ER, class, Gantt, Git graph and mindmap** renderer in pure Nim: `.mmd` text → PNG / GIF / SVG, with colour emoji (Noto Color Emoji).

Pipeline: `preprocess` (front matter, directives, comments) → `flowparser`
→ `flowdb` → recursive layout (`dagre_adapter`, port of mermaid's dagre driver, using our own
`dagre_nim`) → PureVG software canvas → built-in PNG encoder.

## Build & run
    ./build.sh                      # compiles bin/nimaid (pure Nim, no external libraries)
    bin/nimaid [--colors=64] [--font=f.ttf] [--scale=2] in.mmd out.png

Library: `renderFlowchartToPng(text, "out.png", "fonts/DejaVuSans.ttf")` in `src/nimaid.nim`.

## How to use
  To get started read the full [usage guide](docs/USAGE.md). Documentation are in improvement.

  You can also browse sample files and generated images in the [examples folder](examples/).

## Module map (src/nimaid)
| module | role |
|---|---|
| `flowparser` | jison lexer (start-condition stack, first-match rules) + recursive-descent grammar |
| `flowdb` | vertices/edges/subgraphs/classes, link destructuring, `@{ }` metadata, `getData` |
| `shapereg` | generated alias→handler table for all mermaid shapes |
| `shapes` | geometry (size, paths, label offset, outline) for ~55 shapes |
| `dagre_adapter` | cluster/anchor edge rewriting, independent-cluster extraction, recursive layout, self-loops |
| `outline` | edge ↔ shape-border intersection |
| `curves` | d3 curves: basis (default), linear, cardinal, catmullRom, natural, monotoneX/Y, step*, bumpX/Y |
| `styles` | `classDef` / `style` / `linkStyle` → fill, stroke, width, dash, colour, opacity |
| `label` / `textmetrics` | entities, markdown markers, 200px word-wrap, PureVG text measurement |
| `gfx` / `svg` | recording scene graph (same `pvg_*` API as the painters) replayed to PureVG or written as SVG |
| `deflate` / `png` / `quant` / `gif` | own DEFLATE compressor, adaptive-filter PNG (truecolour or palette), median-cut quantiser, GIF89a |
| `painter` / `purevg` | drawing, generic `rasterizeScene`, PNG encoder, vector engine |
| `diagrams` | state / ER / class parsers that translate into the flowchart layout input (shared layout, boxes, markers) |
| `gantt` / `gitgraph` / `mindmap` / `drawkit` | self-contained layouts + painting for the non-graph diagrams |
| `sequence` | sequence diagrams: parser/DB + layout (port of `sequenceRenderer.ts` rules) + painting |
| `emoji` / `inflate` | Noto Color Emoji OpenType-SVG glyph extraction (cmap, GSUB ligatures, gzip) |
