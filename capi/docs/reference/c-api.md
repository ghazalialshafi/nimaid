# C API reference (`#include <nimaid.h>`)

Everything below is declared in `include/nimaid.h`. The API is plain C99, has a stable ABI (`NIMAID_ABI_VERSION`), and works unchanged from C++, Python (`ctypes`), Rust, Go, C#, Zig, Swift, …

* Every function that can fail returns a **`nimaid_status`** (`NIMAID_OK` = 0). The message of the last failure is `nimaid_context_error(ctx)`.
* Memory returned through `out_…` parameters belongs to you: release it with **`nimaid_free`**. On failure those outputs are set to `NULL` / 0.
* Strings are NUL-terminated UTF-8. Buffers you pass in (fonts, pixels) are **copied**; you can free yours immediately.
* Calls are serialised by an internal lock (safe from several threads, not parallel). See [Concurrency](#concurrency).

## Status codes

| Code | Value | Meaning | Typical cause |
|---|---|---|---|
| `NIMAID_OK` | 0 | success | |
| `NIMAID_ERR_INVALID_ARGUMENT` | 1 | bad argument | `NULL` pointer, `scale <= 0`, `colors` outside `0` / `2..256` |
| `NIMAID_ERR_FONT` | 2 | font problem | unreadable file, not a TrueType (`glyf`) font, bad emoji font |
| `NIMAID_ERR_PARSE` | 3 | Mermaid syntax error | the message says what and where |
| `NIMAID_ERR_UNSUPPORTED` | 4 | diagram type not supported | `pie`, `timeline`, … see [diagram syntax](diagram-syntax.md) |
| `NIMAID_ERR_IO` | 5 | cannot write the output file | missing folder, permissions |
| `NIMAID_ERR_OOM` | 6 | out of memory | |
| `NIMAID_ERR_INTERNAL` | 7 | library bug | please report with the diagram text |

`const char *nimaid_status_string(int status)` returns a static, human-readable name for a code.

## Context and fonts

```c
typedef struct nimaid_context nimaid_context;

nimaid_context *nimaid_context_new(void);
void            nimaid_context_free(nimaid_context *ctx);
const char     *nimaid_context_error(const nimaid_context *ctx);
```

A context owns the fonts. **A fresh context already works**: it uses DejaVu Sans, which is compiled into the library, and no emoji font. Create one context and reuse it — fonts are parsed once, not per render. `nimaid_context_new` returns `NULL` only when out of memory; `nimaid_context_free(NULL)` is a no-op.
`nimaid_context_error` returns `""` after a successful call; the pointer stays valid until the next call on that context.

```c
nimaid_status nimaid_context_set_font_file(nimaid_context *ctx, const char *path);
nimaid_status nimaid_context_set_font_data(nimaid_context *ctx, const void *data, size_t size);
nimaid_status nimaid_context_set_emoji_font_file(nimaid_context *ctx, const char *path);
nimaid_status nimaid_context_set_emoji_font_data(nimaid_context *ctx, const void *data, size_t size);
```

| Function | Notes |
|---|---|
| `set_font_file` / `set_font_data` | Text font, **TrueType with `glyf` outlines** (`.ttf`; not CFF `.otf` or `.ttc`). `set_font_data(ctx, NULL, 0)` restores the embedded font. A broken font is reported by the next render (`NIMAID_ERR_FONT`); an unreadable file by `set_font_file` itself. |
| `set_emoji_font_file` / `_data` | Noto Color Emoji, *OpenType-SVG* flavour. `NULL` / size 0 turns emoji off (the default). The file variant reads the file on the first render that needs it. |

Without an emoji font, emoji are skipped; everything else renders normally. The emoji font is 24 MB, which is why it is not embedded: get it from the `nimaid-fonts-<version>.tar.gz` release asset or the repository's `fonts/` folder.

## Options

```c
typedef struct nimaid_options {
  size_t      struct_size;   /* set by nimaid_options_init */
  double      scale;         /* PNG/GIF pixel scale, 2.0 = retina. Ignored for SVG. > 0. Default 2.0 */
  const char *theme;         /* "default" "dark" "forest" "neutral" "base"; NULL or "" = from the diagram */
  int         colors;        /* 0 = truecolour PNG / 256-colour GIF; 2..256 = palette size. Default 0 */
  int         svg_text;      /* SVG only: 1 = live <text>, 0 = outlined glyphs. Default 0 */
  int         legacy_dagre;  /* 1 = Mermaid-compatible layout ordering (default), 0 = dagre_nim defaults */
} nimaid_options;

nimaid_options o;  nimaid_options_init(&o);      /* or: nimaid_options o = NIMAID_OPTIONS_DEFAULT; */
```

Always initialise with `nimaid_options_init`; then change only what you need. `struct_size` lets a newer library accept structs built against an older header (missing fields take their defaults), so new options never break your binary. **Passing `NULL` instead of a pointer means "all defaults".**
The `theme` string is only read during the call; it may point to a temporary. Unknown theme names fall back to `default`.
The meaning of every field is the same as the CLI options in [Tutorial 6](../tutorials/06-output-formats.md) and the [themes reference](themes.md).

## Rendering

All five take the Mermaid text (UTF-8, front matter and `%%{init}%%` are honoured) and optional `opts`.

```c
nimaid_status nimaid_render_png (nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                 uint8_t **out_buf, size_t *out_size);
nimaid_status nimaid_render_gif (…same…);
nimaid_status nimaid_render_svg (nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                 char **out_str, size_t *out_size /* optional, may be NULL */);
nimaid_status nimaid_render_rgba(nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                 nimaid_image *out_image);
nimaid_status nimaid_render_file(nimaid_context *ctx, const char *mermaid, const char *output_path,
                                 const nimaid_options *opts);
```

| Function | Result |
|---|---|
| `nimaid_render_png` | PNG bytes (`out_size` bytes). `opts->colors` = 2..256 gives a palette PNG. |
| `nimaid_render_gif` | GIF89a bytes (still image). `colors` defaults to 256. |
| `nimaid_render_svg` | A complete SVG document, **NUL-terminated**; `*out_size` (if given) excludes the NUL. Always scale 1. `svg_text` selects live text vs outlined glyphs. |
| `nimaid_render_rgba` | `nimaid_image { int width, height; uint8_t *pixels; }`: straight-alpha RGBA8, row-major, `width*height*4` bytes. Free `pixels` with `nimaid_free`. |
| `nimaid_render_file` | Writes `output_path`; the format comes from the extension: `.svg`, `.gif`, anything else is PNG (the same rule as the CLI). |

## Encoders for your own pixels

```c
nimaid_status nimaid_encode_png(const void *rgba, int width, int height, int colors, uint8_t **out_buf, size_t *out_size);
nimaid_status nimaid_encode_gif(…same…);
```

`rgba` is straight-alpha RGBA8, `width*height*4` bytes. `colors`: `0` truecolour (PNG) or `2..256`. Both encoders are dependency-free and need no context. Handy to re-encode an image from `nimaid_render_rgba` at several palette sizes without re-rendering.

## Information

```c
int         nimaid_abi_version(void);          /* compare with NIMAID_ABI_VERSION from the header you compiled against */
const char *nimaid_version(void);              /* "0.6.1"; the header also has NIMAID_VERSION_MAJOR/MINOR/PATCH/STRING */
int         nimaid_has_embedded_font(void);    /* 1 unless built with -d:nimaidNoEmbeddedFont */
int         nimaid_theme_count(void);          /* 5 */
const char *nimaid_theme_name(int index);      /* "default" "dark" "forest" "neutral" "base"; NULL if out of range */
const char *nimaid_detect_type(const char *text);
```

`nimaid_detect_type` returns one of `"flowchart" "sequence" "state" "er" "class" "gantt" "gitgraph" "mindmap" "pie" "xychart" "timeline" "quadrant" "journey" "packet" "kanban" "radar" "treemap" "sankey" "unknown"` (never `NULL`, static string).

A defensive start-up check: `assert(nimaid_abi_version() == NIMAID_ABI_VERSION);`

## Memory

`void nimaid_free(void *p)` releases anything returned by the library (`out_buf`, `out_str`, `image.pixels`); `NULL` is fine. `void *nimaid_alloc(size_t n)` returns memory that `nimaid_free` can release; it exists for hosts that must write input into the library's own memory (WebAssembly) — C programs can simply use `malloc`. Do **not** use `free()`: on Windows the DLL and your program may use different C runtimes.

## Concurrency

The engine keeps a global font registry and caches. The C API therefore takes **one process-wide lock per call**: calls from several threads are safe, but they run one after another. Consequences:

* Several contexts may be used from several threads at once; switching between contexts reloads that context's fonts on demand (cheap for the text font, a one-off parse for the 24 MB emoji font).
* Do not free a context while another thread is still inside a call that uses it.
* For parallel throughput, run one process per worker.
* Rendering is deterministic: the same input gives byte-identical output on every run and, for a given target, every machine.

## Linking

| Platform | Static | Shared |
|---|---|---|
| Linux / FreeBSD | `cc app.c -Iinclude lib/libnimaid.a -lm` | `cc app.c -Iinclude -Llib -lnimaid` |
| macOS | `cc app.c -Iinclude lib/libnimaid.a` | `cc app.c -Iinclude -Llib -lnimaid -Wl,-rpath,@executable_path/../lib` |
| Windows (MinGW / zig) | `cc app.c -Iinclude lib/libnimaid.a` | `cc -DNIMAID_SHARED app.c -Iinclude lib/nimaid.lib`, ship `bin/nimaid.dll` |
| Windows (MSVC) | use the DLL | `cl /DNIMAID_SHARED app.c /I include lib\nimaid.lib`, ship `bin\nimaid.dll` |

More in [Getting started](../getting-started.md#link-it-into-your-program).
