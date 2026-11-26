# Changelog

## [0.6.1] - 2026-11-26

### Fixed
- **Kanban crashed on 32-bit targets** (wasm32, armv7, i386) with `over- or underflow` when a card had an `assigned:` name longer than 6 characters:
  the avatar-colour hash used `int`, which is 32 bits there. It now uses wrapping `uint64` arithmetic (same colours as before on 64-bit).

### Added
- The wasm test suite renders every shipped example on wasm32 (it previously rendered only tiny diagrams), plus a kanban regression test.
- **Website + playground** (`site/`, deployed to GitHub Pages by `.github/workflows/pages.yml`): a home page with a gallery of all 18 diagram types, and a live playground
  (editor, pan/zoom preview, 26 examples, SVG/PNG export, shareable links, colour emoji loaded on demand). New logo; README and package READMEs link to it.

## [0.6.0] - 2026-11-26

First release with the C API, Python wheels, WebAssembly build and automated cross-platform releases, on top of all eighteen diagram types
(the ten chart diagrams added in 0.4.0 – 0.5.1 are covered by every binding).

### Added
- **C API** (`capi/`): stable C ABI (`nimaid.h`), reusable contexts, PNG / GIF / SVG / RGBA output, fonts from files or memory,
  header-only C++ wrapper. DejaVu Sans is embedded, so no font files are needed. `nimaid_detect_type` now also returns
  `pie`, `xychart`, `timeline`, `quadrant`, `journey`, `packet`, `kanban`, `radar`, `treemap` and `sankey`.
- **Python package** (`python/`): `pip install nimaid` — platform wheels for Linux (glibc + musl), macOS and Windows; `nimaid-noto-emoji` for colour emoji.
- **WebAssembly build** (`wasm/`): `nimaid.wasm` + `nimaid.mjs` for Node, Deno, Bun and browsers; npm package `nimaid`.
- **Standalone CLI binaries** for 14 platforms with the font built in (`-d:nimaidEmbedFont`).
- **Automated releases**: one tag builds everything with Zig, tests it on real runners (Linux x86_64/ARM, macOS Intel/ARM, Windows,
  Alpine, old glibc, QEMU ARM/i386), then publishes a GitHub Release, the PyPI wheels and (optionally) the npm package.
- Library: `initTextMetricsData`, `loadEmojiFontData`, `unloadEmojiFont`, `buildMermaidSceneLoaded` (fonts from memory / reuse of loaded fonts).
- `tools/bump_version.py` keeps every version string in sync.
- C, Python and wasm test suites render and detect all ten chart types; the C API docs gained Tutorial 9 (charts) and the chart syntax / theme references.

### Changed
- `backgroundOf` is exported.
- The `nimaid` CLI falls back to the built-in font when `fonts/DejaVuSans.ttf` is not next to the binary (release builds).
- FAQ: `themeVariables` accept CSS colour names (since 0.5.0).

## [0.5.1] — sankey, kanban and journey look-and-feel

### Changed
- **Sankey:** automatic canvas height (busy diagrams no longer collapse into hairlines), ribbons painted under nodes and labels, labels on soft pills with per-column and cross-column de-collision, first-column labels on the left, values in a muted tone, softly rounded nodes. `labelStyle: legacy` keeps Mermaid's placement; an explicit `height` is respected.
- **Kanban:** desaturated column tints with an accent bar and a card-count badge, left-aligned headers, soft-shadow cards, a footer row with a ticket pill and an initials avatar + name that never overlap (long names are shortened), rounded priority bars. `kanban.classicColors: true` keeps the original flat look.
- **Journey:** saturated section headers with white text and matching tinted task cards, mood-coloured faces (red → amber → green), a smooth emotion curve with 1–5 guide lines, distinct actor colours, soft shadows; works in all themes. `journey.classicColors: true` keeps Mermaid's palette.

### Added
- `mixColor` / `kShadow` helpers; tests for the auto height and the classic-colour switches (49 tests).

## [0.5.0] — more diagrams, audited against Mermaid's source

### Added
- **Five more diagram types:** **packet**, **kanban**, **radar** (`radar-beta`), **treemap** (`treemap-beta`, with d3-hierarchy's squarified layout) and **sankey** (`sankey-beta`, a port of d3-sankey with gradient ribbons).
- **Gradient fills and strokes on shapes** in the engine (`pvg_linear_gradient_new`, `pvg_gradient_add_stop`, `pvg_shape_set_fill/stroke_gradient`), the scene recorder and the SVG writer.
- Pie options from Mermaid's config: `legendPosition`, `textPosition`, `donutHole`, `highlightSlice`.
- The complete CSS named-colour table in `parseCssColor`; khroma-style `lighten`/`darken`.
- All nested theme groups (`radar.*`, `packet.*`, `xyChart.*`) are now extracted from Mermaid's themes; `tools/themes/dump_chart_themes.mjs` regenerates them.
- Tutorial 9 now covers all ten chart types; syntax reference, theme tables, FAQ and architecture updated.
- Tests: 47 (10 new); goldens for the new examples.

### Changed
- **Journey corrected against the real renderer** (found in the full Mermaid repository): legend wrapping and `leftMargin = config + widest legend line`, 16 px legend text, score lines and axis coloured by the theme text colour, title inherits the root fill, and the `journey` config block is honoured.
- **Pie slices are individual 70 %-opacity elements** (not one group), matching `.pieCircle { opacity }`.
- Arrowheads in timeline and journey inherit the theme text colour (they were black).
- SVG opacities use 3 decimals so the SVG matches the raster alpha exactly.

## [0.4.0] — chart diagrams

### Added
- **Five new diagram types**, ported from Mermaid's renderers and themes: **pie**, **XY chart** (`xychart-beta`: bar + line, category/numeric axes, vertical and horizontal, legend, data labels, d3 ticks), **timeline**, **quadrant chart** (points, `classDef`, inline styles) and **user journey** (faces, actors, sections).
- `chartheme`: Mermaid's evaluated theme variables for all five themes (embedded), CSS colour parsing (`#hex`, `rgb()`, `hsl()`, names) and per-chart overrides, including nested `themeVariables.xyChart`.
- `config.readConfig`: a structured reader for nested `%%{init: {...}}%%` directives and YAML front matter.
- `chartkit`: shared helpers for SVG-style text placement (baseline/anchor, rotation), arcs, arrowheads.
- **Rotation** across the scene recorder and the SVG writer (`rotate(...)` transforms, outlined and live text).
- CLI: the "supported types" message lists the new diagrams.
- Docs: Tutorial 9 (charts), syntax reference sections, theme-variable tables for the charts, updated architecture, FAQ and contributor guides; new examples with golden images.
- Tests: 14 new chart tests (37 total), plus golden PNGs for the five new examples in the visual-regression suite.

## [0.3.0]
- Previous release.
