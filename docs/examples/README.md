# Example sources

Everything the documentation shows comes from the files in this folder.

| File | Used by | What it is |
|---|---|---|
| `01-first.mmd` … `14-emoji.mmd` | tutorials 1–6 | Mermaid diagrams (flowchart, subgraphs, styling, themes, sequence, state, ER, class, Gantt, Git graph, mindmap, emoji) |
| `15-pie.mmd` … `26-pie-config.mmd` | tutorial 9 | pie (+ options), XY chart (vertical and horizontal), timeline, quadrant, journey, packet, kanban, radar, treemap, sankey |
| `arch-pipeline.mmd`, `arch-engine.mmd` | architecture guide | the architecture diagrams, drawn by nimaid itself |
| `hello.nim` | tutorial 7 | smallest possible program |
| `in_memory.nim` | tutorial 7 | RGBA pixels, PNG bytes, SVG string |
| `batch.nim` | tutorial 7 | convert a folder with error handling |
| `engine_demo.nim` | tutorial 8 | drawing with the PureVG engine |
| `scene_both.nim` | tutorial 8 | one scene → PNG and SVG |

Run the Nim programs from the repository root (so `fonts/` is found):

```sh
nim c -r docs/examples/hello.nim
nim c -r docs/examples/engine_demo.nim
```

Regenerate every image in `docs/images/`:

```sh
./build.sh && docs/build_images.sh
```
