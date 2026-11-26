# Diagram syntax reference

What each diagram type supports. "Not yet" lists are deliberate — anything not listed there but missing from Mermaid is also unsupported; please report it.

Common to all diagrams: `%% comments`, YAML front matter (`title`, `config.theme`, `config.themeVariables`), `%%{init: …}%%` directives (theme and `themeVariables`), and colour emoji.

## Flowchart

Keyword: `flowchart` / `graph` (+ `TB TD BT LR RL`). Also `flowchart-v2`.
The parser is a port of Mermaid's `flow.jison` lexer and grammar, including its quirks.

**Statements:** `;` or newline separators · chaining `A-->B-->C` · `A & B --> C & D` · `subgraph id [title] … end` (nested, own `direction`, edges to/from subgraphs) · `classDef` · `class` · `:::` · `style` · `linkStyle` (indexes, lists, `default`, `interpolate`) · `click` (parsed, not drawn) · `accTitle` / `accDescr` · `@{ shape: …, label: … }` node metadata · edge ids (`e1@-->`).

**Links:** `-->  ---  -.->  ==>  ~~~  --o  --x  o--o  x--x  <-->`, extra length (`---->`), text (`-- t -->`, `-->|t|`, `== t ==>`, `-. t .->`).

### Flowchart shapes

Classic brackets: `[]` rectangle · `()` rounded · `([])` stadium · `[[]]` subroutine · `[()]` cylinder · `(())` circle · `((()))` double circle · `{}` diamond · `{{}}` hexagon · `[/ /]` `[\ \]` `[/ \]` `[\ /]` parallelograms/trapezoids · `>]` flag.

Every shape in Mermaid's registry through `@{ shape: NAME }`:

`rect` `rounded` `stadium` `cyl` `h-cyl` `lin-cyl` `diam` `hex` `lean-r` `lean-l` `trap-b` `trap-t` `circ` `dbl-circ` `sm-circ` `fr-circ` `f-circ` `cross-circ` `fork` `hourglass` `brace` `brace-r` `braces` `bolt` `doc` `docs` `lin-doc` `tag-doc` `delay` `curv-trap` `div-rect` `tri` `flip-tri` `win-pane` `notch-rect` `notch-pent` `sl-rect` `st-rect` `bow-rect` `tag-rect` `lin-rect` `flag` `cloud` `bang` `text` `bucket` `folder` `browser` `console` `person` `data-store` `state` `choice` `note` `anchor` … (aliases are accepted). Node dimensions follow Mermaid's formulas.

**Styling:** `fill`, `stroke`, `stroke-width`, `stroke-dasharray`, `color`, `opacity`, `font-size` via `classDef` / `style` / `linkStyle`. Colours: `#rgb`, `#rrggbb`, `rgb()`, CSS names.

**Layout:** Mermaid's dagre driver: compound clusters, independently laid-out clusters (alternating direction), `direction` inside subgraphs, anchor redirection of cluster edges, self-loops, multi-edges — on top of `dagre_nim` in `legacyOrder` mode (matches `dagre-d3-es`).

**Edges:** arrowheads (point, circle, cross, double), thick / dotted / invisible, labels, curve types `basis` (default), `linear`, `cardinal`, `catmullRom`, `natural`, `monotoneX/Y`, `step`, `stepBefore/After`, `bumpX/Y`.

**Labels:** `<br/>`, `\n`, HTML/Mermaid entities (`#quot;`, `#9829;`), markdown markers stripped, 200 px word wrap.

**Not yet:** `@{ view: collapsed }`, icon/image assets (`icon:`/`img:` render as plain boxes), clickable links & tooltips (parsed only), `look: handDrawn`, rich HTML labels, KaTeX math.

## Sequence diagram

Keyword: `sequenceDiagram`.

* **Participants:** `participant`, `actor`, with `as` aliases; mirrored actors at the bottom; `box` groups (colour + title).
* **Messages:** `->>  -->>  ->  -->  -x  --x  -)  --)  <<->>  <<-->>`, self-messages, `<br/>`, entities.
* **Activations:** `+`/`-` shorthand or `activate`/`deactivate`, nested bars.
* **Other:** `autonumber [start step | off]`, `title`, notes (`left of`, `right of`, `over A,B`).
* **Fragments** (nestable, with titles): `loop`, `opt`, `alt/else`, `par/and`, `critical/option`, `break`, `rect <colour>`.

**Not yet:** `create`/`destroy` actor placement, half arrows (`-|\`), `links`/`properties`, `wrap` text wrapping, `participant X@{ type: … }` icon shapes, config overrides (`mirrorActors`, widths, …).

## State diagram

Keywords: `stateDiagram`, `stateDiagram-v2`. (Line-based parser translating into the flowchart layout, so it shares dagre layout, clusters, themes and curves.)

`[*] --> A` · `A --> B : label` · `state "Long name" as s` · `s : description` · composite `state X { … }` (nested, own start/end) · `<<choice>>`, `<<fork>>`, `<<join>>` · `note left|right of X : text` (and multi-line `note … end note`) · `direction LR` · `title`.

**Not yet:** concurrency (`--`), `classDef` styling, history states.

## Entity–relationship diagram

Keyword: `erDiagram`.

`A ||--o{ B : label` with every cardinality (`|| |o o| }| |{ }o o{`), identifying `--` / non-identifying `..` relationships · entity blocks with `type name PK|FK|UK "comment"` rows (key/comment columns appear when used) · `NAME["Alias"]` · `direction`.

**Not yet:** word cardinalities (`one or more`), `style` / `classDef`.

## Class diagram

Keyword: `classDiagram`.

`class X { +attr  +method() }` · `X : member` · `<<interface>>` annotations · generics `Foo~T~` · relations `<|-- --|> *-- --* o-- --o --> <-- ..> <.. ..|> <|.. -- ..` and lollipop `()--`, with labels · `direction`. Members containing `(` are methods.

**Not yet:** cardinality labels at relation ends, namespaces, notes, `classDef`.

## Gantt

Keyword: `gantt`.

`title` · `dateFormat YYYY-MM-DD` · `axisFormat` (`%Y %y %m %d %e %b %B %a`) · `section` · tasks `name : [crit|done|active|milestone,] [id,] start|after a b, end|duration` (`d w h m s`; a task with only a duration starts after the previous one) · Mermaid default colours · week/month tick spacing · bars and labels placed outside when too narrow.

**Not yet:** other `dateFormat`s, `excludes`/weekends, `todayMarker`, `click`, themed colours (uses the default palette).

## Git graph

Keyword: `gitGraph`.

`commit [id:] [tag:] [type: NORMAL|REVERSE|HIGHLIGHT]` · `branch [order:]` · `checkout` / `switch` · `merge [id:] [tag:] [type:]` · `cherry-pick id:`. Thick lane lines, merge/branch curves, tags, Mermaid's default branch colours.

**Differences:** commit ids are drawn horizontally (Mermaid rotates them 45°); left-to-right only (no `TB`/`BT`); no `parallelCommits`.

## Mindmap

Keyword: `mindmap`.

Indentation tree · node shapes `id[sq] id(round) id((circle)) id))bang(( id)cloud( id{{hexagon}}` · coloured branches · emoji. The layout is a balanced left/right tree, not Mermaid's force-directed layout, so positions differ; icons and `:::classes` are ignored.

## Pie chart

Keyword: `pie` (`showData`, `title …` may follow on the same line). Grammar from Mermaid's `pie.langium`.

`"label" : value` slices (label **quoted**, value ≥ 0, first occurrence of a duplicate label wins) · `title` · `showData` · `accTitle`/`accDescr` (ignored).
Geometry follows Mermaid's renderer: 450 px canvas, radius 185, outer ring, slices at 70 % opacity with a dark outline, percentage labels at 0.75 of the radius, right-hand legend; slices under 1 % are not drawn and percentages use the total of all values. Colours: `pie1…pie12`, `pieStrokeColor`, `pieOpacity`, `pieSectionTextColor`, … from the theme.

Config under `pie`: `legendPosition` (`right` `left` `top` `bottom` `center`), `textPosition`, `donutHole`, `highlightSlice`. Each slice is its own 70 %-opacity element, as in Mermaid.

**Not yet:** label wrapping.

## XY chart

Keyword: `xychart-beta` / `xychart` (+ `horizontal`).

`title` · `x-axis [categories]` or `x-axis "title" min --> max` · `y-axis "title" min --> max` · `bar [..]` / `line [..]` with optional series names (legend). Band and linear scales, d3 tick generation, Mermaid's orchestrator layout (reserved plot space, title, axes, legend), bar widths, data labels (`showDataLabel`, `showDataLabelOutsideBar`), `chartOrientation`, per-axis options (`showLabel`, `labelRotation`, `tickLength`, …) and `themeVariables.xyChart` (`plotColorPalette`, axis/title colours). Multiple bar series overlap, as in Mermaid.

**Not yet:** markdown strings in titles and labels.

## Timeline

Keyword: `timeline` (`LR`; `TD` is accepted but drawn as LR).

`title` · `section` · `period : event : event` and continuation lines `: event` · `<br>` line breaks. Layout from Mermaid's renderer: 150 px nodes at a 200 px pitch, sections above, events stacked below dashed arrows, axis with arrowhead; colours from `cScale*`/`cScaleLabel*`/`cScaleInv*`, events brightened 20 %.

**Not yet:** vertical (`TD`) layout, `disableMulticolor`, icons, markdown text.

## Quadrant chart

Keyword: `quadrantChart`.

`title` · `x-axis left --> right` · `y-axis bottom --> top` (a lone label names one end) · `quadrant-1…4 text` · points `Name: [x, y]` (0–1) with inline `radius`, `color`, `stroke-color`, `stroke-width` · `classDef` + `Name:::class: [x, y]` · `quadrantChart` config (`chartWidth`, `chartHeight`, `pointRadius`, `xAxisPosition`, `yAxisPosition`, paddings, font sizes, border widths). Points are painted in Mermaid's order (last-written first).

**Not yet:** markdown strings.

## User journey

Keyword: `journey`.

`title` · `section` · `Task: score: Actor, Actor` (score 1–5). Faces (smile / neutral / sad) at score height on dashed lines, actor legend and dots, section headers, journey axis with arrowhead; fills from `fillType0…6`.

Built from Mermaid's own renderer (`journeyRenderer.ts`, `svgDraw.js`, `styles.js`): legend wrapping at `maxLabelWidth`, `leftMargin = config + widest legend line`, theme-coloured score lines and axis, and the `journey` config block (`leftMargin`, `maxLabelWidth`, `width`, `height`, `taskMargin`, `diagramMarginX/Y`, `actorColours`, `titleColor`).

Colours: saturated section headers with tinted task cards, mood-coloured faces with an emotion curve and score guides, distinct actor colours; `journey.classicColors: true` restores Mermaid's palette.

**Not yet:** `rightAngles`.

## Packet diagram

Keyword: `packet` / `packet-beta`. Grammar from `packet.langium`, row splitting from `parser.ts`.

`start-end: "Label"` · `bit: "Label"` · `+bits: "Label"` · `title`. Fields must be contiguous; fields crossing a 32-bit row boundary continue on the next row. Config under `packet` (`rowHeight`, `bitWidth`, `bitsPerRow`, `showBits`, `bitOrder`, `paddingX/Y`) and `themeVariables.packet.*`.

## Kanban

Keyword: `kanban`. Indentation grammar like mindmap: the first line's indentation is the **column** level, deeper lines are cards. `id[text]`, `[text]`, or plain text; metadata `@{ ticket: …, assigned: …, priority: 'Very High'|'High'|'Low'|'Very Low' }` (priority draws a coloured bar). Layout from `kanbanRenderer.ts`: 200 px columns, 190 px cards, tints from `cScale`.

Look: tinted columns with an accent bar and count badge, soft-shadow cards, ticket pill and assignee avatar footer (`kanban.classicColors: true` restores Mermaid's flat columns).

**Not yet:** ticket links (`ticketBaseUrl` is parsed and ignored), markdown in card text.

## Radar chart

Keyword: `radar-beta`.

`axis id["Label"], …` · `curve id["Label"]{v1, v2, …}` or `{axisId: v, …}` (multi-line allowed) · `title` · options `max`, `min`, `ticks`, `showLegend`, `graticule circle|polygon`. Smooth closed curves (`curveTension`), axis labels anchored by angle, legend at the top right; config under `radar`, colours `themeVariables.radar.*` and `cScale*`.

## Treemap

Keyword: `treemap` / `treemap-beta`.

`"Section"` / `"Leaf": value` rows nested by indentation · `:::class` + `classDef` (`fill`, `stroke`, `stroke-width`, `color`) · `title`. d3 squarified layout (padding, header band, rounding), ordinal colour scales reproduced in Mermaid's call order, adaptive label/value font sizes with truncation. Config under `treemap`: `nodeWidth`, `nodeHeight`, `padding`, `showValues`, `valueFormat`.

**Not yet:** `look`-specific styles.

## Sankey

Keyword: `sankey` / `sankey-beta`.

CSV rows `source,target,value` (quotes and `""` escapes) · config under `sankey`: `width`, `height`, `nodeWidth`, `nodePadding`, `nodeAlignment` (`justify` `left` `right` `center`), `showValues`, `prefix`, `suffix`, `linkColor` (`gradient` `source` `target` or a colour), `labelStyle`, `nodeColors`. Layout is a port of d3-sankey 0.12 (six relaxation iterations with collision resolution).

nimaid additions: automatic canvas height when `height` is not configured, labels drawn above the ribbons on soft pills with de-collision (`labelStyle: auto`, default; `legacy` = Mermaid's placement).

**Not yet:** `mix-blend-mode: multiply` on overlapping ribbons (they are plain translucent).

## Diagram types that are not implemented

Pie, timeline, user journey, quadrant, requirement, C4, sankey, XY chart, block, packet, kanban, architecture, radar, treemap and others. They produce `unsupported diagram type`. New diagram types are added in the main nimaid repository.
