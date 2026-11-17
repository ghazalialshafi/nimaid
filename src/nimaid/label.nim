import std/strutils

type
  TextMeasureProc* = proc(text: string, fontSize: float32, isTitle: bool): tuple[w, h: float32] {.closure.}

var activeMeasurer*: TextMeasureProc = nil   ## set by textmetrics.initTextMetrics (PureVG-backed)

proc setTextMeasurer*(m: TextMeasureProc) = activeMeasurer = m

proc labelText*(s: string): string =
  ## Normalises mermaid label markup: <br>, <br/>, <br /> and literal "\n" become real newlines.
  result = s
  for tag in ["<br/>", "<br />", "<br>", "<BR/>", "<BR>", "\\n"]:
    result = result.replace(tag, "\n")

proc defaultEstimateText(text: string, fontSize: float32 = 16.0): tuple[w, h: float32] =
  let lines = text.splitLines()
  var maxLen = 0
  for line in lines:
    if line.len > maxLen:
      maxLen = line.len
  let lineCount = max(1, lines.len)
  (float32(maxLen) * (fontSize * 0.6), float32(lineCount) * (fontSize * 1.25))

proc measureLabel*(
  text: string,
  fontSize: float32 = 16.0,
  isTitle = false,
  isNode = false,
  customMeasure: TextMeasureProc = nil
): tuple[w, h: float32] =
  let t = labelText(text)
  if t.strip().len == 0:
    return (0.0'f32, 0.0'f32)
  if not customMeasure.isNil:
    return customMeasure(t, fontSize, isTitle)
  if not activeMeasurer.isNil:
    return activeMeasurer(t, fontSize, isTitle)
  defaultEstimateText(t, fontSize)

const edgeLabelFontSize* = 12.0'f32

proc edgeLabelSize*(label: string): tuple[w, h: float] =
  ## Size of the badge behind an edge label (text + padding).
  let m = measureLabel(label, edgeLabelFontSize)
  (float(m.w) + 8.0, float(m.h) + 4.0)

# ---------------------------------------------------------------------------
# label preparation: entities, markdown, wrapping
# ---------------------------------------------------------------------------
import std/tables
import std/unicode except splitWhitespace

const namedEntities = {
  "quot": 0x22, "amp": 0x26, "apos": 0x27, "lt": 0x3C, "gt": 0x3E, "nbsp": 0xA0, "copy": 0xA9,
  "reg": 0xAE, "trade": 0x2122, "hellip": 0x2026, "mdash": 0x2014, "ndash": 0x2013, "laquo": 0xAB,
  "raquo": 0xBB, "larr": 0x2190, "rarr": 0x2192, "uarr": 0x2191, "darr": 0x2193, "harr": 0x2194,
  "hearts": 0x2665, "spades": 0x2660, "clubs": 0x2663, "diams": 0x2666, "check": 0x2713, "times": 0xD7,
  "divide": 0xF7, "deg": 0xB0, "plusmn": 0xB1, "euro": 0x20AC, "pound": 0xA3, "yen": 0xA5, "cent": 0xA2,
  "sect": 0xA7, "para": 0xB6, "middot": 0xB7, "bull": 0x2022, "lsquo": 0x2018, "rsquo": 0x2019,
  "ldquo": 0x201C, "rdquo": 0x201D, "infin": 0x221E, "ne": 0x2260, "le": 0x2264, "ge": 0x2265,
  "alpha": 0x3B1, "beta": 0x3B2, "gamma": 0x3B3, "delta": 0x3B4, "pi": 0x3C0, "sigma": 0x3C3,
  "omega": 0x3C9, "mu": 0x3BC, "lambda": 0x3BB, "star": 0x2606, "phone": 0x260E,
}.toTable

proc decodeEntities*(s: string): string =
  ## Mermaid entity syntax: #quot;  #9829;  #x2665;   (also plain &amp; style entities)
  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '#' or c == '&':
      let semi = s.find(';', i + 1)
      if semi > i + 1 and semi - i <= 10:
        var body = s.substr(i + 1, semi - 1)
        var cp = -1
        if body.len > 0 and body[0] == '#': body = body[1 .. ^1]   # &#9829;
        if body.len > 0 and body.allCharsInSet({'0'..'9'}):
          cp = parseInt(body)
        elif body.len > 1 and body[0] in {'x', 'X'} and body[1 .. ^1].allCharsInSet(HexDigits):
          cp = parseHexInt(body[1 .. ^1])
        elif body in namedEntities:
          cp = namedEntities[body]
        if cp > 0 and cp < 0x110000:
          result.add $Rune(cp)
          i = semi + 1
          continue
    result.add c
    inc i

proc stripMarkdown*(s: string): string =
  ## Removes emphasis markers (**bold**, __bold__, *italic*, _italic_) from paired spans.
  proc pairs(t: string, m: string): string =
    result = ""
    var i = 0
    while i < t.len:
      if t.continuesWith(m, i):
        let j = t.find(m, i + m.len)
        if j > i + m.len and t[i + m.len] notin {' ', '\n'} and t[j - 1] notin {' ', '\n'}:
          result.add t.substr(i + m.len, j - 1)
          i = j + m.len
          continue
      result.add t[i]
      inc i
  result = pairs(pairs(pairs(pairs(s, "**"), "__"), "*"), "_")
  # underscores inside words stay literal (snake_case): re-check simple case
  if s.find('_') >= 0 and result != s:
    discard

proc wrapLabel*(text: string, maxWidth: float, fontSize: float32): string =
  ## Greedy word wrap like the browser does for mermaid's 200px label boxes.
  var lines: seq[string]
  for para in text.split('\n'):
    if float(measureLabel(para, fontSize).w) <= maxWidth or ' ' notin para:
      lines.add para
      continue
    var cur = ""
    for w in para.splitWhitespace():
      let cand = if cur.len == 0: w else: cur & " " & w
      if cur.len > 0 and float(measureLabel(cand, fontSize).w) > maxWidth:
        lines.add cur
        cur = w
      else:
        cur = cand
    if cur.len > 0: lines.add cur
  lines.join("\n")

const wrappingWidth* = 200.0

proc prepLabel*(text: string, markdown = false, wrap = true, fontSize: float32 = 16.0): string =
  ## Applied to node / edge labels before measuring: entities -> chars, markdown markers removed, wrapped.
  result = labelText(text)
  result = decodeEntities(result)
  if markdown: result = stripMarkdown(result)
  if wrap: result = wrapLabel(result, wrappingWidth, fontSize)
