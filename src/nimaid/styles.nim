## Resolves mermaid style declarations (classDef / style / linkStyle strings) into drawing attributes.
import std/[strutils, tables, math]
import theme

const cssColorList = [
  ("aliceblue", 0xF0F8FF'u32),
  ("antiquewhite", 0xFAEBD7'u32),
  ("aqua", 0x00FFFF'u32),
  ("aquamarine", 0x7FFFD4'u32),
  ("azure", 0xF0FFFF'u32),
  ("beige", 0xF5F5DC'u32),
  ("bisque", 0xFFE4C4'u32),
  ("black", 0x000000'u32),
  ("blanchedalmond", 0xFFEBCD'u32),
  ("blue", 0x0000FF'u32),
  ("blueviolet", 0x8A2BE2'u32),
  ("brown", 0xA52A2A'u32),
  ("burlywood", 0xDEB887'u32),
  ("cadetblue", 0x5F9EA0'u32),
  ("chartreuse", 0x7FFF00'u32),
  ("chocolate", 0xD2691E'u32),
  ("coral", 0xFF7F50'u32),
  ("cornflowerblue", 0x6495ED'u32),
  ("cornsilk", 0xFFF8DC'u32),
  ("crimson", 0xDC143C'u32),
  ("cyan", 0x00FFFF'u32),
  ("darkblue", 0x00008B'u32),
  ("darkcyan", 0x008B8B'u32),
  ("darkgoldenrod", 0xB8860B'u32),
  ("darkgray", 0xA9A9A9'u32),
  ("darkgreen", 0x006400'u32),
  ("darkgrey", 0xA9A9A9'u32),
  ("darkkhaki", 0xBDB76B'u32),
  ("darkmagenta", 0x8B008B'u32),
  ("darkolivegreen", 0x556B2F'u32),
  ("darkorange", 0xFF8C00'u32),
  ("darkorchid", 0x9932CC'u32),
  ("darkred", 0x8B0000'u32),
  ("darksalmon", 0xE9967A'u32),
  ("darkseagreen", 0x8FBC8F'u32),
  ("darkslateblue", 0x483D8B'u32),
  ("darkslategray", 0x2F4F4F'u32),
  ("darkslategrey", 0x2F4F4F'u32),
  ("darkturquoise", 0x00CED1'u32),
  ("darkviolet", 0x9400D3'u32),
  ("deeppink", 0xFF1493'u32),
  ("deepskyblue", 0x00BFFF'u32),
  ("dimgray", 0x696969'u32),
  ("dimgrey", 0x696969'u32),
  ("dodgerblue", 0x1E90FF'u32),
  ("firebrick", 0xB22222'u32),
  ("floralwhite", 0xFFFAF0'u32),
  ("forestgreen", 0x228B22'u32),
  ("fuchsia", 0xFF00FF'u32),
  ("gainsboro", 0xDCDCDC'u32),
  ("ghostwhite", 0xF8F8FF'u32),
  ("gold", 0xFFD700'u32),
  ("goldenrod", 0xDAA520'u32),
  ("gray", 0x808080'u32),
  ("green", 0x008000'u32),
  ("greenyellow", 0xADFF2F'u32),
  ("grey", 0x808080'u32),
  ("honeydew", 0xF0FFF0'u32),
  ("hotpink", 0xFF69B4'u32),
  ("indianred", 0xCD5C5C'u32),
  ("indigo", 0x4B0082'u32),
  ("ivory", 0xFFFFF0'u32),
  ("khaki", 0xF0E68C'u32),
  ("lavender", 0xE6E6FA'u32),
  ("lavenderblush", 0xFFF0F5'u32),
  ("lawngreen", 0x7CFC00'u32),
  ("lemonchiffon", 0xFFFACD'u32),
  ("lightblue", 0xADD8E6'u32),
  ("lightcoral", 0xF08080'u32),
  ("lightcyan", 0xE0FFFF'u32),
  ("lightgoldenrodyellow", 0xFAFAD2'u32),
  ("lightgray", 0xD3D3D3'u32),
  ("lightgreen", 0x90EE90'u32),
  ("lightgrey", 0xD3D3D3'u32),
  ("lightpink", 0xFFB6C1'u32),
  ("lightsalmon", 0xFFA07A'u32),
  ("lightseagreen", 0x20B2AA'u32),
  ("lightskyblue", 0x87CEFA'u32),
  ("lightslategray", 0x778899'u32),
  ("lightslategrey", 0x778899'u32),
  ("lightsteelblue", 0xB0C4DE'u32),
  ("lightyellow", 0xFFFFE0'u32),
  ("lime", 0x00FF00'u32),
  ("limegreen", 0x32CD32'u32),
  ("linen", 0xFAF0E6'u32),
  ("magenta", 0xFF00FF'u32),
  ("maroon", 0x800000'u32),
  ("mediumaquamarine", 0x66CDAA'u32),
  ("mediumblue", 0x0000CD'u32),
  ("mediumorchid", 0xBA55D3'u32),
  ("mediumpurple", 0x9370DB'u32),
  ("mediumseagreen", 0x3CB371'u32),
  ("mediumslateblue", 0x7B68EE'u32),
  ("mediumspringgreen", 0x00FA9A'u32),
  ("mediumturquoise", 0x48D1CC'u32),
  ("mediumvioletred", 0xC71585'u32),
  ("midnightblue", 0x191970'u32),
  ("mintcream", 0xF5FFFA'u32),
  ("mistyrose", 0xFFE4E1'u32),
  ("moccasin", 0xFFE4B5'u32),
  ("navajowhite", 0xFFDEAD'u32),
  ("navy", 0x000080'u32),
  ("oldlace", 0xFDF5E6'u32),
  ("olive", 0x808000'u32),
  ("olivedrab", 0x6B8E23'u32),
  ("orange", 0xFFA500'u32),
  ("orangered", 0xFF4500'u32),
  ("orchid", 0xDA70D6'u32),
  ("palegoldenrod", 0xEEE8AA'u32),
  ("palegreen", 0x98FB98'u32),
  ("paleturquoise", 0xAFEEEE'u32),
  ("palevioletred", 0xDB7093'u32),
  ("papayawhip", 0xFFEFD5'u32),
  ("peachpuff", 0xFFDAB9'u32),
  ("peru", 0xCD853F'u32),
  ("pink", 0xFFC0CB'u32),
  ("plum", 0xDDA0DD'u32),
  ("powderblue", 0xB0E0E6'u32),
  ("purple", 0x800080'u32),
  ("rebeccapurple", 0x663399'u32),
  ("red", 0xFF0000'u32),
  ("rosybrown", 0xBC8F8F'u32),
  ("royalblue", 0x4169E1'u32),
  ("saddlebrown", 0x8B4513'u32),
  ("salmon", 0xFA8072'u32),
  ("sandybrown", 0xF4A460'u32),
  ("seagreen", 0x2E8B57'u32),
  ("seashell", 0xFFF5EE'u32),
  ("sienna", 0xA0522D'u32),
  ("silver", 0xC0C0C0'u32),
  ("skyblue", 0x87CEEB'u32),
  ("slateblue", 0x6A5ACD'u32),
  ("slategray", 0x708090'u32),
  ("slategrey", 0x708090'u32),
  ("snow", 0xFFFAFA'u32),
  ("springgreen", 0x00FF7F'u32),
  ("steelblue", 0x4682B4'u32),
  ("tan", 0xD2B48C'u32),
  ("teal", 0x008080'u32),
  ("thistle", 0xD8BFD8'u32),
  ("tomato", 0xFF6347'u32),
  ("turquoise", 0x40E0D0'u32),
  ("violet", 0xEE82EE'u32),
  ("wheat", 0xF5DEB3'u32),
  ("white", 0xFFFFFF'u32),
  ("whitesmoke", 0xF5F5F5'u32),
  ("yellow", 0xFFFF00'u32),
  ("yellowgreen", 0x9ACD32'u32),
]

let cssColors = block:
  var t = initTable[string, uint32]()
  for (n, v) in cssColorList: t[n] = v
  t

type
  ResolvedStyle* = object
    hasFill*, hasStroke*, hasColor*: bool
    fill*, stroke*, color*: Color
    strokeWidth*: float        ## 0 = unset
    dash*: seq[float]
    hasDash*: bool
    opacity*: float            ## -1 = unset
    bold*, italic*: bool
    fontSize*: float           ## 0 = unset

proc tryParseColor*(raw: string, c: var Color): bool =
  let s = raw.strip().toLowerAscii
  if s.len == 0: return false
  if s == "none" or s == "transparent":
    c = rgba(0, 0, 0, 0)
    return true
  if s[0] == '#':
    let h = s[1 .. ^1]
    for ch in h:
      if ch notin {'0'..'9', 'a'..'f'}: return false
    if h.len in [3, 6, 8]:
      c = parseColor(s)
      return true
    return false
  if s.startsWith("rgb"):
    c = parseColor(s)
    return true
  if s in cssColors:
    let v = cssColors[s]
    c = rgba(uint8((v shr 16) and 0xFF), uint8((v shr 8) and 0xFF), uint8(v and 0xFF))
    return true
  false

proc parseLength(raw: string): float =
  var s = raw.strip().toLowerAscii.replace("!important", "").strip()
  s = s.replace("px", "")
  try: parseFloat(s) except ValueError: 0.0

proc resolveStyles*(lists: varargs[seq[string]]): ResolvedStyle =
  ## Later lists override earlier ones (classDef first, inline `style` last).
  result.opacity = -1
  for lst in lists:
    for decl in lst:
      for part in decl.split(';'):
        let ci = part.find(':')
        if ci <= 0: continue
        let k = part[0 ..< ci].strip().toLowerAscii
        let v = part[ci + 1 .. ^1].strip().replace("!important", "").strip()
        var c: Color
        case k
        of "fill":
          if tryParseColor(v, c):
            result.fill = c
            result.hasFill = true
        of "stroke":
          if tryParseColor(v, c):
            result.stroke = c
            result.hasStroke = true
        of "color":
          if tryParseColor(v, c):
            result.color = c
            result.hasColor = true
        of "stroke-width":
          result.strokeWidth = parseLength(v)
        of "stroke-dasharray":
          result.dash = @[]
          for tok in v.replace(",", " ").splitWhitespace():
            let n = parseLength(tok)
            if n > 0: result.dash.add n
          result.hasDash = result.dash.len > 0
        of "opacity":
          try: result.opacity = parseFloat(v) except ValueError: discard
        of "font-weight":
          result.bold = v == "bold" or v == "bolder" or (v.len > 0 and v[0] in {'6'..'9'})
        of "font-style":
          result.italic = v == "italic"
        of "font-size":
          result.fontSize = parseLength(v)
        else: discard
