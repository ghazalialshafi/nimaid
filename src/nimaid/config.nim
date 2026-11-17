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
