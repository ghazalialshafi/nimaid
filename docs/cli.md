# Command-line reference

```
nimaid [options] input.mmd output.(png|gif|svg)
```

* `input.mmd` — a Mermaid text file (UTF-8). The diagram type is detected from its first keyword.
* `output` — the extension selects the format: `.png`, `.gif` or `.svg` (anything else is an error).
* On success nimaid prints `wrote <output>` and exits with status 0. On failure it prints one line to stderr and exits with status 1.

## Options

| Option | Values | Default | Applies to | Meaning |
|---|---|---|---|---|
| `--theme=NAME` | `default` `dark` `forest` `neutral` `base` | from the diagram, else `default` | all | Colour theme. **Wins over** a theme set inside the diagram. |
| `--scale=N` | number > 0 | `2` | PNG, GIF | Pixel scale. `1` = CSS pixels, `2` = retina, `3` = extra crisp. SVG is scale-free and ignores it. |
| `--colors=N` | `2`…`256` | truecolour PNG / 256-colour GIF | PNG, GIF | Quantise to an N-colour palette (median-cut). Much smaller files, slight banding on gradients/emoji. |
| `--svg-text=MODE` | `paths` \| `text` | `paths` | SVG | `paths`: glyphs are outlined — identical in every viewer, no font needed. `text`: live `<text>` — selectable/searchable, but needs a similar font installed. |
| `--font=FILE` | path to a `.ttf` | `<bin>/../fonts/DejaVuSans.ttf` | all | Text font. Must be a TrueType font with `glyf` outlines (not CFF/`.otf`, not `.ttc`). |
| `--emoji=FILE` | path to a `.ttf` | `<bin>/../fonts/NotoColorEmoji-Regular.ttf` | all | Colour emoji font (Noto Color Emoji, OpenType-SVG flavour). |
| `--dagre=MODE` | `legacy` \| `modern` | `legacy` | flowchart-style layouts | Node-ordering tie-breaking. `legacy` reproduces Mermaid's `dagre-d3-es`; `modern` uses `dagre_nim`'s own defaults. |
| `-h`, `--help` | | | | Print help. |
| `-v`, `--version` | | | | Print the version. |

Options use the `--name=value` form.

## Recipes

```sh
# retina PNG with the dark theme
nimaid --theme=dark flow.mmd flow.png

# small web image
nimaid --scale=1 --colors=64 flow.mmd flow-small.png

# SVG for a web page (identical rendering everywhere)
nimaid flow.mmd flow.svg

# SVG with selectable text (for docs where users copy/search labels)
nimaid --svg-text=text flow.mmd flow-text.svg

# a different font
nimaid --font=/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf flow.mmd serif.png

# convert a whole folder
for f in diagrams/*.mmd; do nimaid "$f" "out/$(basename "${f%.mmd}").svg"; done
```

## Precedence: command line vs. diagram

Theme and some layout choices can be set in the diagram itself (`%%{init: …}%%` or YAML front matter).
When the same setting appears in both places, **the command line wins**. Everything else in the diagram text (titles, styles, `themeVariables`) is still applied.

## Exit status and messages

| Situation | Message (stderr) | Exit |
|---|---|---|
| Success | `wrote out.png` (stdout) | 0 |
| Input file missing | `failed: cannot open: missing.mmd` | 1 |
| Font cannot be loaded | `failed: cannot load font /nope.ttf` | 1 |
| Unknown output extension | `nimaid: output file must end in .png, .gif or .svg (got 'x.xyz')` | 1 |
| Unsupported diagram type | `nimaid: sankey.mmd: unsupported diagram type` + list of supported types | 1 |
| Syntax error | `nimaid: bad.mmd: Parse error: expecting node id, got tEof` | 1 |

See the [FAQ](faq.md) for how to fix each of these.
