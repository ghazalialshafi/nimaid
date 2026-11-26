# nimaid C API documentation

Mermaid diagrams to PNG / GIF / SVG / raw pixels, from C — and from anything that can call C.
Pure Nim core, **no runtime dependencies, no font files needed** (DejaVu Sans is built in), one header.

| | |
|---|---|
| **New here?** | [Getting started](getting-started.md) → [Tutorial 1](tutorials/01-first-flowchart.md) |
| **Looking something up?** | [C API](reference/c-api.md) · [Diagram syntax](reference/diagram-syntax.md) · [Themes](reference/themes.md) · [Output formats](reference/output-formats.md) |
| **Building for a platform?** | [Cross-compiling](cross-compiling.md) |
| **Something broke?** | [FAQ & troubleshooting](faq.md) |

## Tutorials

1. [Your first flowchart](tutorials/01-first-flowchart.md) — nodes, labels, links, direction
2. [Shapes, links and subgraphs](tutorials/02-shapes-links-subgraphs.md)
3. [Styling and themes](tutorials/03-styling-and-themes.md)
4. [Other diagram types](tutorials/04-other-diagrams.md) — sequence, state, ER, class, Gantt, Git graph, mindmap, and the ten chart types
5. [Text, fonts and emoji](tutorials/05-text-fonts-emoji.md)
6. [PNG, GIF and SVG](tutorials/06-output-formats.md)
7. [Using nimaid from C](tutorials/07-c-library.md)
8. [Calling nimaid from other languages](tutorials/08-other-languages.md) — Python, C++, and the recipe for the rest
9. [Charts](tutorials/09-charts.md) — pie, XY, timeline, quadrant, journey, packet, kanban, radar, treemap, sankey

Tutorials 1–6 and 9 show the `nimaid` command-line tool (`bin/nimaid`, included in every package and built on the C API), run from the package root so that `docs/examples/*.mmd` is found. Tutorials 7–8 are about the library.
Runnable sources: [`docs/examples/`](examples) (Mermaid) and [`examples/`](../examples) (C, Python).

The tutorials, the syntax / themes / output-format references and the FAQ are shared with the main nimaid project
(<https://github.com/ghazalialshafi/nimaid>), which also documents its internals (architecture, PureVG engine, extending).
