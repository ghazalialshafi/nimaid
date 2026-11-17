## State, entity-relationship and class diagrams. Each parser translates its syntax into FlowChartData,
## so layout (dagre + clusters), shapes, markers, themes and exports are shared with flowcharts.
## Line-based parsers covering the commonly used syntax (not a port of Mermaid's langium/jison grammars).
import std/[strutils, tables]
import types, flowdb

type
  DiagramParseError* = object of CatchableError

  Chart = object
    data: FlowChartData
    idx: Table[string, int]
    edgeCount: int

proc bad(msg: string) {.noreturn.} = raise newException(DiagramParseError, msg)

proc newChart(direction = "TB"): Chart =
  result.data.direction = direction

proc addNode(c: var Chart, id, label, shape: string, parent = ""): int =
  if id in c.idx: return c.idx[id]
  var n = RenderNode(id: id, label: label, labelType: flkText, parentId: parent, padding: 8,
                     shape: shape, domId: id, colorIndex: -1)
  c.data.nodes.add n
  c.idx[id] = c.data.nodes.len - 1
  c.idx[id]

proc addEdge(c: var Chart, a, b: string, label = "", startMk = "none", endMk = "arrow_point",
             dotted = false) =
  inc c.edgeCount
  c.data.edges.add RenderEdge(
    id: "e" & $c.edgeCount, source: a, target: b, label: label, labelType: flkText,
    stroke: (if dotted: fesDotted else: fesNormal), minlen: 1,
    arrowTypeStart: startMk, arrowTypeEnd: endMk)

proc unq(s: string): string =
  let t = s.strip()
  if t.len >= 2 and t[0] == '"' and t[^1] == '"': t[1 ..< t.len - 1] else: t

proc cleanLines(text: string): seq[string] =
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    l = l.strip()
    if l.len > 0: result.add l

proc dirOf(v: string): string =
  case v.strip().toUpperAscii
  of "LR": "LR"
  of "RL": "RL"
  of "BT": "BT"
  else: "TB"

# ===========================================================================
# state diagram
# ===========================================================================
proc parseStateChart*(text: string): FlowChartData =
  var c = newChart()
  var scope: seq[string]
  var descs = initTable[string, seq[string]]()
  var names = initTable[string, string]()
  var noteN = 0
  proc cur(): string = (if scope.len > 0: scope[^1] else: "")
  proc scopeName(): string = (if scope.len > 0: scope[^1] else: "root")
  proc ensure(id: string): string =
    discard c.addNode(id, id, "roundedRect", cur())
    id
  proc endpoint(tok: string, isSource: bool): string =
    let t = tok.strip()
    if t == "[*]":
      let id = scopeName() & (if isSource: "_start" else: "_end")
      discard c.addNode(id, "", (if isSource: "stateStart" else: "stateEnd"), cur())
      return id
    ensure(t)
  var lines = cleanLines(text)
  var started = false
  var i = 0
  while i < lines.len:
    let l = lines[i]
    inc i
    let low = l.toLowerAscii
    if not started:
      if low.startsWith("statediagram"): started = true; continue
      bad("Parse error: expecting 'stateDiagram'")
    if low.startsWith("direction "): c.data.direction = dirOf(l[10 .. ^1]); continue
    if low.startsWith("title "): c.data.title = l[6 .. ^1].strip(); continue
    if low.startsWith("classdef ") or low.startsWith("class ") or low.startsWith("style ") or low == "--" or
       low.startsWith("scale ") or low.startsWith("hide ") or low.startsWith("if ") or low.startsWith("else") or
       low == "endif" or low.startsWith("-->[") or low.startsWith("accdescr") or low.startsWith("acctitle") or
       low.startsWith("click "): continue
    if l == "}":
      if scope.len > 0: scope.setLen(scope.len - 1)
      continue
    if low.startsWith("note "):
      var r = l[5 .. ^1].strip()
      let rl = r.toLowerAscii
      var side = "right"
      if rl.startsWith("left of "): side = "left"; r = r[8 .. ^1]
      elif rl.startsWith("right of "): r = r[9 .. ^1]
      else: continue
      var target = r
      var body = ""
      let ci = r.find(':')
      if ci >= 0:
        target = r[0 ..< ci].strip()
        body = r[ci + 1 .. ^1].strip()
      else:
        target = r.strip()
        var parts: seq[string]
        while i < lines.len and lines[i].toLowerAscii != "end note":
          parts.add lines[i]
          inc i
        inc i
        body = parts.join("\n")
      discard ensure(target)
      inc noteN
      let nid = "note" & $noteN
      let ni = c.addNode(nid, body, "squareRect", cur())
      c.data.nodes[ni].styles = @["fill:#fff5ad", "stroke:#aaaa33"]
      c.addEdge(target, nid, "", "none", "none", dotted = true)
      continue
    if low.startsWith("state "):
      var r = l[6 .. ^1].strip()
      var composite = false
      if r.endsWith("{"):
        composite = true
        r = r[0 ..< r.len - 1].strip()
      var id = r
      var disp = ""
      if r.startsWith("\""):
        let q = r.find('"', 1)
        disp = r[1 ..< q]
        let asIdx = r.toLowerAscii.find(" as ", q)
        if asIdx < 0: bad("Parse error: state \"...\" needs 'as id'")
        id = r[asIdx + 4 .. ^1].strip()
      var shape = "roundedRect"
      let lt = id.find("<<")
      if lt >= 0:
        let kind = id[lt + 2 ..< id.find(">>")].toLowerAscii
        id = id[0 ..< lt].strip()
        shape = (if kind == "choice": "choice" else: "forkJoin")
      let ni = c.addNode(id, id, shape, cur())
      if shape != "roundedRect": c.data.nodes[ni].shape = shape
      if disp.len > 0: names[id] = disp
      if composite:
        c.data.nodes[ni].isGroup = true
        c.data.nodes[ni].shape = "rect"
        scope.add id
      continue
    let arrow = l.find("-->")
    if arrow >= 0:
      let a = endpoint(l[0 ..< arrow], true)
      var rest = l[arrow + 3 .. ^1]
      var label = ""
      let ci = rest.find(':')
      if ci >= 0:
        label = rest[ci + 1 .. ^1].strip()
        rest = rest[0 ..< ci]
      let b = endpoint(rest, false)
      c.addEdge(a, b, label)
      continue
    let ci = l.find(':')
    if ci > 0:
      let id = ensure(l[0 ..< ci].strip())
      descs.mgetOrPut(id, @[]).add l[ci + 1 .. ^1].strip()
      continue
    if l.endsWith("{"):
      let id = l[0 ..< l.len - 1].strip()
      let ni = c.addNode(id, id, "rect", cur())
      c.data.nodes[ni].isGroup = true
      c.data.nodes[ni].shape = "rect"
      scope.add id
      continue
    discard ensure(l)
  if not started: bad("Parse error: expecting 'stateDiagram'")
  for k, ix in c.idx:
    var n = addr c.data.nodes[ix]
    if n.shape == "roundedRect" or n.isGroup:
      let nm = names.getOrDefault(k, k)
      n.label = nm
      if k in descs and not n.isGroup: n.label = nm & "\n" & descs[k].join("\n")
    if n.isGroup: n.shape = "rect"
  c.data

# ===========================================================================
# entity-relationship diagram
# ===========================================================================
proc erMarker(tok: string): string =
  case tok
  of "||": "er_one"
  of "|o", "o|": "er_zero_one"
  of "}|", "|{": "er_many"
  of "}o", "o{": "er_zero_many"
  else: ""

proc parseErChart*(text: string): FlowChartData =
  var c = newChart()
  var started = false
  var curEntity = ""
  var rows = initTable[string, seq[seq[string]]]()
  proc entity(name: string): string =
    var id = name.strip()
    var label = id
    let br = id.find('[')
    if br > 0 and id.endsWith("]"):
      label = unq(id[br + 1 ..< id.len - 1])
      id = id[0 ..< br].strip()
    let ni = c.addNode(id, label, "squareRect")
    c.data.nodes[ni].box = BoxSpec(kind: "er", title: label)
    if label != id: c.data.nodes[ni].box.title = label
    id
  for l in cleanLines(text):
    let low = l.toLowerAscii
    if not started:
      if low.startsWith("erdiagram"): started = true; continue
      bad("Parse error: expecting 'erDiagram'")
    if curEntity.len > 0:
      if l == "}":
        curEntity = ""
        continue
      # attribute: type name [keys] ["comment"]
      var comment = ""
      var body = l
      let q = l.find('"')
      if q >= 0:
        comment = l[q ..< l.len].strip(chars = {'"', ' '})
        body = l[0 ..< q]
      let toks = body.splitWhitespace()
      if toks.len < 2: bad("Parse error: bad attribute '" & l & "'")
      rows.mgetOrPut(curEntity, @[]).add @[toks[0], toks[1], toks[2 .. ^1].join(" ").replace(" ", ","), comment]
      continue
    if low.startsWith("direction "): c.data.direction = dirOf(l[10 .. ^1]); continue
    if low.startsWith("title "): c.data.title = l[6 .. ^1].strip(); continue
    if l.endsWith("{"):
      curEntity = entity(l[0 ..< l.len - 1])
      continue
    # relationship  A ||--o{ B : label
    var opAt = -1
    var q = false
    for k in 0 ..< l.len - 1:
      if l[k] == '"': q = not q
      if not q and ((l[k] == '-' and l[k + 1] == '-') or (l[k] == '.' and l[k + 1] == '.')) and k >= 2 and k + 3 < l.len:
        if erMarker(l[k - 2 .. k - 1]).len > 0 and erMarker(l[k + 2 .. k + 3]).len > 0:
          opAt = k
          break
    if opAt >= 0:
      let left = l[0 ..< opAt - 2]
      let lm = erMarker(l[opAt - 2 .. opAt - 1])
      let rm = erMarker(l[opAt + 2 .. opAt + 3])
      var rest = l[opAt + 4 .. ^1]
      var label = ""
      let ci = rest.find(':')
      if ci >= 0:
        label = unq(rest[ci + 1 .. ^1])
        rest = rest[0 ..< ci]
      let a = entity(left)
      let b = entity(rest)
      c.addEdge(a, b, label, lm, rm, dotted = (l[opAt] == '.'))
    else:
      discard entity(l)   # bare entity declaration
  if not started: bad("Parse error: expecting 'erDiagram'")
  for k, ix in c.idx:
    var sec: seq[seq[string]]
    var r = rows.getOrDefault(k)
    # drop empty trailing columns consistently
    var hasKeys = false
    var hasCom = false
    for row in r:
      if row[2].len > 0: hasKeys = true
      if row[3].len > 0: hasCom = true
    for row in r:
      var cells = @[row[0], row[1]]
      if hasKeys or hasCom: cells.add row[2]
      if hasCom: cells.add row[3]
      sec.add cells
    c.data.nodes[ix].box.sections = @[sec]
  c.data

# ===========================================================================
# class diagram
# ===========================================================================
proc genericText(s: string): string =
  ## Foo~T~ -> Foo<T>
  var r = s
  let a = r.find('~')
  if a >= 0:
    let b = r.find('~', a + 1)
    if b > a: r = r[0 ..< a] & "<" & r[a + 1 ..< b] & ">" & r[b + 1 .. ^1]
  r

proc classEnds(op: string): (string, string, bool, bool) =
  ## (startMarker, endMarker, dotted, valid)
  var s = "none"
  var e = "none"
  let dotted = ".." in op
  var core = op
  if core.startsWith("<|"): s = "extension"; core = core[2 .. ^1]
  elif core.startsWith("*"): s = "composition"; core = core[1 .. ^1]
  elif core.startsWith("o"): s = "aggregation"; core = core[1 .. ^1]
  elif core.startsWith("<"): s = "arrow_point"; core = core[1 .. ^1]
  elif core.startsWith("()"): s = "lollipop"; core = core[2 .. ^1]
  if core.endsWith("|>"): e = "extension"; core = core[0 ..< core.len - 2]
  elif core.endsWith("*"): e = "composition"; core = core[0 ..< core.len - 1]
  elif core.endsWith("o"): e = "aggregation"; core = core[0 ..< core.len - 1]
  elif core.endsWith(">"): e = "arrow_point"; core = core[0 ..< core.len - 1]
  elif core.endsWith("()"): e = "lollipop"; core = core[0 ..< core.len - 2]
  (s, e, dotted, core == "--" or core == "..")

proc parseClassChart*(text: string): FlowChartData =
  var c = newChart()
  var started = false
  var members = initTable[string, seq[string]]()
  var annot = initTable[string, string]()
  var labels = initTable[string, string]()
  var curBody = ""
  proc cls(name: string): string =
    var id = name.strip()
    var label = ""
    let br = id.find('[')
    if br > 0 and id.endsWith("]"):
      label = unq(id[br + 1 ..< id.len - 1])
      id = id[0 ..< br].strip()
    let tl = id.find('~')
    if tl > 0:                       # Shelter~T~ is the generic form of Shelter
      let gen = genericText(id)
      id = id[0 ..< tl]
      if label.len == 0: label = gen
    let ni = c.addNode(id, id, "squareRect")
    c.data.nodes[ni].box = BoxSpec(kind: "class")
    if label.len > 0: labels[id] = label
    id
  proc addMember(id, m: string) =
    let t = m.strip()
    if t.len == 0: return
    if t.startsWith("<<") and t.endsWith(">>"): annot[id] = "«" & t[2 ..< t.len - 2] & "»"
    else: members.mgetOrPut(id, @[]).add genericText(t)
  for l in cleanLines(text):
    let low = l.toLowerAscii
    if not started:
      if low.startsWith("classdiagram"): started = true; continue
      bad("Parse error: expecting 'classDiagram'")
    if curBody.len > 0:
      if l == "}": curBody = ""
      else: addMember(curBody, l)
      continue
    if low.startsWith("direction "): c.data.direction = dirOf(l[10 .. ^1]); continue
    if low.startsWith("title "): c.data.title = l[6 .. ^1].strip(); continue
    if low.startsWith("note ") or low.startsWith("classdef ") or low.startsWith("style ") or
       low.startsWith("namespace ") or l == "}": continue
    if low.startsWith("class "):
      var r = l[6 .. ^1].strip()
      let opens = r.endsWith("{")
      if opens: r = r[0 ..< r.len - 1].strip()
      let id = cls(r)
      if opens: curBody = id
      continue
    if l.startsWith("<<"):
      let e = l.find(">>")
      if e > 0:
        let id = cls(l[e + 2 .. ^1])
        annot[id] = "«" & l[2 ..< e] & "»"
      continue
    # relation: A ["1"] <op> ["*"] B [: label]
    let toks = l.splitWhitespace()
    var opI = -1
    for k, t in toks:
      if k > 0 and t.len >= 2 and t.allCharsInSet({'<', '>', '|', '*', 'o', '.', '-', '(', ')'}) and ('-' in t or ".." in t):
        let (_, _, _, ok) = classEnds(t)
        if ok:
          opI = k
          break
    if opI > 0 and opI < toks.len - 1:
      var aTok = toks[0]
      var bIdx = opI + 1
      if toks[opI + 1].startsWith("\""): inc bIdx
      let a = cls(aTok)
      let b = cls(toks[min(bIdx, toks.len - 1)])
      var label = ""
      let ci = l.find(" : ")
      if ci >= 0: label = unq(l[ci + 3 .. ^1])
      let (sm, em, dotted, _) = classEnds(toks[opI])
      c.addEdge(a, b, label, sm, em, dotted)
      continue
    let ci = l.find(" : ")
    let ci2 = if ci >= 0: ci else: l.find(':')
    if ci2 > 0:
      let id = cls(l[0 ..< ci2])
      addMember(id, l[ci2 + (if ci >= 0: 3 else: 1) .. ^1])
      continue
    discard cls(l)
  if not started: bad("Parse error: expecting 'classDiagram'")
  for k, ix in c.idx:
    var attrs: seq[seq[string]]
    var meths: seq[seq[string]]
    for m in members.getOrDefault(k):
      if '(' in m: meths.add @[m] else: attrs.add @[m]
    var b = BoxSpec(kind: "class", title: genericText(labels.getOrDefault(k, k)), annotation: annot.getOrDefault(k))
    b.sections = @[attrs, meths]
    c.data.nodes[ix].box = b
  c.data
