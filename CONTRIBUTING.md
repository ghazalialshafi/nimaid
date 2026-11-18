# Contributing to nimaid

Thanks for helping! This guide gets you from a fresh clone to a pull request.

## Set up

```sh
./build.sh                       # builds bin/nimaid
bin/nimaid --version
```

Requirements: Nim ≥ 2.0 and a C compiler. For the optional visual tests: Python 3 with `Pillow` and `numpy` (and `resvg-py` for SVG checks).

## The test suite

Run everything before sending a change:

```sh
nim c -r tests/test_purevg.nim        # engine + SVG writer: 23 unit/end-to-end tests
python3 tests/visual_regression.py    # all examples vs golden PNGs; SVG vs PNG
python3 tests/smoke_examples.py       # every example renders
python3 tests/conformance.py          # flowchart parser vs Mermaid's own spec assertions
python3 tests/render_all_specs.py     # every Mermaid spec chart renders (none may crash/hang)
```

`tests/visual_regression.py` compares against `examples/*.png`. If you **intentionally** change how something looks, regenerate that golden image, look at it, and mention it in the PR:

```sh
bin/nimaid examples/foo.mmd examples/foo.png
```

Layout fuzzing against the real Mermaid layout library (needs Node):

```sh
cd tools/jscheck && npm i dagre-d3-es && node fuzz.mjs 1 300 c
```

## Code style

* Plain Nim, standard library only (no new runtime dependencies — that is a project goal).
* `nimpretty`-style formatting, 2-space indent, `snake_case` only for the engine's C-style `pvg_*` API; `camelCase` elsewhere.
* Keep modules small and single-purpose; put each non-obvious algorithm behind a short `##` doc comment that says *why*.
* Don't commit binaries other than `bin/nimaid` (rebuilt by `build.sh`).

## Documentation

* Every user-visible change needs a docs update: README table, the relevant tutorial or reference page, and `CHANGELOG.md`.
* Code samples in the docs are real programs under `docs/examples/`. Keep them compiling:

  ```sh
  nim c -r docs/examples/hello.nim
  ```
* Doc images are generated, never hand-edited: change `docs/examples/*.mmd`, then `docs/build_images.sh`.

## Adding a diagram type

See [docs/extending.md](docs/extending.md).

## Pull request checklist

- [ ] `nim c -r tests/test_purevg.nim` passes
- [ ] `python3 tests/visual_regression.py` prints `OK` (or golden images updated and explained)
- [ ] New behaviour has a test or an example
- [ ] Docs and CHANGELOG updated
- [ ] No new runtime dependencies

## Reporting bugs

Include: the smallest `.mmd` that reproduces it, the exact command, the output or error message, and what you expected (a Mermaid live-editor screenshot is ideal).
