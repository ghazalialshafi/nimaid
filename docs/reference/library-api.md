# Library API reference (`import nimaid`)

All signatures below are exported by `import nimaid`. Examples assume the fonts live at `fonts/…`.
Errors are raised as exceptions: `IOError` (a font cannot be loaded), `ValueError` (unsupported diagram type), and `ParseError` (a `CatchableError`) for syntax errors.

## One-call rendering

### `renderMermaidToFile`

```nim
proc renderMermaidToFile*(text, outputPath, fontPath: string, scale = 2.0, emojiFontPath = "",
                          themeName = "", colors = 0, svgText = false)
```

Renders `text` and writes `outputPath`; the format comes from its extension — `.svg`, `.gif`, otherwise PNG.

| Parameter | Meaning |
|---|---|
| `text` | Mermaid source (UTF-8). Front matter and `%%{init}%%` are honoured. |
| `outputPath` | `.png`, `.gif` or `.svg`. |
| `fontPath` | TrueType (`glyf`) text font. |
| `scale` | Pixel scale for PNG/GIF (ignored for SVG). |
| `emojiFontPath` | Noto Color Emoji font; `""` disables emoji. |
| `themeName` | `default dark forest neutral base`; `""` = take from the diagram. |
| `colors` | `0` truecolour PNG / 256-colour GIF; `2..256` palette size. |
| `svgText` | SVG only: `true` = live `<text>`, `false` = outlined glyphs. |

### `renderMermaidToImage`

```nim
proc renderMermaidToImage*(text, fontPath: string, scale = 2.0, emojiFontPath = "",
                           themeName = ""): RenderedImage

type RenderedImage* = object
  width*, height*: int
  rgba*: seq[byte]        ## straight-alpha RGBA8, row-major, len = width*height*4
```

### `renderMermaidToSvg`

```nim
proc renderMermaidToSvg*(text, fontPath: string, emojiFontPath = "", themeName = "",
                         svgText = false): string
```

Returns a complete SVG document (scale 1).

### `renderFlowchartToPng`

```nim
proc renderFlowchartToPng*(chartText, outputPath: string, fontPath: string,
                           th: FlowTheme = defaultTheme(), scale = 2.0, emojiFontPath = ""): bool
```

Kept for backwards compatibility; returns `false` on `IOError`. The `th` argument is **ignored** — use `renderMermaidToFile(…, themeName = …)` or an `%%{init}%%` directive.

## Encoders

```nim
proc encodePng*(rgba: openArray[byte], width, height: int, colors = 0): seq[byte]
proc writePng*(path: string, rgba: openArray[byte], width, height: int, colors = 0)
proc encodeGif*(rgba: openArray[byte], w, h: int, colors = 256): seq[byte]
proc writeGif*(path: string, rgba: openArray[byte], w, h: int, colors = 256)
```

`colors = 0` (PNG) is truecolour; `2..256` is a palette. Both encoders are dependency-free.

## Themes

```nim
proc themeByName*(name: string): FlowTheme          # unknown names → "default"
proc defaultTheme*(): FlowTheme
proc themeFor*(text: string, forced = ""): FlowTheme  # precedence: forced > diagram > default; themeVariables applied
proc applyOverrides*(theme: var FlowTheme, overrides: Table[string, string])
proc rgba*(r, g, b: uint8, a: uint8 = 255): Color
const themeNames* = ["default", "dark", "forest", "neutral", "base"]
```

`FlowTheme` fields are listed in the [themes reference](themes.md#from-nim).

## Fonts

```nim
proc initTextMetrics*(fontPath: string): bool   # load the text font used for measuring AND drawing
proc loadEmojiFont*(path: string): bool          # load the colour emoji font
```

The `render*` functions call these for you. Call them yourself only when you use the step-by-step API.

## Step-by-step API

```nim
proc parseAndLayoutFlowchart*(chartText: string): LayoutResult
proc renderToImage*(res: LayoutResult, th: FlowTheme = defaultTheme(),
                    margin = 16.0, scale = 2.0): RenderedImage
proc detectDiagramType*(rawText: string): string
```

`detectDiagramType` returns one of `"flowchart" "sequence" "state" "er" "class" "gantt" "gitgraph" "mindmap" "unknown"`.
Initialise the engine first (`pvg_engine_init(0)`, imported with `from nimaid/purevg import pvg_engine_init, pvg_engine_term`) and load fonts **before** layout, because text sizes determine node sizes.

## Scene recording and SVG

```nim
# nimaid/gfx — same pvg_* function names as the engine, but records a scene graph
proc renderRgba*(root: Node, w, h: int): seq[byte]

# nimaid/svg
type SvgTextMode* = enum stPaths, stText
proc toSvg*(root: Node, w, h: int, bg: array[4, uint8],
            fontFamily = "'DejaVu Sans', Verdana, 'Trebuchet MS', Arial, sans-serif",
            textMode = stPaths): string
```

See [Tutorial 8](../tutorials/08-purevg-engine.md#draw-once-export-twice-png-and-svg).

## Global switches

```nim
var useLegacyDagre*: bool   # true (default): Mermaid/dagre-d3-es node ordering; false: dagre_nim defaults
const nimaidVersion*: string
```

## Concurrency

The engine keeps a global font registry and caches. Use one thread (or one process) at a time.
