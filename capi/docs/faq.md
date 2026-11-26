# FAQ and troubleshooting

## Installation and running

### `undefined reference to 'nimaid_…'` / linker errors
Link the library after your sources: `cc app.c -Llib -lnimaid -lm`. A **static** `libnimaid.a` on Linux/BSD needs `-lm`; the shared library needs nothing. With CMake use `find_package(nimaid)` ([guide](getting-started.md#cmake)).

### `nimaid.dll` not found at run time (Windows)
Put `nimaid.dll` next to your `.exe` (or on `PATH`). When linking dynamically define `NIMAID_SHARED` before including `nimaid.h`.

### `error while loading shared libraries: libnimaid.so`
Add an rpath (`-Wl,-rpath,'$ORIGIN/../lib'`) or set `LD_LIBRARY_PATH` (macOS: `DYLD_LIBRARY_PATH`; the dylib uses `@rpath`).

### `nimaid_context_set_font_file` returns `NIMAID_ERR_FONT`
The path is wrong or unreadable. Use `nimaid_context_error(ctx)` for the message. (Without any call, the embedded DejaVu Sans is used and no font file is needed.)

### The font loads but nothing changes / `cannot load font` for an `.otf`
Only TrueType outlines (`glyf`) are supported. CFF-flavoured `.otf` files and `.ttc` collections are rejected — use a `.ttf`.

### `nimaid: x.mmd: unsupported diagram type`
The first keyword isn't one of: `flowchart`/`graph`, `sequenceDiagram`, `stateDiagram`, `erDiagram`, `classDiagram`, `gantt`, `gitGraph`, `mindmap`, `pie`, `xychart-beta`, `timeline`, `quadrantChart`, `journey`, `packet`, `kanban`, `radar-beta`, `treemap`, `sankey-beta`. Requirement, C4, block and other types aren't implemented. Make sure nothing precedes the keyword except comments, front matter or an `%%{init}%%` directive.

### `Parse error: expecting node id, got tGraph` (or `got tNodeString`, `expecting space`)
A node **id** starts with a Mermaid keyword — `graph…`, `class…`, `style…`, `subgraph…`, or is the bare word `end`. Mermaid itself rejects these. Rename the id (`graphics` → `gfx`); the *label* in brackets is unrestricted.

### `output file must end in .png, .gif or .svg`
The extension decides the format; rename the output file.

## Output looks wrong

### Characters are missing (blank where a letter should be)
The font has no glyph for them and nimaid skips unmapped characters. The embedded DejaVu Sans lacks CJK and many scripts. Use `--font=` with a TrueType font that covers your text (e.g. a CJK font; Japanese was verified).

### Emoji don't show
Emoji are opt-in: pass `--emoji=fonts/NotoColorEmoji-Regular.ttf` (C: `nimaid_context_set_emoji_font_file`). Get the font from the `nimaid-fonts-<version>.tar.gz` release asset. It must be the *OpenType-SVG* flavour of Noto Color Emoji.

### Text in my SVG looks different from the PNG
You used `--svg-text=text`: the viewer substitutes a different font. Use the default outlined mode for identical rendering everywhere, or install DejaVu Sans / keep the font-family list.

### Text overflows boxes in the live-text SVG
It shouldn't: each line has `textLength`. Some editors ignore `textLength`; switch to the default outlined mode.

### The PNG is too big
Use `--scale=1`, or `--colors=64` (palette). For the web prefer SVG.

### The colours of my `themeVariables` are ignored
Use hex (`#ffe08a`), `rgb(…)`, `hsl(…)` or a CSS colour name (`tomato`); anything else is ignored. Also remember: with `theme: base` the variables apply to the base palette. And a `--theme=` on the command line wins over the theme in the diagram (variables still apply).

### My pie / XY / timeline / quadrant / journey ignores `primaryColor`
Those charts use Mermaid's finished theme tables, and derived colours are not recomputed from a base colour. Set the chart's own variables instead (`pie1`, `quadrant1Fill`, `cScale0`, `fillType0`, `themeVariables: {xyChart: {plotColorPalette: …}}`) — see [Tutorial 9](tutorials/09-charts.md#colouring-the-charts).

### My sankey is a tangle of hairlines
That happens in Mermaid itself when many nodes share a column in the fixed 600×400 canvas. nimaid grows the height automatically unless you set `sankey.height` — remove a fixed `height`, or increase it, or set `showValues: false` to reduce the per-node padding.

### `Packet block … is not contiguous`
Packet fields must cover every bit in order — write `108: "x"` for every bit you don't name, or use `+n:` relative widths.

### Parse error: `expecting a quoted label` (pie)
Pie labels must be quoted: `"Dogs" : 386`. Values must be numbers ≥ 0.

### The XY chart's y-axis doesn't start at zero
Mermaid's automatic y-axis spans your data's minimum to maximum. Write `y-axis "Title" 0 --> 100` for a fixed range.

### Layout differs from mermaid.js
Flowchart layout is validated against Mermaid's dagre driver and matches in all but rare cases, but **mindmaps** (balanced tree instead of force layout) and **Git graph** commit labels intentionally differ. Try `--dagre=legacy` (default, matches Mermaid) vs `--dagre=modern`.

### GIF has no transparency / palette PNG edges look jagged on transparent backgrounds
Palette modes use binary transparency (alpha < 128 → transparent). Use truecolour PNG or SVG for translucent backgrounds.

## Library questions

### Can I render from several threads?
Yes, but not in parallel: every call takes one internal lock, because the engine has global state (font registry, caches). For parallel throughput use one process per worker. Do not free a context while another thread is using it.

### How do I get the image without writing a file?
`nimaid_render_png` / `_gif` / `_svg` return a buffer; `nimaid_render_rgba` returns raw pixels. Free everything with `nimaid_free`. See [Tutorial 7](tutorials/07-c-library.md).

### Why `nimaid_free` and not `free`?
On Windows the DLL and your program can use different C runtimes; memory must be released by the side that allocated it.

### How do I use a custom theme from code?
Prepend `%%{init: {'theme':'base','themeVariables':{…}}}%%` to the Mermaid text.

### How do I keep the binary small / skip the embedded font?
Build with `python3 capi/build.py --nim-arg=-d:nimaidNoEmbeddedFont` (saves ~0.75 MB) and call `nimaid_context_set_font_file` yourself.

## What is not supported

* **Diagram types:** requirement, C4, block, architecture, treeView, venn, ishikawa and the newest Mermaid additions.
* **Flowchart:** `@{ view: collapsed }`, icons/images (drawn as plain boxes), clickable links/tooltips (parsed only), `look: handDrawn`, rich HTML labels, KaTeX.
* **Text:** one font at a time, no bold/italic runs (markdown markers are stripped), no complex-script shaping or ligatures (kerning only).
* **Formats:** animated GIF, JPEG, WebP, PDF.
* **SVG pictures:** filters, masks, clip-paths, patterns, `<image>`, `<text>`.

Per-diagram detail: [diagram syntax reference](reference/diagram-syntax.md).

## Still stuck?

Run `bin/nimaid --help`, reproduce with the smallest possible `.mmd`, and open an issue with the diagram text, the command and the message.
