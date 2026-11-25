## Theme variables + CSS colour parsing shared by the "chart" diagrams (pie, xychart, timeline, quadrant, journey, ...).
## The values are Mermaid's own theme output (theme-*.js evaluated for all five themes) and are embedded at compile time.
import std/[json, strutils, tables, math, options]
import theme, config

const themeData = staticRead("data/chart_themes.json")
let themeTable = block:
  var t = initTable[string, Table[string, string]]()
  for name, vars in parseJson(themeData):
    var m = initTable[string, string]()
    for k, v in vars: m[k] = v.getStr()
    t[name] = m
  t

const cssNamed = {
  "aliceblue": 0xf0f8ff,
  "antiquewhite": 0xfaebd7,
  "aqua": 0x00ffff,
  "aquamarine": 0x7fffd4,
  "azure": 0xf0ffff,
  "beige": 0xf5f5dc,
  "bisque": 0xffe4c4,
  "black": 0x000000,
  "blanchedalmond": 0xffebcd,
  "blue": 0x0000ff,
  "blueviolet": 0x8a2be2,
  "brown": 0xa52a2a,
  "burlywood": 0xdeb887,
  "cadetblue": 0x5f9ea0,
  "chartreuse": 0x7fff00,
  "chocolate": 0xd2691e,
  "coral": 0xff7f50,
  "cornflowerblue": 0x6495ed,
  "cornsilk": 0xfff8dc,
  "crimson": 0xdc143c,
  "cyan": 0x00ffff,
  "darkblue": 0x00008b,
  "darkcyan": 0x008b8b,
  "darkgoldenrod": 0xb8860b,
  "darkgray": 0xa9a9a9,
  "darkgreen": 0x006400,
  "darkgrey": 0xa9a9a9,
  "darkkhaki": 0xbdb76b,
  "darkmagenta": 0x8b008b,
  "darkolivegreen": 0x556b2f,
  "darkorange": 0xff8c00,
  "darkorchid": 0x9932cc,
  "darkred": 0x8b0000,
  "darksalmon": 0xe9967a,
  "darkseagreen": 0x8fbc8f,
  "darkslateblue": 0x483d8b,
  "darkslategray": 0x2f4f4f,
  "darkslategrey": 0x2f4f4f,
  "darkturquoise": 0x00ced1,
  "darkviolet": 0x9400d3,
  "deeppink": 0xff1493,
  "deepskyblue": 0x00bfff,
  "dimgray": 0x696969,
  "dimgrey": 0x696969,
  "dodgerblue": 0x1e90ff,
  "firebrick": 0xb22222,
  "floralwhite": 0xfffaf0,
  "forestgreen": 0x228b22,
  "fuchsia": 0xff00ff,
  "gainsboro": 0xdcdcdc,
  "ghostwhite": 0xf8f8ff,
  "gold": 0xffd700,
  "goldenrod": 0xdaa520,
  "gray": 0x808080,
  "green": 0x008000,
  "greenyellow": 0xadff2f,
  "grey": 0x808080,
  "honeydew": 0xf0fff0,
  "hotpink": 0xff69b4,
  "indianred": 0xcd5c5c,
  "indigo": 0x4b0082,
  "ivory": 0xfffff0,
  "khaki": 0xf0e68c,
  "lavender": 0xe6e6fa,
  "lavenderblush": 0xfff0f5,
  "lawngreen": 0x7cfc00,
  "lemonchiffon": 0xfffacd,
  "lightblue": 0xadd8e6,
  "lightcoral": 0xf08080,
  "lightcyan": 0xe0ffff,
  "lightgoldenrodyellow": 0xfafad2,
  "lightgray": 0xd3d3d3,
  "lightgreen": 0x90ee90,
  "lightgrey": 0xd3d3d3,
  "lightpink": 0xffb6c1,
  "lightsalmon": 0xffa07a,
  "lightseagreen": 0x20b2aa,
  "lightskyblue": 0x87cefa,
  "lightslategray": 0x778899,
  "lightslategrey": 0x778899,
  "lightsteelblue": 0xb0c4de,
  "lightyellow": 0xffffe0,
  "lime": 0x00ff00,
  "limegreen": 0x32cd32,
  "linen": 0xfaf0e6,
  "magenta": 0xff00ff,
  "maroon": 0x800000,
  "mediumaquamarine": 0x66cdaa,
  "mediumblue": 0x0000cd,
  "mediumorchid": 0xba55d3,
  "mediumpurple": 0x9370db,
  "mediumseagreen": 0x3cb371,
  "mediumslateblue": 0x7b68ee,
  "mediumspringgreen": 0x00fa9a,
  "mediumturquoise": 0x48d1cc,
  "mediumvioletred": 0xc71585,
  "midnightblue": 0x191970,
  "mintcream": 0xf5fffa,
  "mistyrose": 0xffe4e1,
  "moccasin": 0xffe4b5,
  "navajowhite": 0xffdead,
  "navy": 0x000080,
  "oldlace": 0xfdf5e6,
  "olive": 0x808000,
  "olivedrab": 0x6b8e23,
  "orange": 0xffa500,
  "orangered": 0xff4500,
  "orchid": 0xda70d6,
  "palegoldenrod": 0xeee8aa,
  "palegreen": 0x98fb98,
  "paleturquoise": 0xafeeee,
  "palevioletred": 0xdb7093,
  "papayawhip": 0xffefd5,
  "peachpuff": 0xffdab9,
  "peru": 0xcd853f,
  "pink": 0xffc0cb,
  "plum": 0xdda0dd,
  "powderblue": 0xb0e0e6,
  "purple": 0x800080,
  "rebeccapurple": 0x663399,
  "red": 0xff0000,
  "rosybrown": 0xbc8f8f,
  "royalblue": 0x4169e1,
  "saddlebrown": 0x8b4513,
  "salmon": 0xfa8072,
  "sandybrown": 0xf4a460,
  "seagreen": 0x2e8b57,
  "seashell": 0xfff5ee,
  "sienna": 0xa0522d,
  "silver": 0xc0c0c0,
  "skyblue": 0x87ceeb,
  "slateblue": 0x6a5acd,
  "slategray": 0x708090,
  "slategrey": 0x708090,
  "snow": 0xfffafa,
  "springgreen": 0x00ff7f,
  "steelblue": 0x4682b4,
  "tan": 0xd2b48c,
  "teal": 0x008080,
  "thistle": 0xd8bfd8,
  "tomato": 0xff6347,
  "turquoise": 0x40e0d0,
  "violet": 0xee82ee,
  "wheat": 0xf5deb3,
  "white": 0xffffff,
  "whitesmoke": 0xf5f5f5,
  "yellow": 0xffff00,
  "yellowgreen": 0x9acd32
}.toTable

type ChartVars* = object
  v*: Table[string, string]
  cfg*: JsonNode              ## the diagram's whole config (init directive / front matter)

proc hexDigitVal(c: char): int =
  case c
  of '0'..'9': ord(c) - ord('0')
  of 'a'..'f': ord(c) - ord('a') + 10
  of 'A'..'F': ord(c) - ord('A') + 10
  else: -1

proc hslToColor*(h, s, l: float, a: float): Color =
  let hh = ((h mod 360.0) + 360.0) mod 360.0 / 60.0
  let c = (1 - abs(2 * l - 1)) * s
  let x = c * (1 - abs(hh mod 2.0 - 1))
  var (r, g, b) = (0.0, 0.0, 0.0)
  if hh < 1: (r, g, b) = (c, x, 0.0)
  elif hh < 2: (r, g, b) = (x, c, 0.0)
  elif hh < 3: (r, g, b) = (0.0, c, x)
  elif hh < 4: (r, g, b) = (0.0, x, c)
  elif hh < 5: (r, g, b) = (x, 0.0, c)
  else: (r, g, b) = (c, 0.0, x)
  let m = l - c / 2
  proc b8(v: float): uint8 = uint8(clamp(round((v + m) * 255), 0.0, 255.0))
  rgba(b8(r), b8(g), b8(b), uint8(clamp(round(a * 255), 0.0, 255.0)))

proc parseCssColor*(s0: string): Option[Color] =
  ## #rgb #rrggbb #rrggbbaa, rgb()/rgba(), hsl()/hsla(), and the few named colours Mermaid's themes use.
  let s = s0.strip().toLowerAscii()
  if s.len == 0: return none(Color)
  if s[0] == '#':
    var d: seq[int]
    for c in s[1 .. ^1]:
      let v = hexDigitVal(c)
      if v < 0: return none(Color)
      d.add v
    case d.len
    of 3: return some(rgba(uint8(d[0] * 17), uint8(d[1] * 17), uint8(d[2] * 17)))
    of 4: return some(rgba(uint8(d[0] * 17), uint8(d[1] * 17), uint8(d[2] * 17), uint8(d[3] * 17)))
    of 6: return some(rgba(uint8(d[0] * 16 + d[1]), uint8(d[2] * 16 + d[3]), uint8(d[4] * 16 + d[5])))
    of 8: return some(rgba(uint8(d[0] * 16 + d[1]), uint8(d[2] * 16 + d[3]), uint8(d[4] * 16 + d[5]), uint8(d[6] * 16 + d[7])))
    else: return none(Color)
  if s.startsWith("rgb") or s.startsWith("hsl"):
    let o = s.find('('); let c = s.find(')')
    if o < 0 or c < o: return none(Color)
    var nums: seq[float]
    for part in s[o + 1 ..< c].replace("/", ",").split({',', ' '}):
      let p = part.strip().strip(chars = {'%'})
      if p.len == 0: continue
      try: nums.add parseFloat(p) except ValueError: return none(Color)
    if nums.len < 3: return none(Color)
    let alpha = if nums.len >= 4: nums[3] else: 1.0
    if s.startsWith("rgb"):
      return some(rgba(uint8(clamp(nums[0], 0.0, 255.0)), uint8(clamp(nums[1], 0.0, 255.0)), uint8(clamp(nums[2], 0.0, 255.0)), uint8(clamp(alpha, 0.0, 1.0) * 255)))
    return some(hslToColor(nums[0], nums[1] / 100.0, nums[2] / 100.0, alpha))
  if s in cssNamed:
    let v = cssNamed[s]
    return some(rgba(uint8((v shr 16) and 255), uint8((v shr 8) and 255), uint8(v and 255)))
  case s
  of "white": some(rgba(255, 255, 255))
  of "black": some(rgba(0, 0, 0))
  of "red": some(rgba(255, 0, 0))
  of "green": some(rgba(0, 128, 0))
  of "navy": some(rgba(0, 0, 128))
  of "grey", "gray": some(rgba(128, 128, 128))
  of "lightgrey", "lightgray": some(rgba(211, 211, 211))
  of "transparent": some(rgba(0, 0, 0, 0))
  else: none(Color)

proc chartVars*(text: string, forcedTheme = ""): ChartVars =
  ## Theme variables for `text`: the preset chosen like flowcharts do (forced > diagram > default),
  ## then the diagram's own themeVariables on top.
  let cfg = readConfig(text)
  result.cfg = cfg
  let name = if forcedTheme.len > 0: forcedTheme else: cfg.cfgStr("theme", "")
  let key = if name in themeTable: name else: "default"
  result.v = themeTable[key]
  let tv = cfg.cfgSub("themeVariables")
  for k, val in tv:
    if val.kind == JObject:               # nested group, e.g. xyChart: {plotColorPalette: ...}
      for k2, v2 in val: result.v[k & "." & k2] = (if v2.kind == JString: v2.getStr() else: $v2)
    elif val.kind == JString: result.v[k] = val.getStr()
    elif val.kind in {JInt, JFloat, JBool}: result.v[k] = $val

proc str*(cv: ChartVars, key: string, default = ""): string = cv.v.getOrDefault(key, default)

proc color*(cv: ChartVars, key: string, default: Color = rgba(0, 0, 0)): Color =
  let s = cv.v.getOrDefault(key, "")
  let p = parseCssColor(s)
  if p.isSome: p.get else: default

proc num*(cv: ChartVars, key: string, default: float): float =
  let s = cv.v.getOrDefault(key, "").strip().toLowerAscii().replace("px", "")
  try: parseFloat(s) except ValueError: default

proc palette*(cv: ChartVars, prefix: string, count: int): seq[Color] =
  ## prefix0..prefix(count-1) (e.g. "cScale", 12) or prefix1..prefixN when `oneBased` is baked into the prefix by the caller.
  for i in 0 ..< count: result.add cv.color(prefix & $i)

proc withAlpha*(c: Color, a: float): Color = rgba(c.r, c.g, c.b, uint8(clamp(a, 0.0, 1.0) * 255))

proc blendOver*(fg, bg: Color): Color =
  ## Opaque colour of `fg` (with its alpha) drawn over `bg` — keeps SVG/PNG identical without relying on group opacity.
  let a = float(fg.a) / 255.0
  rgba(uint8(round(float(fg.r) * a + float(bg.r) * (1 - a))), uint8(round(float(fg.g) * a + float(bg.g) * (1 - a))),
       uint8(round(float(fg.b) * a + float(bg.b) * (1 - a))))

proc toHsl*(c: Color): (float, float, float) =
  ## (h degrees, s 0..1, l 0..1)
  let r = float(c.r) / 255
  let g = float(c.g) / 255
  let b = float(c.b) / 255
  let mx = max(r, max(g, b))
  let mn = min(r, min(g, b))
  let l = (mx + mn) / 2
  if mx == mn: return (0.0, 0.0, l)
  let d = mx - mn
  let sat = if l > 0.5: d / (2 - mx - mn) else: d / (mx + mn)
  var h: float
  if mx == r: h = (g - b) / d + (if g < b: 6.0 else: 0.0)
  elif mx == g: h = (b - r) / d + 2
  else: h = (r - g) / d + 4
  (h * 60, sat, l)

proc lighten*(c: Color, amount: float): Color =
  ## khroma lighten(): HSL lightness + amount (percentage points)
  let (h, s, l) = toHsl(c)
  let r = hslToColor(h, s, clamp(l + amount / 100, 0.0, 1.0), 1.0)
  rgba(r.r, r.g, r.b, c.a)

proc darken*(c: Color, amount: float): Color = lighten(c, -amount)

proc isDarkColor*(c: Color): bool =
  ## khroma isDark(): perceived luminance < 0.5
  (0.2126 * float(c.r) + 0.7152 * float(c.g) + 0.0722 * float(c.b)) / 255 < 0.5
