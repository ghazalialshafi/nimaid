# Tutorial 7 — Using nimaid from C

**You will learn:** how to render from your own program: to a file, to memory, in batch, with custom fonts, and with custom themes.
**Source files:** `examples/hello.c`, `in_memory.c`, `batch.c`, `custom_font.c` — all compiled and run while writing this tutorial.

## Setup

Take the archive for your platform (or [build it](../cross-compiling.md)) and unpack it. You need three things from it: `include/nimaid.h` and one library from `lib/`.

```sh
cc examples/hello.c -Iinclude lib/libnimaid.a -lm -o hello && ./hello      # Linux / BSD
```

There is nothing else to install and no font files are needed: **DejaVu Sans is embedded in the library**. (Per-platform link lines, CMake and pkg-config: [Getting started](../getting-started.md).)

## 1. Hello, file

```c
#include "nimaid.h"
#include <stdio.h>

int main(void) {
  nimaid_context *ctx = nimaid_context_new();
  nimaid_status st = nimaid_render_file(ctx, "flowchart LR\n  A[Hello] --> B[World]", "hello.png", NULL);
  if (st != NIMAID_OK) fprintf(stderr, "nimaid: %s\n", nimaid_context_error(ctx));
  nimaid_context_free(ctx);
  return st != NIMAID_OK;
}
```

`nimaid_render_file(ctx, text, path, opts)` picks the format from the extension of `path` (`.png`, `.gif`, `.svg`). Passing `NULL` for the options means defaults (scale 2, truecolour, theme from the diagram).
Every call returns a `nimaid_status`; on failure `nimaid_context_error(ctx)` says what is wrong, for example a syntax error with its position.

## 2. In memory

```c
nimaid_context *ctx = nimaid_context_new();
nimaid_options opt; nimaid_options_init(&opt);              /* scale 2.0, truecolour */

nimaid_image img;
nimaid_render_rgba(ctx, chart, &opt, &img);                 /* straight-alpha RGBA8, row-major */
printf("pixels: %dx%d\n", img.width, img.height);

uint8_t *png; size_t png_len;
nimaid_encode_png(img.pixels, img.width, img.height, 0, &png, &png_len);   /* encode the pixels you have */
nimaid_free(png); nimaid_free(img.pixels);

opt.colors = 64;                                            /* or render straight to bytes */
nimaid_render_png(ctx, chart, &opt, &png, &png_len);

opt.colors = 0; opt.theme = "forest";
char *svg; size_t svg_len;
nimaid_render_svg(ctx, chart, &opt, &svg, &svg_len);        /* NUL-terminated SVG document */
```

Output of `examples/in_memory.c` (error checking omitted above; the example has it):

```
pixels: 464x910 (1688960 bytes)
png: 33750 bytes
palette png: 16921 bytes
svg: 9352 chars, starts with: <svg xmlns="http://www.w3.org/2000/svg"
```

Use the buffers directly — send them over HTTP, put them in a database, embed them in a PDF generator, upload them to object storage. **Everything the library hands you is released with `nimaid_free`**, never `free`.

## 3. Themes and styling from code

`opt.theme` takes `default | dark | forest | neutral | base` (`nimaid_theme_count()` / `nimaid_theme_name(i)` list them). For anything finer-grained, prepend an init directive to the text:

```c
const char *styled =
  "%%{init: {'theme':'base','themeVariables':{'primaryColor':'#ffe08a','lineColor':'#6b4f00'}}}%%\n"
  "flowchart LR\n  A --> B";
nimaid_render_file(ctx, styled, "styled.png", NULL);
```

Or build the text from your data:

```c
char text[4096]; size_t n = snprintf(text, sizeof text, "flowchart LR\n");
for (int i = 0; i < stages; i++) {
  n += snprintf(text + n, sizeof text - n, "    S%d[\"%s\"]\n", i, names[i]);
  if (i) n += snprintf(text + n, sizeof text - n, "    S%d --> S%d\n", i - 1, i);
}
```

## 4. Batch conversion with error handling

Reuse **one context** for the whole batch: fonts are loaded once.

```c
nimaid_context *ctx = nimaid_context_new();
nimaid_options opt; nimaid_options_init(&opt); opt.theme = "neutral";
for (int i = 2; i < argc; i++) {
  /* read argv[i] into `text`, derive `out` from its name … */
  nimaid_status st = nimaid_render_file(ctx, text, out, &opt);
  if (st == NIMAID_OK) printf("ok    %s\n", name);
  else                 printf("FAIL  %s: %s\n", name, nimaid_context_error(ctx));
}
```

`examples/batch.c` does exactly this (portable, no directory-walking API; your shell expands the glob):

```sh
mkdir -p out && ./batch out docs/examples/*.mmd
```

Distinguish error kinds with the status value: `NIMAID_ERR_PARSE` (user's diagram is wrong), `NIMAID_ERR_UNSUPPORTED` (diagram type not implemented), `NIMAID_ERR_IO` (cannot write), `NIMAID_ERR_FONT`, …

## 5. Your own fonts and emoji

```c
nimaid_context_set_font_file(ctx, "MyFont.ttf");                         /* TrueType, glyf outlines */
nimaid_context_set_emoji_font_file(ctx, "NotoColorEmoji-Regular.ttf");   /* opt-in colour emoji */
```

Or from memory — for fonts that live in a resource, a database or an archive (`examples/custom_font.c`):

```c
nimaid_context_set_font_data(ctx, bytes, size);        /* the bytes are copied: free yours right away */
nimaid_context_set_emoji_font_data(ctx, bytes, size);
nimaid_context_set_font_data(ctx, NULL, 0);            /* back to the embedded DejaVu Sans */
nimaid_context_set_emoji_font_file(ctx, NULL);         /* emoji off */
```

Changing fonts is cheap to do and applies from the next render. Use several contexts if you alternate between font setups.

## 6. Raw pixels into your own pipeline

`nimaid_render_rgba` gives straight-alpha RGBA8: hand it to a texture upload, an image library, a video encoder, a PDF writer. `nimaid_encode_png` / `nimaid_encode_gif` turn pixels you already have (from any source) into bytes with the library's optimising encoders.

## Notes for application authors

* **Thread-safe, not parallel.** Each call takes one process-wide lock (the engine has global state). Several threads may call in; they queue. For parallel throughput use one process per worker.
* **Cheap to call repeatedly.** Fonts are parsed once per context; rendering the 7-node `basic` example takes a few ms for SVG and tens of ms for pixels.
* **Deterministic.** The same input yields byte-identical PNG and SVG on every run (and the C API output is byte-identical to the `nimaid` command-line tool).
* **No global init or shutdown.** The first call initialises the runtime; there is nothing to clean up except contexts and buffers you own.
* **ABI stability.** Check `nimaid_abi_version() == NIMAID_ABI_VERSION` once at start-up if you load the library dynamically.

## Next

[Tutorial 8 — other languages (Python, C++)](08-other-languages.md) · [C API reference](../reference/c-api.md)
