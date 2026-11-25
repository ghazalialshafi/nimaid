## Reads theme settings from `%%{init: {...}}%%` directives and YAML front matter (`config:` block).
import std/[strutils, tables]

proc cleanVal(v: string): string =
  result = v.strip().strip(chars = {'\'', '"', ',', ' '})

proc pairsIn(blob: string): Table[string, string] =
  result = initTable[string, string]()
  for piece in blob.replace("{", "").replace("}", "").split({',', '\n'}):
    let ci = piece.find(':')
    if ci <= 0: continue
    let k = cleanVal(piece[0 ..< ci])
    let v = cleanVal(piece[ci + 1 .. ^1])
    if k.len > 0 and v.len > 0 and k.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9'}): result[k] = v

proc readThemeConfig*(raw: string): tuple[name: string, vars: Table[string, string]] =
  result.vars = initTable[string, string]()
  var blob = ""
  let t = raw.replace("\r\n", "\n")
  # front matter
  let stripped = t.strip(trailing = false)
  if stripped.startsWith("---"):
    let e = stripped.find("\n---", 3)
    if e > 0: blob.add stripped[3 ..< e] & "\n"
  # directives
  var i = 0
  while true:
    let a = t.find("%%{", i)
    if a < 0: break
    let b = t.find("}%%", a)
    if b < 0: break
    blob.add t[a + 3 ..< b] & "\n"
    i = b + 3
  if blob.len == 0: return
  # theme name: word "theme" (not themeVariables / themeCSS)
  var p = 0
  while true:
    let f = blob.find("theme", p)
    if f < 0: break
    let after = f + 5
    let nextCh = if after < blob.len: blob[after] else: ' '
    p = after
    if nextCh.isAlphaNumeric: continue
    var j = after
    while j < blob.len and blob[j] in {'\'', '"', ' ', ':'}: inc j
    var e = j
    while e < blob.len and blob[e].isAlphaNumeric: inc e
    if e > j:
      result.name = blob[j ..< e]
      break
  # theme variables
  let tv = blob.find("themeVariables")
  if tv >= 0:
    var j = blob.find(':', tv)
    if j >= 0:
      inc j
      while j < blob.len and blob[j] in {' ', '\t'}: inc j
      if j < blob.len and blob[j] == '{':
        let e = blob.find('}', j)
        result.vars = pairsIn(blob[j ..< (if e < 0: blob.len else: e)])
      else:
        # indented YAML block: following lines more indented than the key
        let lineStart = blob.rfind('\n', 0, tv) + 1
        let baseIndent = tv - lineStart
        var block2 = ""
        var ls = blob.find('\n', tv)
        while ls >= 0 and ls + 1 < blob.len:
          let nxt = ls + 1
          var e = blob.find('\n', nxt)
          if e < 0: e = blob.len
          let line = blob[nxt ..< e]
          let ind = line.len - line.strip(trailing = false).len
          if line.strip().len > 0 and ind <= baseIndent: break
          block2.add line & "\n"
          ls = if e >= blob.len: -1 else: e
        result.vars = pairsIn(block2)

# ------------------------------------------------------------------------------------------------
# Structured config (nested objects) for the chart diagrams: `%%{init: {...}}%%` and YAML front matter.
import std/json

proc skipWs(s: string, i: var int) =
  while i < s.len and s[i] in {' ', '\t', '\n', '\r'}: inc i

proc scalarNode(tok: string): JsonNode =
  let t = tok.strip()
  if t == "true": return newJBool(true)
  if t == "false": return newJBool(false)
  if t == "null" or t.len == 0: return newJNull()
  try:
    if t.allCharsInSet({'0'..'9', '-', '+'}) and t.len > 0 and t != "-" and t != "+": return newJInt(parseInt(t))
    if t.allCharsInSet({'0'..'9', '-', '+', '.', 'e', 'E'}) and t.count('.') <= 1 and t[0] in {'0'..'9', '-', '+', '.'}: return newJFloat(parseFloat(t))
  except ValueError: discard
  newJString(t)

proc parseValue(s: string, i: var int): JsonNode

proc parseString(s: string, i: var int): string =
  let q = s[i]; inc i
  while i < s.len and s[i] != q:
    if s[i] == '\\' and i + 1 < s.len: inc i
    result.add s[i]; inc i
  inc i

proc parseKey(s: string, i: var int): string =
  skipWs(s, i)
  if i < s.len and s[i] in {'"', '\''}: return parseString(s, i)
  while i < s.len and s[i] notin {':', ',', '}', '\n'}: result.add s[i]; inc i
  result = result.strip()

proc parseValue(s: string, i: var int): JsonNode =
  skipWs(s, i)
  if i >= s.len: return newJNull()
  case s[i]
  of '{':
    result = newJObject(); inc i
    while true:
      skipWs(s, i)
      if i >= s.len: break
      if s[i] == '}': inc i; break
      if s[i] == ',': inc i; continue
      let k = parseKey(s, i)
      skipWs(s, i)
      if i < s.len and s[i] == ':':
        inc i
        result[k] = parseValue(s, i)
      elif k.len == 0: inc i
  of '[':
    result = newJArray(); inc i
    while true:
      skipWs(s, i)
      if i >= s.len: break
      if s[i] == ']': inc i; break
      if s[i] == ',': inc i; continue
      result.add parseValue(s, i)
  of '"', '\'':
    result = newJString(parseString(s, i))
  else:
    var tok = ""
    while i < s.len and s[i] notin {',', '}', ']', '\n'}: tok.add s[i]; inc i
    result = scalarNode(tok)

proc mergeInto(dst: JsonNode, src: JsonNode) =
  if src.kind != JObject: return
  for k, v in src:
    if v.kind == JObject and dst.hasKey(k) and dst[k].kind == JObject: mergeInto(dst[k], v)
    else: dst[k] = v

proc parseYamlBlock(lines: seq[string]): JsonNode =
  ## minimal YAML: nested maps by indentation, `key: value`, inline {..}/[..] values.
  result = newJObject()
  var stack: seq[(int, JsonNode)] = @[(-1, result)]
  for raw in lines:
    let line = raw.replace("\t", "  ")
    let body = line.strip()
    if body.len == 0 or body.startsWith("#"): continue
    let ind = line.len - line.strip(trailing = false).len
    while stack.len > 1 and stack[^1][0] >= ind: stack.setLen(stack.len - 1)
    let ci = body.find(':')
    if ci <= 0: continue
    let k = body[0 ..< ci].strip(chars = {' ', '\'', '"'})
    let rest = body[ci + 1 .. ^1].strip()
    let parent = stack[^1][1]
    if rest.len == 0:
      let child = newJObject(); parent[k] = child; stack.add (ind, child)
    elif rest[0] in {'{', '['}:
      var j = 0; parent[k] = parseValue(rest, j)
    elif rest[0] in {'"', '\''}:
      var j = 0; parent[k] = newJString(parseString(rest, j))
    else: parent[k] = scalarNode(rest)

proc readConfig*(raw: string): JsonNode =
  ## Merged config object from YAML front matter (`config:` block) and `%%{init: {...}}%%` directives.
  ## Same shape Mermaid's own config has: {"theme": "...", "themeVariables": {...}, "xyChart": {...}, ...}.
  result = newJObject()
  let t = raw.replace("\r\n", "\n")
  let stripped = t.strip(trailing = false)
  if stripped.startsWith("---"):
    let e = stripped.find("\n---", 3)
    if e > 0:
      let y = parseYamlBlock(stripped[3 ..< e].splitLines())
      if y.hasKey("config") and y["config"].kind == JObject: mergeInto(result, y["config"])
  var i = 0
  while true:
    let a = t.find("%%{", i)
    if a < 0: break
    let b = t.find("}%%", a)
    if b < 0: break
    let body = t[a + 3 ..< b + 1]                       # includes the closing '}' of the directive object
    let colon = body.find(':')
    if colon > 0 and body[0 ..< colon].strip().toLowerAscii() in ["init", "initialize"]:
      var j = colon + 1
      let v = parseValue(body, j)
      mergeInto(result, v)
    i = b + 3

proc cfgFloat*(n: JsonNode, key: string, default: float): float =
  if n != nil and n.kind == JObject and n.hasKey(key):
    let v = n[key]
    case v.kind
    of JInt: return float(v.getInt())
    of JFloat: return v.getFloat()
    of JString:
      try: return parseFloat(v.getStr().replace("px", "")) except ValueError: discard
    else: discard
  default

proc cfgBool*(n: JsonNode, key: string, default: bool): bool =
  if n != nil and n.kind == JObject and n.hasKey(key):
    let v = n[key]
    case v.kind
    of JBool: return v.getBool()
    of JString: return v.getStr().toLowerAscii() == "true"
    else: discard
  default

proc cfgStr*(n: JsonNode, key: string, default: string): string =
  if n != nil and n.kind == JObject and n.hasKey(key) and n[key].kind in {JString, JInt, JFloat, JBool}:
    let v = n[key]
    return (if v.kind == JString: v.getStr() else: $v)
  default

proc cfgSub*(n: JsonNode, key: string): JsonNode =
  if n != nil and n.kind == JObject and n.hasKey(key) and n[key].kind == JObject: n[key] else: newJObject()
