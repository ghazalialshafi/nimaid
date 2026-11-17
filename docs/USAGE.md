# Using nimaid

Supports **flowcharts**, **sequence**, **state**, **ER**, **class**, **Gantt**, **Git graph** and **mindmap** diagrams (auto-detected from the first keyword), with colour emoji, 5 themes and PNG/GIF/SVG export.

## 1. Build
Requirements: Nim >= 2.0 and a C compiler. Nothing else: rendering, fonts and SVG are pure Nim.

    ./build.sh          # compiles bin/nimaid

## 2. Command line
    bin/nimaid [--colors=2..256] [--font=path.ttf] [--emoji=NotoColorEmoji-Regular.ttf] [--theme=default|dark|forest|neutral|base] [--dagre=legacy|modern] [--scale=2] input.mmd output.png

`--emoji` defaults to `fonts/NotoColorEmoji-Regular.ttf` (bundled). `--scale` multiplies pixel size (2 = retina). `--font` must be a TTF; PureVG names it by file name.

## 3. As a library
```nim
import nimaid
# one call: parse -> layout -> raster -> PNG
discard renderFlowchartToPng(readFile("a.mmd"), "a.png", "fonts/DejaVuSans.ttf")

# step by step
discard pvg_engine_init(0)
discard initTextMetrics("fonts/DejaVuSans.ttf")    # must come BEFORE layout (text sizes drive node sizes)
let layout = parseAndLayoutFlowchart(readFile("a.mmd"))
let img = renderToImage(layout, defaultTheme(), margin = 16, scale = 2)   # RGBA bytes: img.rgba, img.width, img.height
writePng("a.png", img.rgba, img.width, img.height)
discard pvg_engine_term()
```
Theme: `defaultTheme()` returns a `FlowTheme` (colours, font size, stroke width); copy and modify fields to restyle.

## 2b. Output formats (chosen by the output file's extension)
| ext | what | typical size |
|---|---|---|
| `.png` | truecolour RGBA, adaptive PNG filters + real DEFLATE (own encoder) | 40–320 KB at 2x (was MBs) |
| `.png --colors=64` | palette PNG (median-cut quantiser) | ~35–125 KB |
| `.gif` | static GIF89a, 256-colour palette, LZW (`--colors=N` to shrink) | ~50–150 KB |
| `.svg` | vector: paths + `<text>` + embedded vector emoji; scale-free | 8–65 KB |

`--scale=1` halves the pixel dimensions again for raster formats. SVG notes: text is real `<text>` with font-family
`'DejaVu Sans', Verdana, 'Trebuchet MS', Arial, sans-serif` (text-only lines are centre-anchored so other fonts still look right);
emoji are inlined as vector SVG with namespaced ids. Verified by rendering the SVGs with resvg.
Library: `renderMermaidToFile(text, "out.svg|png|gif", font, scale, emojiFont, theme, colors)`, `renderMermaidToSvg`,
`renderMermaidToImage` (RGBA), `encodePng(rgba,w,h,colors)`, `encodeGif(rgba,w,h,colors)`.
All formats come from one drawing pass: the painters draw into a recording scene graph (`gfx.nim`) that is replayed to PureVG for
raster output or serialised by `svg.nim`.

## 3a. Themes
Five built-in themes with Mermaid's exact colours (evaluated from its own `theme-*.js`): `default`, `dark`, `forest`, `neutral`, `base`.
Select with `--theme=dark`, or in the diagram itself (CLI wins):

    %%{init: {'theme': 'forest', 'themeVariables': {'primaryColor': '#ffcc00', 'lineColor': '#0066cc'}}}%%
    ---
    config:
      theme: dark
      themeVariables:
        primaryColor: "#334455"
    ---

`themeVariables` supported: `background mainBkg primaryColor primaryBorderColor nodeBorder nodeTextColor primaryTextColor clusterBkg tertiaryColor
clusterBorder lineColor arrowheadColor textColor titleColor edgeLabelBackground fontSize fontFamily` and the sequence colours
`actorBkg actorBorder actorTextColor actorLineColor signalColor signalTextColor noteBkgColor noteBorderColor noteTextColor
labelBoxBkgColor labelBoxBorderColor loopTextColor activationBkgColor activationBorderColor sequenceNumberColor`
(hex / `rgb()` colours; CSS colour *names* are not accepted in `themeVariables`). Regenerate presets with `tools/themes/dump.mjs` (needs `npm i khroma`).
Library: `themeByName("dark")`, `themeFor(text, forcedName)`, `FlowTheme.applyOverrides(table)`.

## 3d. State, ER and class diagrams
These three are line-based parsers (`diagrams.nim`) that translate into the flowchart layout input, so they share dagre layout,
clusters, themes, curves and all exports. They cover the commonly used syntax, not every Mermaid option.

**stateDiagram / stateDiagram-v2**: `[*] --> A`, `A --> B : label`, `state "Long name" as s`, `s : description`, composite states
`state X { ... }` (nested, own start/end), `<<choice>>`, `<<fork>>`/`<<join>>`, `note left|right of X : text` (and multi-line
`note ... end note`), `direction LR`, `title`. Not yet: concurrency `--`, `classDef` styling, history states.

**erDiagram**: `A ||--o{ B : label` with all cardinalities (`|| |o o| }| |{ }o o{`), solid `--` / dashed `..` relationships, entity
blocks with `type name PK|FK|UK "comment"` rows (key/comment columns appear when used), `NAME["Alias"]`, `direction`. Not yet: word
cardinalities (`one or more`), `style`/`classDef`.

**classDiagram**: `class X { +attr  +method() }`, `X : member`, `<<interface>>` annotations, generics `Foo~T~`, relations
`<|-- --|> *-- --* o-- --o --> <-- ..> <.. ..|> <|.. -- ..` (+ `()--` lollipop) with labels, `direction`. Members with `(` are methods.
Not yet: cardinality labels at relation ends, namespaces, notes, `classDef`.

## 3e. Gantt, Git graph, mindmap
Own layouts (no graph engine). Scene helpers live in `drawkit.nim`.
- **gantt**: `title`, `dateFormat YYYY-MM-DD`, `axisFormat` (`%Y %y %m %d %e %b %B %a`), `section`, tasks `name : [crit|done|active|milestone,] [id,] start|after a b, end|duration`
  (`d w h m s` durations; a task with only a duration starts after the previous one), Mermaid default colours, week/month tick spacing, bars/labels
  outside when too narrow. Not yet: other `dateFormat`s, `excludes`/weekends, `todayMarker`, `click`, themed colours (uses the default theme palette).
- **gitGraph**: `commit [id:] [tag:] [type: NORMAL|REVERSE|HIGHLIGHT]`, `branch [order:]`, `checkout`/`switch`, `merge [id:] [tag:] [type:]`, `cherry-pick id:`.
  Thick lane lines, merge/branch curves, tags, Mermaid's default branch colours. Differences: commit ids are drawn horizontally (Mermaid rotates them 45 deg),
  left-to-right only (no `TB`/`BT`), no `parallelCommits`.
- **mindmap**: indentation tree, node shapes `id[sq] id(round) id((circle)) id))bang(( id)cloud( id{{hexagon}}`, coloured branches, emoji. Layout is a balanced
  left/right tree, not Mermaid's force-directed layout, so positions differ; icons and `:::classes` are ignored.

## 3b. Colour emoji
Noto Color Emoji is read directly (OpenType-SVG table, `src/nimaid/emoji.nim` + `inflate.nim`): plain emoji, VS16 (`❤️`), skin tones,
flags, ZWJ families, keycaps. Each emoji is rendered as a PureVG SVG picture inline with the text, in node labels, edge labels, titles,
cluster titles and sequence diagrams. Text-style symbols such as `→ ♥` stay in the normal font unless followed by VS16.
Library: `loadEmojiFont(path)` before layout (or pass `emojiFontPath` to `renderFlowchartToPng` / `renderMermaidToPng`).

## 3c. Sequence diagrams
```
sequenceDiagram
    title Order flow
    autonumber
    actor U as User
    participant W as Web
    U->>+W: Place order
    W-->>-U: Done
```
**Supported**: `participant`/`actor` (+`as`), messages `->> -->> -> --> -x --x -) --) <<->> <<-->>`, `+`/`-` shorthand and
`activate`/`deactivate` (nested activation bars), `autonumber [start step | off]`, notes (`left of`, `right of`, `over A,B`),
`box` groups (colour + title), fragments `loop opt alt/else par/and critical/option break rect <color>` (nested, with titles), self-messages, `<br/>`, entities,
`title`, front matter title, mirrored actors, Mermaid default spacing/colours, emoji.
**Not yet**: `create`/`destroy` actor placement, half-arrows (`-|\` …), `links`/`properties`,
`wrap` text wrapping, `participant X@{ type: ... }` icons (other actor shapes), config overrides (`mirrorActors`, widths, …), themes.

## 4. What is supported
**Syntax (ported from `flow.jison`)**: `graph`/`flowchart` + `TB TD BT LR RL`; front matter `title:`; `%%` comments and
`%%{init}%%` directives (stripped); `;` or newline separators; chaining (`A-->B-->C`), `A & B --> C & D`;
all link types `--> --- -.-> ==> ~~~ --o --x o--o x--x <-->`, lengths (`---->`), text (`-- t -->`, `-->|t|`, `== t ==>`, `-. t .->`),
edge ids (`e1@-->`); `subgraph id [title]` (nested, `direction`), edges to/from subgraphs; `classDef`, `class`, `:::`, `style`,
`linkStyle` (incl. `default`, lists, `interpolate`); `click` (parsed); `accTitle/accDescr`; `@{ shape: …, label: … }`.

**Shapes**: classic brackets `[] () ([]) [[]] [()] (()) ((())) {} {{}} [/ /] [\ \] [/ \] [\ /] >]` and every shape in Mermaid's
registry via `@{ shape: … }` (rect, rounded, stadium, cyl, h-cyl, lin-cyl, diam, hex, lean-r/l, trap-b/t, circ, dbl-circ, sm-circ,
fr-circ, f-circ, cross-circ, fork, hourglass, brace, brace-r, braces, bolt, doc, docs, lin-doc, tag-doc, delay, curv-trap, div-rect,
tri, flip-tri, win-pane, notch-rect, notch-pent, sl-rect, st-rect, bow-rect, tag-rect, lin-rect, flag, cloud, bang, text, bucket,
folder, browser, console, person, data-store, state, choice, note, anchor …). Dimensions follow Mermaid's formulas.

**Styling**: `fill stroke stroke-width stroke-dasharray color opacity font-size` from `classDef`/`style`/`linkStyle`;
named CSS colours, `#rgb/#rrggbb`, `rgb()`.

**Layout**: full Mermaid dagre driver (compound clusters, independent clusters laid out recursively with alternating direction,
`direction` inside subgraphs, anchor redirection of cluster edges, self-loops, multi-edges) on top of `dagre_nim` in
`legacyOrder` mode (matches `dagre-d3-es`).

**Edges**: arrowheads (point, circle, cross, double), thick/dotted/invisible, labels, curves
(basis default, linear, cardinal, catmullRom, natural, monotoneX/Y, step, stepBefore/After, bumpX/Y).

**Labels**: `<br/>`, `\n`, HTML/Mermaid entities (`#quot;`, `#9829;`), markdown markers stripped, 200px word wrap.

## 5. What is NOT supported (yet)
- Animated GIF, JPEG/WebP, PDF. (PureVG's own savers aren't used: PNG/GIF/SVG are produced by in-repo encoders so they work with the default PureVG build.)
- Glyph coverage beyond the loaded TTF (bundled DejaVu: Latin/Greek/Cyrillic/symbols; no CJK). Emoji need the emoji font (bundled). One font only, no bold/italic runs.
- `@{ view: collapsed }`, icon/image assets (`icon:`/`img:` render as plain boxes), clickable links/tooltips (parsed only), `look: handDrawn`, `htmlLabels` rich HTML, KaTeX math.
- Rare layout deviations: ~2 in 1,800 random compound graphs differ by 1–10px in dummy-node x of duplicate parallel edges.
- Other diagram types (see below).

## 6. Adding another chart type (pie, …)
The flowchart code is organised so that only the *front half* is diagram-specific; layout/raster/PNG are reusable.

1. **Get the ground truth**: Mermaid's grammar `diagrams/<type>/parser/<type>.jison`, DB `<type>Db.ts`, renderer `<type>Renderer.ts`,
   and specs `parser/*.spec.js` (all are in your `mermaid-flow.zip` style checkout).
2. **Detect**: add the keyword to `src/nimaid/detect.nim` (`detectDiagramType`) and a branch in `renderMermaidToPng` (`src/nimaid.nim`). `sequence.nim` is the worked example of a non-graph diagram: `parseX` → `layoutAndPaint` (returns a PureVG scene + bounds) → `rasterizeScene` (in `painter.nim`) → PNG.
3. **Parser**: copy `flowparser.nim` as a template. The recipe that worked: port the jison lexer rules *in file order*
   with the start-condition stack, then write recursive descent for the grammar. Keep Mermaid's quirks.
4. **DB**: port `<type>Db.ts` to `<type>db.nim` (public accessors for tests).
5. **Test first**: run `tests/extract_specs.py` on the new `parser/` folder, add the DB getters to `tools/dumpdb.nim`
   (or a sibling tool) and extend `resolve()` in `tests/conformance.py`. Drive pass-rate to ~100% before drawing.
6. **Layout**: graph-like diagrams (class, state, ER, requirement) reuse `dagre_adapter.nim` – build a `FlowChartData`-like
   structure (nodes with size from `shapes.buildGeom`, edges, optional clusters). Non-graph diagrams (sequence, gantt, pie, timeline)
   compute coordinates directly in their own module.
7. **Paint**: emit PureVG paints with the helpers in `painter.nim` (`emitPath`, `addText`, `setDash`) into a scene and hand it to
   `renderToImage`-style code (generalise `renderToImage` to take a scene + bounds). PNG encoding is shared.
8. **Validate** like the flowchart: differential test against the JS implementation (npm `mermaid` internals / `dagre-d3-es`) with
   a dump hook (`MMD_DUMP_LAYOUT` shows the pattern).
