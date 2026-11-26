# Building and cross-compiling the C API

One machine, one command, every platform. The build uses **Nim** to turn the library into C and **Zig** (`zig cc`) as the C compiler and linker for each target — no per-platform toolchains, SDKs or virtual machines.

## Requirements

```sh
pip install ziglang            # the cross compiler (any host: Linux, macOS, Windows)
# Nim >= 2.0 from https://nim-lang.org/install.html (the official tarball/installer, so that lib/nimbase.h exists)
```

## Build

```sh
python3 capi/build.py --list                     # the 14 targets
python3 capi/build.py                            # everything  -> capi/dist/
python3 capi/build.py -t native                  # only this machine
python3 capi/build.py -t windows-x86_64 macos-aarch64 linux-x86_64-musl
```

| Target | Zig triple | Notes |
|---|---|---|
| `linux-x86_64-gnu`, `linux-aarch64-gnu` | `…-linux-gnu.2.17` | runs on glibc ≥ 2.17 (CentOS 7 era and newer) |
| `linux-armv7-gnueabihf`, `linux-x86-gnu`, `linux-riscv64-gnu` | | 32-bit ARM (Raspberry Pi OS 32-bit), 32-bit x86, RISC-V 64 |
| `linux-x86_64-musl`, `linux-aarch64-musl`, `linux-armv7-musleabihf` | | Alpine; static executables with no libc dependency |
| `windows-x86_64`, `windows-aarch64`, `windows-x86` | `…-windows-gnu` | DLL + import library + static library |
| `macos-x86_64`, `macos-aarch64` | `…-macos.11.0` | macOS 11 and newer; no Xcode needed |
| `freebsd-x86_64` | | |

What happens per target (see `capi/build.py`, ~200 lines):

1. `nim c --compileOnly --os:<os> --cpu:<cpu>` generates the C sources for exactly that platform.
2. Nim's runtime entry points (`NimMain`, …) are marked private, so the shared library exports **only** the `nimaid_*` functions.
3. Every `.c` file is compiled in parallel with `zig cc -target <triple> -O2`.
4. The objects are archived (`libnimaid.a`), linked into the shared library, and the CLI (`examples/nimaid_cli.c`) is linked against the static library.
5. On the host platform the C and C++ test suites run against both the static and the shared library; for Windows the DLL's export table is checked.
6. Everything is packaged as `dist/nimaid-capi-<version>-<target>.tar.gz` (`.zip` for Windows), plus `nimaid-fonts-<version>.tar.gz` and `SHA256SUMS` when all targets are built.

## More products

```sh
python3 capi/build.py --products capi cli     # default: C API package + standalone Nim CLI (src/nimaid_cli.nim, font built in)
python3 capi/build.py -t wasm32-wasi          # nimaid.wasm + nimaid.mjs (npm package layout)
```

The CLI archive `nimaid-cli-<version>-<target>` is one static executable; the build checks that it renders byte-identically to the C API CLI.
The wasm target compiles the same C API to `wasm32-wasi` (WASI reactor, 2 MB) and tests it with Node. Everything is run for you by the
[release workflow](../../docs/releasing.md) on every tag.

## Options

```sh
python3 capi/build.py --nim /path/to/nim          # nim not on PATH
python3 capi/build.py -j 8                        # parallel compile jobs
python3 capi/build.py --nim-arg=-d:nimaidNoEmbeddedFont     # smaller: don't embed DejaVu Sans (~0.75 MB)
```

Without the embedded font, `nimaid_context_new()` has no text font until you call `nimaid_context_set_font_file/_data`; renders fail with `NIMAID_ERR_FONT` otherwise.

## Adding a target

Add one line to `TARGETS` in `capi/build.py`: `name: (zig triple, nim --os, nim --cpu, kind)`. `zig targets` lists every triple Zig can build; the Nim side must support the `--os`/`--cpu` pair (`nim --help`).

## Testing a build

```sh
python3 capi/build.py -t native          # builds, then runs tests/test_capi.c and tests/test_cpp.cpp
```

For other architectures, run the test suite on the real thing (or under QEMU / Wine): `tests/test_capi.c` needs no arguments and prints `all C API tests passed`.

## Notes

* **Why not `nim c --app:lib` directly?** Nim's own cross-compilation needs a C toolchain per target. Generating C once per target and compiling it with Zig replaces all of them with one `pip install`.
* The renderer is deterministic, and the CLI built from this API produces byte-identical PNGs to the Nim CLI (checked on the host platform).
* Static libraries built by Zig are standard archives; MSVC users should prefer the DLL + import library.
