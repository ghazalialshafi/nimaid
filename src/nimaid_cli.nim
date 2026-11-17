import std/[os, parseopt, strutils]
import nimaid

proc usage() =
  echo "usage: nimaid [--font=path.ttf] [--emoji=NotoColorEmoji.ttf] [--dagre=legacy|modern] [--theme=default|dark|forest|neutral|base] [--colors=2..256] [--scale=2] [--svg-text=paths|text] input.mmd output.png"
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
    else: usage()
  of cmdArgument: pos.add key
  else: usage()
if pos.len != 2: usage()
try:
  renderMermaidToFile(readFile(pos[0]), pos[1], font, scale, emojiFont, themeName, colors, svgText)
except IOError as e:
  quit "failed: " & e.msg
echo "wrote ", pos[1]
