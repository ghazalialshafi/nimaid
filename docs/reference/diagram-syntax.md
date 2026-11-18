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

## Diagram types that are not implemented

Pie, timeline, user journey, quadrant, requirement, C4, sankey, XY chart, block, packet, kanban, architecture, radar, treemap and others. They produce `unsupported diagram type`. See [Adding a diagram type](../extending.md) if you want to contribute one.
