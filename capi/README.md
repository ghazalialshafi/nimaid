# nimaid C API

C bindings for [nimaid](https://github.com/ghazalialshafi/nimaid) — Mermaid diagrams (flowchart, sequence, state, ER, class, Gantt, Git graph, mindmap, **plus pie, XY, timeline, quadrant, journey, packet, kanban, radar, treemap and sankey charts**) to **PNG, GIF, SVG or raw RGBA pixels**, in pure Nim with no external dependencies.

* **One header** (`include/nimaid.h`), stable ABI, plain C99; works from C++, Python, Rust, Go, C#, Zig, …
* **Zero setup:** DejaVu Sans is embedded, so `nimaid_context_new()` already renders. Own fonts and colour emoji are opt-in.
* **Static or shared**, **14 targets** from one `pip install ziglang`: Linux (glibc + musl; x86_64, aarch64, armv7, x86, riscv64), Windows (x86_64, aarch64, x86), macOS (x86_64, arm64), FreeBSD.
* Thread-safe (calls are serialised), deterministic, and byte-identical to the nimaid CLI.

```c
#include "nimaid.h"

int main(void) {
  nimaid_context *ctx = nimaid_context_new();
  nimaid_status st = nimaid_render_file(ctx, "flowchart LR\n  A[Hello] --> B[World]", "hello.png", NULL);
  nimaid_context_free(ctx);
  return st != NIMAID_OK;
}
```

```sh
cc hello.c -Iinclude lib/libnimaid.a -lm -o hello && ./hello
```

In memory, with options and error handling:

```c
nimaid_options o; nimaid_options_init(&o); o.theme = "dark"; o.scale = 3;
uint8_t *png; size_t n;
if (nimaid_render_png(ctx, mermaid_text, &o, &png, &n) == NIMAID_OK) { /* use png[0..n) */ nimaid_free(png); }
else fprintf(stderr, "%s\n", nimaid_context_error(ctx));
```

## Layout of this folder

| Path | Contents |
|---|---|
| `include/nimaid.h`, `nimaid.hpp` | the C header; header-only C++11 RAII wrapper |
| `src/nimaid_capi.nim` | the C API implementation (Nim, `{.exportc.}`) |
| `build.py` | cross-compiles and packages every target with Zig — [guide](docs/cross-compiling.md) |
| `examples/` | `hello.c` `in_memory.c` `batch.c` `custom_font.c` `nimaid_cli.c` `nimaid.py` |
| `tests/` | `test_capi.c`, `test_cpp.cpp` (run by `build.py` on the host platform) |
| `docs/` | getting started, tutorials 1–8, C API reference, FAQ — start at [docs/README.md](docs/README.md) |

## Build

```sh
pip install ziglang                    # + Nim >= 2.0
python3 capi/build.py                  # all targets -> capi/dist/nimaid-capi-<version>-<target>.(tar.gz|zip)
python3 capi/build.py -t native        # this machine only, with tests
```

## Changes to the nimaid library itself

The C API needed three small, backward-compatible additions to `src/` (all existing Nim APIs are unchanged):
`initTextMetricsData` (text font from memory), `loadEmojiFontData` / `unloadEmojiFont` (emoji font from memory, and off again),
and `buildMermaidSceneLoaded` (build a scene when fonts are already loaded, so contexts do not reload font files on every render).

## Licenses

MIT, like nimaid. The shared/static libraries embed **DejaVu Sans** (DejaVu Fonts License — a Bitstream Vera derivative that permits
embedding and redistribution; see `THIRD_PARTY.md`). Build with `--nim-arg=-d:nimaidNoEmbeddedFont` to leave it out.
The optional `nimaid-fonts` archive contains Noto Color Emoji (SIL OFL 1.1, license text included).
