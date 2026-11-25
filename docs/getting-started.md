# Getting started

This page takes you from nothing to a rendered diagram in about five minutes.

## 1. What you need

| Requirement | Notes |
|---|---|
| [Nim](https://nim-lang.org/install.html) ≥ 2.0 | `nim --version` to check. Developed and tested with Nim 2.2 on Linux x86-64. |
| A C compiler | `gcc` or `clang` — Nim compiles through C. |

Nothing else: no browser, no Node.js, no Python, no system libraries. The only runtime dependencies of the finished binary are libc and libm.
Python 3 with Pillow is needed **only** to run the optional visual-regression tests.

## 2. Build

```sh
git clone <your-repo-url> nimaid && cd nimaid
./build.sh
```

`build.sh` is a one-liner around:

```sh
nim c -d:release -o:bin/nimaid src/nimaid_cli.nim
```

The project's `nim.cfg` already points Nim at `src/` and the bundled `dagre_nim/src/`, so no extra flags are required.
Check it worked:

```sh
bin/nimaid --version        # nimaid 0.5.1
```

## 3. Render your first diagram

Create `hello.mmd`:

```
flowchart LR
    A[Hello] --> B[World]
```

and render it:

```sh
bin/nimaid hello.mmd hello.png
```

Open `hello.png`. You just ran the whole pipeline: parse → layout → draw → encode.

> **Where are the fonts?** By default nimaid looks for `fonts/DejaVuSans.ttf` and `fonts/NotoColorEmoji-Regular.ttf`
> *next to the binary's parent folder* (`bin/../fonts`). If you copy `bin/nimaid` elsewhere, keep a `fonts/` folder beside its
> parent directory or pass `--font=` and `--emoji=` explicitly.

## 4. Pick an output format

The output format comes from the file extension:

```sh
bin/nimaid hello.mmd hello.png     # PNG, retina scale (2×)
bin/nimaid hello.mmd hello.svg     # scalable vector
bin/nimaid hello.mmd hello.gif     # GIF
```

Make the PNG smaller or larger:

```sh
bin/nimaid --scale=1 hello.mmd hello-1x.png      # half the pixel size
bin/nimaid --scale=3 hello.mmd hello-3x.png      # extra crisp
bin/nimaid --colors=64 hello.mmd hello-small.png # palette PNG, roughly 2–3× smaller
```

## 5. Try a theme

```sh
bin/nimaid --theme=dark hello.mmd hello-dark.png
```

Themes: `default`, `dark`, `forest`, `neutral`, `base`. You can also choose one inside the diagram — see [Styling & themes](tutorials/03-styling-and-themes.md).

## 6. Try the examples

The repository ships sample diagrams for every supported type:

```sh
ls examples/*.mmd
bin/nimaid examples/sequence.mmd sequence.png
bin/nimaid examples/emoji.mmd emoji.svg
```

Each `examples/NAME.png` is the golden image that the test-suite compares against.

## 7. Where next?

| If you want to… | Read |
|---|---|
| Learn the Mermaid syntax by doing | [Tutorial 1 — your first flowchart](tutorials/01-first-flowchart.md) |
| Draw pie / XY / timeline / quadrant / journey charts | [Tutorial 9 — charts](tutorials/09-charts.md) |
| See every command-line flag | [CLI reference](cli.md) |
| Call nimaid from your own Nim program | [Tutorial 7 — library](tutorials/07-library.md) |
| Draw your own graphics with the engine | [Tutorial 8 — PureVG](tutorials/08-purevg-engine.md) |
| Something broke | [FAQ & troubleshooting](faq.md) |
