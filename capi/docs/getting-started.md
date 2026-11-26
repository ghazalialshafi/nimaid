# Getting started (C API)

This page takes you from nothing to a rendered diagram from C in about five minutes.

## 1. What you need

| Requirement | Notes |
|---|---|
| The nimaid C package for your platform | `nimaid-capi-<version>-<target>.tar.gz` (`.zip` on Windows), from the releases — or [build it yourself](cross-compiling.md) |
| Any C compiler | `gcc`, `clang`, `zig cc`, MSVC, … |

Nothing else: no browser, no Node.js, no Python, no font files, no system libraries. The finished program depends only on libc (and libm on Linux/BSD).

Unpacked, the package looks like this:

```
include/nimaid.h  nimaid.hpp        the header (and the optional C++ wrapper)
lib/libnimaid.a                      static library        (all platforms)
lib/libnimaid.so | .dylib            shared library        (Linux/BSD | macOS)
bin/nimaid.dll + lib/nimaid.lib      shared library + import library (Windows)
bin/nimaid[.exe]                     the nimaid command-line tool, built on this very C API
lib/pkgconfig/nimaid.pc  lib/cmake/nimaid/   pkg-config and CMake files
examples/  docs/                     C examples, tutorials, reference
```

Which package? Pick the one matching the **machine the program runs on**: `linux-x86_64-gnu` for most Linux PCs/servers, `linux-x86_64-musl` for Alpine or fully static executables, `linux-aarch64-*` for ARM servers and Raspberry Pi 4/5 (64-bit OS), `macos-aarch64` for Apple Silicon, `windows-x86_64` for Windows. `python3 capi/build.py --list` shows all 14.

## 2. Render your first diagram

Create `hello.c` (it is `examples/hello.c`):

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

Compile and run:

```sh
cc hello.c -Iinclude lib/libnimaid.a -lm -o hello     # Linux; other platforms below
./hello
```

Open `hello.png`. You just ran the whole pipeline: parse → layout → draw → encode.

## Link it into your program

| Platform | Static (nothing to ship) | Shared |
|---|---|---|
| **Linux / FreeBSD** | `cc app.c -Iinclude lib/libnimaid.a -lm` | `cc app.c -Iinclude -Llib -lnimaid -Wl,-rpath,'$ORIGIN/../lib'` |
| **macOS** | `cc app.c -Iinclude lib/libnimaid.a` | `cc app.c -Iinclude -Llib -lnimaid -Wl,-rpath,@executable_path/../lib` |
| **Windows (MinGW, zig cc, clang)** | `cc app.c -Iinclude lib/libnimaid.a` | `cc -DNIMAID_SHARED app.c -Iinclude lib/nimaid.lib` + `bin/nimaid.dll` next to the `.exe` |
| **Windows (MSVC)** | — | `cl /DNIMAID_SHARED app.c /I include lib\nimaid.lib` + `bin\nimaid.dll` next to the `.exe` |

### pkg-config

```sh
export PKG_CONFIG_PATH=$PWD/lib/pkgconfig
cc app.c $(pkg-config --cflags --libs nimaid) -o app            # add --static for static linking
```

### CMake

```cmake
cmake_minimum_required(VERSION 3.13)
project(app C)
find_package(nimaid REQUIRED PATHS /path/to/unpacked/package/lib/cmake/nimaid NO_DEFAULT_PATH)
add_executable(app main.c)
target_link_libraries(app PRIVATE nimaid::nimaid)
```

### Cross-compiling *your* program with zig

Because the package is built with zig, the easiest way to cross-compile your own app is also zig:

```sh
python3 -m ziglang cc -target aarch64-linux-musl app.c -Iinclude lib/libnimaid.a -o app     # lib = linux-aarch64-musl package
```

## 3. The command-line tool

`bin/nimaid` is the nimaid CLI, written against this C API. Every command in the tutorials works with it:

```sh
bin/nimaid docs/examples/01-first.mmd first.png
bin/nimaid --theme=dark --scale=3 docs/examples/01-first.mmd first@3x.png
bin/nimaid --help
```

Fonts: DejaVu Sans is built in. Colour emoji are opt-in: `--emoji=fonts/NotoColorEmoji-Regular.ttf` (get the `fonts/` folder from the `nimaid-fonts-<version>.tar.gz` release asset).

## 4. Pick an output format

The format comes from the file extension (or the function you call):

```c
nimaid_render_file(ctx, text, "out.png", NULL);   /* PNG */
nimaid_render_file(ctx, text, "out.gif", NULL);   /* GIF */
nimaid_render_file(ctx, text, "out.svg", NULL);   /* SVG */
```

and in memory: `nimaid_render_png`, `nimaid_render_gif`, `nimaid_render_svg`, `nimaid_render_rgba`.

## 5. Where next

| I want to… | Go to |
|---|---|
| learn Mermaid syntax by example | [Tutorial 1](tutorials/01-first-flowchart.md) → [Tutorial 4](tutorials/04-other-diagrams.md) |
| render to memory, batch, custom fonts | [Tutorial 7](tutorials/07-c-library.md) |
| call it from Python / C++ / Rust / Go | [Tutorial 8](tutorials/08-other-languages.md) |
| look up a function | [C API reference](reference/c-api.md) |
| build for another platform | [Cross-compiling](cross-compiling.md) |
| something broke | [FAQ](faq.md) |
