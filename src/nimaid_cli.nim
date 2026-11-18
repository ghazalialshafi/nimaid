import std/[os, parseopt, strutils]
import nimaid

const helpText = """nimaid - Mermaid diagrams to PNG / GIF / SVG, in pure Nim

usage: nimaid [options] input.mmd output.(png|gif|svg)

  The output format is chosen by the output file extension.

options:
  --theme=NAME        default | dark | forest | neutral | base      (default: from diagram, else default)
  --scale=N           pixel scale for PNG/GIF, 2 = retina             (default: 2; SVG is always scale-free)
  --colors=N          2..256: palette PNG / smaller GIF               (default: truecolour PNG, 256-colour GIF)
  --svg-text=MODE     paths | text                                   (default: paths)
                        paths = outlined glyphs, looks identical everywhere
                        text  = live <text>, selectable/searchable, needs a similar font installed
  --font=FILE.ttf     text font, TrueType (glyf) outlines             (default: fonts/DejaVuSans.ttf)
  --emoji=FILE.ttf    colour emoji font (Noto, OpenType-SVG)          (default: fonts/NotoColorEmoji-Regular.ttf)
  --dagre=MODE        legacy | modern  graph layout tie-breaking      (default: legacy = matches Mermaid)
  -h, --help          show this help
  -v, --version       show the version

examples:
  nimaid flow.mmd flow.png
  nimaid --theme=dark --scale=3 flow.mmd flow@3x.png
  nimaid --svg-text=text flow.mmd flow.svg
"""

proc usage() =
  echo "usage: nimaid [options] input.mmd output.(png|gif|svg)   (nimaid --help for details)"
  quit(1)

var font = getAppDir() / ".." / "fonts" / "DejaVuSans.ttf"
var emojiFont = getAppDir() / ".." / "fonts" / "NotoColorEmoji-Regular.ttf"
var themeName = ""
var colors = 0
var svgText = false
var scale = 2.0
var pos: seq[string]
for kind, key, val in getopt():
  case kind
  of cmdLongOption:
    case key
    of "font": font = val
    of "scale": scale = parseFloat(val)
    of "emoji": emojiFont = val
    of "theme": themeName = val
    of "colors": colors = parseInt(val)
    of "svg-text": svgText = (val == "text" or val == "live" or val == "true")
    of "dagre": useLegacyDagre = (val != "modern")
    of "help": echo helpText; quit(0)
    of "version": echo "nimaid ", nimaidVersion; quit(0)
    else: usage()
  of cmdShortOption:
    case key
    of "h": echo helpText; quit(0)
    of "v": echo "nimaid ", nimaidVersion; quit(0)
    else: usage()
  of cmdArgument: pos.add key
  else: usage()
if pos.len != 2: usage()
let outLower = pos[1].toLowerAscii
if not (outLower.endsWith(".png") or outLower.endsWith(".gif") or outLower.endsWith(".svg")):
  quit "nimaid: output file must end in .png, .gif or .svg (got '" & pos[1] & "')"
try:
  renderMermaidToFile(readFile(pos[0]), pos[1], font, scale, emojiFont, themeName, colors, svgText)
except IOError as e:
  quit "failed: " & e.msg
except ValueError as e:
  quit "nimaid: " & pos[0] & ": " & e.msg & "\n  supported: flowchart/graph, sequenceDiagram, stateDiagram(-v2), erDiagram, classDiagram, gantt, gitGraph, mindmap"
except CatchableError as e:
  quit "nimaid: " & pos[0] & ": " & e.msg
echo "wrote ", pos[1]
