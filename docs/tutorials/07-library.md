# Tutorial 7 — Using nimaid as a Nim library

**You will learn:** how to render from your own program: to a file, to memory, in batch, and with custom themes.
**Source files:** `docs/examples/hello.nim`, `in_memory.nim`, `batch.nim` — all compiled and run as part of writing these docs.

## Setup

Nimaid is a normal Nim module. The simplest way is to build **inside the repository**, whose `nim.cfg` sets the search paths:

```sh
nim c -r docs/examples/hello.nim
```

From another project, add the paths yourself:

```sh
nim c --path:/path/to/nimaid/src --path:/path/to/nimaid/dagre_nim/src myprog.nim
```

or declare it in your `.nimble` file and let nimble resolve it. Either way, `import nimaid` brings in the public API.

Fonts are passed as file paths — keep `DejaVuSans.ttf` (and `NotoColorEmoji-Regular.ttf` for emoji) where your program can find them.

## 1. Hello, file

```nim
import nimaid

renderMermaidToFile(
  "flowchart LR\n  A[Hello] --> B[World]",
  "hello.png",
  "fonts/DejaVuSans.ttf",
  emojiFontPath = "fonts/NotoColorEmoji-Regular.ttf")
```

`renderMermaidToFile(text, outputPath, fontPath, scale = 2.0, emojiFontPath = "", themeName = "", colors = 0, svgText = false)`
picks the format from the extension of `outputPath` (`.png`, `.gif`, `.svg`). It raises `IOError` if a font cannot be loaded and `ValueError`/`ParseError` for unsupported or invalid diagrams.

## 2. In memory

```nim
import nimaid

let chart = "flowchart TD\n A[Request] --> B{Cached?}\n B -->|yes| C[Serve]\n B -->|no| D[Compute] --> C"
const font = "fonts/DejaVuSans.ttf"

let img = renderMermaidToImage(chart, font, scale = 2.0)   # RenderedImage
echo img.width, "x", img.height                            # 464x910
# img.rgba: seq[byte], straight-alpha RGBA8, row-major, len = width*height*4

let png   = encodePng(img.rgba, img.width, img.height)           # seq[byte]
let small = encodePng(img.rgba, img.width, img.height, colors = 64)
let gif   = encodeGif(img.rgba, img.width, img.height)
let svg   = renderMermaidToSvg(chart, font, themeName = "forest") # string
```

Run output of `docs/examples/in_memory.nim`:

```
pixels: 464x910 (1688960 bytes)
png: 33750 bytes
palette png: 16921 bytes
svg: 9352 chars, starts with: <svg xmlns="http://www.w3.org/2000/svg"
```

Use the byte sequences directly — send them over HTTP, put them in a database, embed them in a PDF generator, upload them to object storage.

## 3. Themes and styling from code

`themeName` takes `default | dark | forest | neutral | base`. For anything finer-grained, prepend an init directive to the text:

```nim
let styled = "%%{init: {'theme':'base','themeVariables':{'primaryColor':'#ffe08a','lineColor':'#6b4f00'}}}%%\n" & chart
renderMermaidToFile(styled, "styled.png", font)
```

Or build everything from a template and fill in data:

```nim
import std/strformat
proc pipeline(stages: seq[string]): string =
  result = "flowchart LR\n"
  for i, s in stages:
    result.add &"    S{i}[\"{s}\"]"
    if i > 0: result.add &"\n    S{i-1} --> S{i}"
    result.add "\n"
renderMermaidToFile(pipeline(@["Fetch", "Parse", "Render"]), "pipeline.svg", font)
```

## 4. Batch conversion with error handling

```nim
import std/[os, strformat]
import nimaid

for path in walkFiles("examples" / "*.mmd"):
  let name = splitFile(path).name
  try:
    renderMermaidToFile(readFile(path), "out" / (name & ".svg"), "fonts/DejaVuSans.ttf",
                        emojiFontPath = "fonts/NotoColorEmoji-Regular.ttf", themeName = "neutral")
    echo &"ok    {name}"
  except CatchableError as e:
    echo &"FAIL  {name}: {e.msg}"
```

(`docs/examples/batch.nim` does exactly this for PNG and SVG; run it with `nim c -r docs/examples/batch.nim`. Create the `out/` folder first.)

## 5. Step by step (advanced)

When you need the intermediate results (for example to measure a diagram before drawing), the stages are public:

```nim
import nimaid
from nimaid/purevg import pvg_engine_init, pvg_engine_term   # qualified: `nimaid` also exports the scene-recording pvg_* names

discard pvg_engine_init(0)
discard initTextMetrics("fonts/DejaVuSans.ttf")      # BEFORE layout: text sizes drive node sizes
let layout = parseAndLayoutFlowchart(readFile("a.mmd"))
let img = renderToImage(layout, defaultTheme(), margin = 16, scale = 2)
writePng("a.png", img.rgba, img.width, img.height)
discard pvg_engine_term()
```

`themeByName("dark")`, `defaultTheme()` and `FlowTheme` (a plain object of colours, font size, stroke width) are exported; copy and modify fields to restyle programmatically.
Full signatures are in the [library API reference](../reference/library-api.md).

## Notes for application authors

* **Not thread-safe.** The engine keeps a global font registry and caches. Render from one thread at a time (or one process per worker).
* **Cheap to call repeatedly.** Fonts are parsed once and cached. Measured in one process on a single core: ~2.6 ms per SVG render and ~37 ms per RGBA render of the 7-node `basic` example.
* **Deterministic.** The same input always yields byte-identical pixels and SVG text (verified).
* **No global state to clean up** beyond `pvg_engine_term()`, which the high-level `render*` functions already call for you.

## Next

[Tutorial 8 — drawing with the PureVG engine](08-purevg-engine.md)
