# Themes reference

## Built-in themes

`default` · `dark` · `forest` · `neutral` · `base`

Colours are Mermaid's own, evaluated from its theme source (`theme-*.js`) and stored as presets. `base` is the plain canvas meant to be customised.

| Theme | Character |
|---|---|
| `default` | light lavender nodes, yellow clusters |
| `dark` | dark background, light lines and text |
| `forest` | greens |
| `neutral` | greys, print-friendly |
| `base` | neutral starting point for `themeVariables` |

## Choosing a theme (in order of precedence)

1. **Command line / API:** `--theme=dark`, `themeName = "dark"` — always wins.
2. **In the diagram:** `%%{init: {'theme': 'forest'}}%%` or front matter `config: { theme: dark }`.
3. Otherwise `default`.

`themeVariables` from the diagram are applied **on top of** whichever theme was chosen, even when the theme itself came from the command line.

## `themeVariables`

```
%%{init: {'theme': 'base', 'themeVariables': {'primaryColor': '#ffe08a', 'lineColor': '#6b4f00'}}}%%
```

or

```
---
config:
  theme: base
  themeVariables:
    primaryColor: "#ffe08a"
---
```

Values are hex (`#rgb`, `#rrggbb`) or `rgb()` colours. CSS colour *names* are not accepted here (they are in `classDef`/`style`).

### Flowchart, state, ER, class, general

| Variable | Controls |
|---|---|
| `background` | canvas background |
| `mainBkg`, `primaryColor` | node fill |
| `primaryBorderColor`, `nodeBorder` | node border |
| `primaryTextColor`, `nodeTextColor` | node text |
| `clusterBkg`, `tertiaryColor` | subgraph fill |
| `clusterBorder` | subgraph border |
| `lineColor` | edge lines |
| `arrowheadColor` | arrowheads |
| `textColor` | general text |
| `titleColor` | diagram title |
| `edgeLabelBackground` | background of edge labels |
| `fontSize`, `fontFamily` | text size / family name |

### Sequence diagram

`actorBkg` `actorBorder` `actorTextColor` `actorLineColor` `signalColor` `signalTextColor` `noteBkgColor` `noteBorderColor` `noteTextColor` `labelBoxBkgColor` `labelBoxBorderColor` `loopTextColor` `activationBkgColor` `activationBorderColor` `sequenceNumberColor`

## Variables of the chart diagrams

Pie, XY chart, timeline, quadrant, journey, packet, radar, kanban and treemap read Mermaid's *finished* theme tables (all five themes, every variable). Set the variable you want directly:

| Chart | Variables |
|---|---|
| Pie | `pie1…pie12`, `pieTitleTextColor`, `pieSectionTextColor`, `pieLegendTextColor`, `pieStrokeColor`, `pieStrokeWidth`, `pieOuterStrokeColor`, `pieOuterStrokeWidth`, `pieOpacity`, `pieTitleTextSize`, `pieSectionTextSize`, `pieLegendTextSize` |
| XY chart | nested `xyChart: { backgroundColor, titleColor, plotColorPalette, dataLabelColor, legendTextColor, xAxisLabelColor, xAxisTitleColor, xAxisTickColor, xAxisLineColor, yAxis… }` (also settable in front matter) |
| Timeline | `cScale0…11`, `cScaleLabel0…11`, `cScaleInv0…11`, `textColor` |
| Quadrant | `quadrant1Fill…quadrant4Fill`, `quadrant1TextFill…`, `quadrantPointFill`, `quadrantPointTextFill`, `quadrantTitleFill`, `quadrantXAxisTextFill`, `quadrantYAxisTextFill`, `quadrantInternalBorderStrokeFill`, `quadrantExternalBorderStrokeFill` |
| Journey | `fillType0…7`, `textColor`, `titleColor` |
| Packet | nested `packet: { blockFillColor, blockStrokeColor, blockStrokeWidth, labelColor, startByteColor, endByteColor, titleColor }` |
| Radar | nested `radar: { axisColor, axisStrokeWidth, graticuleColor, graticuleOpacity, graticuleStrokeWidth, curveOpacity, curveStrokeWidth }` |
| Kanban, treemap | `cScale0…11`, `cScaleLabel0…`, `cScalePeer0…`, `background`, `nodeBorder` |

Derived colours are **not** recomputed: changing `primaryColor` recolours flowchart-family diagrams but not these charts. See [Tutorial 9](../tutorials/09-charts.md#colouring-the-charts).

## From Nim

```nim
import nimaid

let th = themeByName("dark")                 # FlowTheme (plain object of colours + sizes)
var custom = themeByName("base")
custom.nodeBkg = rgba(255, 224, 138)         # edit any field
custom.lineColor = rgba(107, 79, 0)
```

`themeFor(text, forced = "")` applies the precedence rules above to a Mermaid text and returns the resulting `FlowTheme`.
To feed a custom theme into `render*`, express it as an `%%{init}%%` directive prepended to the text (see [Tutorial 7](../tutorials/07-library.md)).

`FlowTheme` fields: `background nodeBkg nodeBorder clusterBkg clusterBorder lineColor arrowheadColor textColor titleColor edgeLabelBkg fontFamily fontSize radius strokeWidth nodeText noteBkg noteBorder noteText actorBkg actorBorder actorText actorLine signal signalText labelBoxBkg labelBoxBorder labelText loopText activationBkg activationBorder seqNumber`.

## Regenerating the presets

The preset table was produced from Mermaid's source with `tools/themes/dump.mjs` (needs `npm i khroma`). You only need this if Mermaid changes its theme colours.
