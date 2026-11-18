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

Suggested order of difficulty (cheapest first): pie, requirement, timeline, journey, quadrant, sankey.

## Minimal skeleton

This compiles and runs as-is (it was checked while writing this guide):

```nim
# src/nimaid/pie.nim
import std/options
import gfx, theme, painter, drawkit

proc pieScene*(text: string, th: FlowTheme): (Pvg_Paint, DiagramBounds) =
  ## 1. parse `text`   2. compute the geometry   3. paint it with the drawkit helpers
  let root = pvg_scene_new()
  kCircle(root, 200, 150, 100, some(th.nodeBkg), some(th.nodeBorder), 2.0)
  kLine(root, 200, 150, 300, 150, th.lineColor, 2.0)
  (root, (minX: 0.0, minY: 0.0, maxX: 400.0, maxY: 300.0))
```

Then hook it up in `buildMermaidScene` (`src/nimaid.nim`), next to the sequence/gantt branches:

```nim
of "pie":
  let (scene, bounds) = pieScene(text, th)
  result = composeScene(scene, bounds, th, 16.0, scale)
```

and teach `detectDiagramType` (`src/nimaid/detect.nim`) to return `"pie"` for text starting with `pie`.
