# Third-party components

nimaid bundles or derives from the following. Please check each project for its authoritative license text.

| Component | Where | Use | License |
|---|---|---|---|
| **DejaVu Sans** | `fonts/DejaVuSans.ttf` | default text font | DejaVu Fonts License (Bitstream Vera licence with public-domain DejaVu changes) — <https://dejavu-fonts.github.io/License.html> |
| **Noto Color Emoji** | `fonts/NotoColorEmoji-Regular.ttf` | colour emoji glyphs (OpenType-SVG) | SIL Open Font License 1.1 — text in `fonts/OFL-NotoColorEmoji.txt` |
| **nanosvg** (Nim port, `nanosvg-nim`) | `src/nimaid/purevg/nanosvg.nim` | SVG parsing (paths, transforms, styles, gradients) for emoji and pictures | Port of Mikko Mononen's NanoSVG (zlib licence); the Nim port is the project author's own work |
| **dagre_nim** | `dagre_nim/` | graph layout (a Nim port of dagre) by Ghazali (Project author's own work)| MIT |
| **Mermaid** | — | *Reference only.* The flowchart grammar, shape geometry, dagre driver rules and theme colours are re-implemented from Mermaid's published source so that output is compatible | MIT (Mermaid project) |

If you redistribute nimaid, ship the font licences next to the fonts.
