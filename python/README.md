# nimaid

**Mermaid diagrams to PNG, GIF, SVG or raw pixels — from Python, with no dependencies.**
No browser, no Node.js, no Cairo, no system fonts. The renderer is [nimaid](https://github.com/ghazalialshafi/nimaid) (pure Nim),
shipped as a small native library inside the wheel. DejaVu Sans is built in, so it works the moment it is installed.

```sh
pip install nimaid              # add colour emoji:  pip install "nimaid[emoji]"
```

```python
import nimaid

png = nimaid.png("flowchart LR\n  A[Hello] --> B[World]")          # bytes
open("hello.png", "wb").write(png)

svg = nimaid.svg("sequenceDiagram\n  Alice->>Bob: Hi", theme="dark")   # str (outlined glyphs: looks identical everywhere)
nimaid.render_file("gantt\n title Plan\n dateFormat YYYY-MM-DD\n section A\n T :a, 2025-01-01, 5d", "plan.svg")
```

Supported: flowchart/graph, sequenceDiagram, stateDiagram(-v2), erDiagram, classDiagram, gantt, gitGraph, mindmap, pie, xychart-beta, timeline, quadrantChart, journey, packet, kanban, radar-beta, treemap-beta, sankey-beta
([syntax reference](https://github.com/ghazalialshafi/nimaid/blob/main/capi/docs/reference/diagram-syntax.md)).

## API

| | |
|---|---|
| `nimaid.png(text, *, scale=2.0, theme=None, colors=0)` | PNG `bytes`. `colors=2..256` → smaller palette PNG |
| `nimaid.gif(text, *, scale=2.0, theme=None, colors=0)` | GIF `bytes` |
| `nimaid.svg(text, *, theme=None, live_text=False)` | SVG `str` (`live_text=True` keeps selectable `<text>`) |
| `nimaid.rgba(text, *, scale=2.0, theme=None)` | `Image(width, height, data)` straight-alpha RGBA8; `.to_pil()` if Pillow is installed |
| `nimaid.render_file(text, path, **opts)` | writes `.png` / `.gif` / `.svg` by extension |
| `nimaid.encode_png / encode_gif(pixels, w, h, colors=0)` | encode pixels you already have |
| `nimaid.Context(font=None, emoji="auto")` | reusable context with your own fonts (see below) |
| `nimaid.Diagram(text, theme=None)` | shows itself in Jupyter; `.png() .svg() .save(path)` |
| `nimaid.detect_type(text)`, `nimaid.themes()` | `"flowchart"` … / `['default','dark','forest','neutral','base']` |

Themes: `default dark forest neutral base`, or per diagram with `%%{init: {'theme':'base','themeVariables':{'primaryColor':'#ffe08a'}}}%%`.

### Errors

Everything derives from `nimaid.NimaidError`: `ParseError` and `UnsupportedDiagramError` (both also `ValueError`; the message says what and where),
`FontError`, `InvalidArgumentError` (`ValueError`), `RenderIOError` (`OSError`), `InternalError`.

```python
try:
    nimaid.png("flowchart LR\n A --> ")
except nimaid.ParseError as e:
    print(e)          # Parse error: expecting node id, got tEof
```

### Fonts and emoji

```python
ctx = nimaid.Context(font="MyFont.ttf")           # TrueType (glyf) path or bytes; default is the embedded DejaVu Sans
ctx.png(text)
ctx = nimaid.Context(emoji="NotoColorEmoji-Regular.ttf")   # or emoji=False to switch emoji off
```

`pip install "nimaid[emoji]"` installs [`nimaid-noto-emoji`](https://pypi.org/project/nimaid-noto-emoji/) (Noto Color Emoji, OFL-1.1). With the default `emoji="auto"` it is used
automatically — loaded lazily the first time a diagram contains emoji. Reuse one `Context` for many renders: fonts are parsed once.

### Notebooks

```python
nimaid.Diagram("flowchart LR\n A --> B", theme="forest")     # as the last expression of a cell: shows the SVG
```

### Command line

```sh
nimaid --theme=dark --scale=3 diagram.mmd diagram.png        # also: python -m nimaid …;  nimaid --help
```

## Notes

* **Thread-safe, not parallel:** calls are serialised by a lock inside the library; use processes for parallel throughput.
* **Deterministic:** same input → byte-identical output (identical to the native nimaid CLI).
* **Wheels** are provided for Linux (glibc ≥ 2.17 and musl; x86_64, aarch64, armv7, i686), macOS 11+ (Intel, Apple Silicon) and Windows (x64, ARM64, x86).
  Any Python ≥ 3.8 (the library is loaded with `ctypes`, so there is no per-Python-version build).
* Set `NIMAID_LIB=/path/to/libnimaid.so` to use another build of the native library.

## License

MIT. The native library embeds DejaVu Sans (DejaVu Fonts License, permits embedding/redistribution); `nimaid-noto-emoji` ships Noto Color Emoji (SIL OFL 1.1).
See `THIRD_PARTY.md` in the wheel's `.dist-info`. Source and C API: <https://github.com/ghazalialshafi/nimaid>.
