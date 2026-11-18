## Render to memory: raw pixels, PNG bytes and an SVG string, without touching the disk.
import nimaid

const chart = """
flowchart TD
    A[Request] --> B{Cached?}
    B -->|yes| C[Serve]
    B -->|no| D[Compute] --> C
"""
const font = "fonts/DejaVuSans.ttf"

# 1) Raw pixels (straight-alpha RGBA8, row-major)
let img = renderMermaidToImage(chart, font, scale = 2.0)
echo "pixels: ", img.width, "x", img.height, " (", img.rgba.len, " bytes)"

# 2) PNG bytes, e.g. to send over HTTP or store in a database
let png = encodePng(img.rgba, img.width, img.height)
echo "png: ", png.len, " bytes"
let small = encodePng(img.rgba, img.width, img.height, colors = 64)   # palette PNG
echo "palette png: ", small.len, " bytes"

# 3) SVG text (scale-free). `svgText = true` keeps text selectable.
let svg = renderMermaidToSvg(chart, font, themeName = "forest")
echo "svg: ", svg.len, " chars, starts with: ", svg[0 ..< 40]
writeFile("in_memory.svg", svg)
