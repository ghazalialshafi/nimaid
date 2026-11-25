# Adding a diagram type

The flowchart code is organised so that only the *front half* is diagram-specific; painting, rasterisation, SVG and encoding are shared.
`sequence.nim` is the worked example of a non-graph diagram (`parse` → `layout` → `paint` into a scene). `diagrams.nim` is the example of translating into the flowchart layout.

## Checklist

1. **Ground truth.** Get Mermaid's grammar (`diagrams/<type>/parser/<type>.jison`), data model (`<type>Db.ts`), renderer (`<type>Renderer.ts`) and parser specs (`parser/*.spec.js`).
2. **Detect.** Add the keyword in `src/nimaid/detect.nim` (`detectDiagramType`) and a branch in `buildMermaidScene` (`src/nimaid.nim`).
3. **Parse.** Use `flowparser.nim` as a template: port the jison lexer rules *in file order* with the start-condition stack, then write recursive descent for the grammar. Keep Mermaid's quirks. Simple line-based diagrams can use a small hand-written parser like `diagrams.nim`.
4. **Data model.** Port `<type>Db.ts` to `<type>db.nim` with public accessors for tests.
5. **Test first.** Extract the spec cases (`tests/extract_specs.py`), expose DB getters in `tools/dumpdb.nim`, extend `resolve()` in `tests/conformance.py`, and drive the pass rate up *before* drawing.
6. **Layout.**
   * Graph-like (class, state, ER, requirement): reuse `dagre_adapter.nim` — build a `FlowChartData`-style structure (nodes sized with `shapes.buildGeom`, edges, optional clusters).
   * Non-graph (sequence, Gantt, pie, timeline): compute coordinates in your own module.
7. **Paint.** Emit paints into a scene and return `(scene, bounds)`; `composeScene` adds the margin, title band and background, and PNG, GIF and SVG then work automatically. Public helpers: `drawkit.nim` — `kRect`, `kLine`, `kCurve`, `kCircle`, `kPoly` — and `textmetrics.drawLabel` for text (it handles emoji and measuring). For anything else call the `pvg_*` API from `gfx` directly. `bounds` is a `DiagramBounds` tuple `(minX, minY, maxX, maxY)`.
8. **Verify.** Add an `examples/<type>.mmd` and its golden `examples/<type>.png`, run `python3 tests/visual_regression.py`, and add a test to `tests/test_purevg.nim` if you touched the engine.
9. **Document.** Add the type to the README table and `docs/reference/diagram-syntax.md` (supported / not-yet lists), and a section to Tutorial 4 with a source file in `docs/examples/`.

## A worked example: `pie.nim`

`src/nimaid/pie.nim` (≈ 130 lines) is the smallest complete diagram module and a good template for **chart-style** diagrams:

* a hand-written parser that raises `ChartError` with a Mermaid-style message,
* `ChartVars` for theme variables (`chartVars(text, themeName)` — Mermaid's evaluated themes plus the diagram's own overrides) and `cv.cfg` (`readConfig`) for nested config such as `xyChart: {width: 900}`,
* geometry copied from Mermaid's renderer and drawn with `chartkit` helpers (`drawT` for baseline/anchor text, `kWedge`, `kPath`, `arrowHead`, `styleShape`) and `drawkit` (`kRect`, `kCircle`, …).

For richer layouts see `xychart.nim` (space-allocation orchestrator, axes) and `timeline.nim` (measured boxes).
Where Mermaid's source is available (the `diagrams/<type>/` folder in its repository), port its **renderer constants and layout order** and its **theme variables**; the theme data for all five themes is already embedded (`src/nimaid/data/chart_themes.json`, regenerate with the helper in `tools/themes`).

## Minimal skeleton

This compiles and runs as-is (it was checked while writing this guide):

```nim
# src/nimaid/donut.nim
import std/options
import gfx, theme, painter, drawkit

proc donutScene*(text: string, th: FlowTheme): (Pvg_Paint, DiagramBounds) =
  ## 1. parse `text`   2. compute the geometry   3. paint it with the drawkit helpers
  let root = pvg_scene_new()
  kCircle(root, 200, 150, 100, some(th.nodeBkg), some(th.nodeBorder), 2.0)
  kLine(root, 200, 150, 300, 150, th.lineColor, 2.0)
  (root, (minX: 0.0, minY: 0.0, maxX: 400.0, maxY: 300.0))
```

Then hook it up in `buildMermaidScene` (`src/nimaid.nim`), next to the other branches:

```nim
of "donut":
  let (scene, bounds) = donutScene(text, th)
  result = composeScene(scene, bounds, th, 16.0, scale)
```

and teach `detectDiagramType` (`src/nimaid/detect.nim`) to return `"donut"` for text starting with `donut`. Add the type to the CLI's "supported" message in `src/nimaid_cli.nim`.

## What is still open

Not implemented yet, roughly cheapest first: **requirement** (reuse the dagre layout and the flowchart shapes), **block** (its own grid layout), **C4**, **treeView**. Heavier: **architecture** (needs a force-directed layout), **venn**, **ishikawa**, **wardley**, **cynefin**, **railroad**.
The cloned Mermaid repository has the grammar (`packages/parser/src/language/<type>/`), the database and renderer (`packages/mermaid/src/diagrams/<type>/`) and — for d3-based layouts — the npm package of the d3 module (`npm pack d3-sankey` is how the sankey port was checked).
