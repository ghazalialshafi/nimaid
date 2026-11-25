## Treemap diagrams (Mermaid `treemap` / `treemap-beta`): treemap.langium + db/utils (hierarchy) + renderer.ts.
## Includes d3-hierarchy's squarified treemap tiling (paddingInner/Top/Left/Right/Bottom, round) and d3 ordinal colour scales.
import std/[strutils, math, options, json, tables, algorithm]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  Node = ref object
    name, cls: string
    isLeaf: bool
    own: float                   ## declared leaf value
    value: float                 ## d3 sum
    kids: seq[Node]
    parent: Node
    depth: int
    x0, y0, x1, y1: float
    styles: Table[string, string]

  Scale = object
    names: seq[string]
    palette: seq[Color]

proc pick(s: var Scale, name: string): Color =
  var i = s.names.find(name)
  if i < 0: s.names.add name; i = s.names.high
  s.palette[i mod s.palette.len]

proc parseStyleText(t: string): Table[string, string] =
  for part in t.replace("\\,", "\x01").split({',', ';'}):
    let ci = part.find(':')
    if ci > 0: result[part[0 ..< ci].strip()] = part[ci + 1 .. ^1].strip().replace("\x01", ",")

proc parseTreemap(text, fmTitle: string): (string, Node) =
  var title = fmTitle
  let root = Node(name: "")
  var stack: seq[(Node, int)]
  var classes = initTable[string, Table[string, string]]()
  var started = false
  var items: seq[(int, Node)]
  for rawLine in text.replace("\r\n", "\n").split('\n'):
    var l = rawLine.replace("\t", "    ")
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    if l.strip().len == 0: continue
    let indent = l.len - l.strip(trailing = false).len
    let t = l.strip()
    if not started:
      if not t.toLowerAscii.startsWith("treemap"): raise newException(ChartError, "Parse error: expecting 'treemap'")
      started = true; continue
    if t.toLowerAscii.startsWith("title"): title = t[5 .. ^1].strip(); continue
    if t.toLowerAscii.startsWith("acctitle") or t.toLowerAscii.startsWith("accdescr"): continue
    if t.startsWith("classDef"):
      let rest = t[8 .. ^1].strip()
      let sp = rest.find({' ', '\t'})
      if sp > 0: classes[rest[0 ..< sp]] = parseStyleText(rest[sp .. ^1])
      continue
    if t[0] notin {'"', '\''}: raise newException(ChartError, "Parse error: a treemap row is '\"Name\"' or '\"Name\": value', got '" & t & "'")
    let q = t[0]
    let e = t.find(q, 1)
    if e < 0: raise newException(ChartError, "Parse error: unterminated name in '" & t & "'")
    let name = t[1 ..< e]
    var rest = t[e + 1 .. ^1].strip()
    var cls = ""
    let ci = rest.find(":::")
    if ci >= 0: cls = rest[ci + 3 .. ^1].strip(); rest = rest[0 ..< ci].strip()
    let n = Node(name: name, cls: cls)
    if rest.len > 0:
      if rest[0] notin {':', ','}: raise newException(ChartError, "Parse error: expecting ':' before the value of \"" & name & "\"")
      n.isLeaf = true
      try: n.own = parseFloat(rest[1 .. ^1].strip().replace(",", "").replace("_", ""))
      except ValueError: raise newException(ChartError, "Parse error: \"" & name & "\" has an invalid value")
    items.add (indent, n)
  for (_, n) in items:                       # classDef may come after the nodes that use it
    if n.cls in classes: n.styles = classes[n.cls]
  # buildHierarchy
  for (level, n) in items:
    while stack.len > 0 and stack[^1][1] >= level: stack.setLen(stack.len - 1)
    let parent = if stack.len == 0: root else: stack[^1][0]
    n.parent = parent
    parent.kids.add n
    if not n.isLeaf: stack.add (n, level)
  (title, root)

# ---------------------------------------------------------------- d3-hierarchy
proc sumAndSort(n: Node) =
  for k in n.kids: sumAndSort(k)
  if n.kids.len == 0: n.value = n.own
  else:
    n.value = 0
    for k in n.kids: n.value += k.value
    n.kids.sort(proc(a, b: Node): int = cmp(b.value, a.value))    # stable, descending

proc setDepth(n: Node, d: int) =
  n.depth = d
  for k in n.kids: setDepth(k, d + 1)

proc dice(kids: seq[Node], v, x0, y0, x1, y1: float) =
  let k = if v != 0: (x1 - x0) / v else: 0.0
  var x = x0
  for n in kids: n.y0 = y0; n.y1 = y1; n.x0 = x; x += n.value * k; n.x1 = x

proc slice(kids: seq[Node], v, x0, y0, x1, y1: float) =
  let k = if v != 0: (y1 - y0) / v else: 0.0
  var y = y0
  for n in kids: n.x0 = x0; n.x1 = x1; n.y0 = y; y += n.value * k; n.y1 = y

proc squarify(parent: Node, x0a, y0a, x1a, y1a: float) =
  let ratio = (1 + sqrt(5.0)) / 2
  var x0 = x0a
  var y0 = y0a
  var x1 = x1a
  var y1 = y1a
  let nodes = parent.kids
  let n = nodes.len
  var value = parent.value
  var i0 = 0
  var i1 = 0
  while i0 < n:
    let dx = x1 - x0
    let dy = y1 - y0
    var sumValue = 0.0
    while true:
      sumValue = nodes[i1].value; inc i1
      if sumValue != 0 or i1 >= n: break
    var minValue = sumValue
    var maxValue = sumValue
    let alpha = max(dy / dx, dx / dy) / (value * ratio)
    var beta = sumValue * sumValue * alpha
    var minRatio = max(maxValue / beta, beta / minValue)
    while i1 < n:
      let nodeValue = nodes[i1].value
      sumValue += nodeValue
      if nodeValue < minValue: minValue = nodeValue
      if nodeValue > maxValue: maxValue = nodeValue
      beta = sumValue * sumValue * alpha
      let newRatio = max(maxValue / beta, beta / minValue)
      if newRatio > minRatio: sumValue -= nodeValue; break
      minRatio = newRatio
      inc i1
    let row = nodes[i0 ..< i1]
    if dx < dy:
      let ny = if value != 0: y0 + dy * sumValue / value else: y1
      dice(row, sumValue, x0, y0, x1, ny)
      y0 = ny
    else:
      let nx = if value != 0: x0 + dx * sumValue / value else: x1
      slice(row, sumValue, x0, y0, nx, y1)
      x0 = nx
    value -= sumValue
    i0 = i1

proc layout(root: Node, W, H, paddingInner: float, headerTop, pad: float) =
  var paddingStack = @[0.0]
  proc position(n: Node) =
    while paddingStack.len <= n.depth + 1: paddingStack.add 0.0
    var p = paddingStack[n.depth]
    var x0 = n.x0 + p
    var y0 = n.y0 + p
    var x1 = n.x1 - p
    var y1 = n.y1 - p
    if x1 < x0: x0 = (x0 + x1) / 2; x1 = x0
    if y1 < y0: y0 = (y0 + y1) / 2; y1 = y0
    n.x0 = x0; n.y0 = y0; n.x1 = x1; n.y1 = y1
    if n.kids.len > 0:
      p = paddingInner / 2
      paddingStack[n.depth + 1] = p
      x0 += pad - p; y0 += headerTop - p; x1 -= pad - p; y1 -= pad - p
      if x1 < x0: x0 = (x0 + x1) / 2; x1 = x0
      if y1 < y0: y0 = (y0 + y1) / 2; y1 = y0
      squarify(n, x0, y0, x1, y1)
      for k in n.kids: position(k)
  root.x0 = 0; root.y0 = 0; root.x1 = W; root.y1 = H
  position(root)
  proc rnd(n: Node) =
    n.x0 = floor(n.x0 + 0.5); n.y0 = floor(n.y0 + 0.5); n.x1 = floor(n.x1 + 0.5); n.y1 = floor(n.y1 + 0.5)
    for k in n.kids: rnd(k)
  rnd(root)

# ---------------------------------------------------------------- value formatting (d3-format subset)
proc group(intPart: string): string =
  var s = intPart
  var neg = false
  if s.startsWith("-"): neg = true; s = s[1 .. ^1]
  var o = ""
  for i, c in s:
    if i > 0 and (s.len - i) mod 3 == 0: o.add ','
    o.add c
  (if neg: "-" else: "") & o

proc fmtValue(v: float, spec: string): string =
  var sp = spec
  var prefix = ""
  if sp.startsWith("$"): prefix = "$"; sp = sp[1 .. ^1]
  let comma = ',' in sp
  var decimals = -1
  let di = sp.find('.')
  if di >= 0:
    var j = di + 1
    var num = ""
    while j < sp.len and sp[j] in {'0' .. '9'}: num.add sp[j]; inc j
    if num.len > 0: decimals = parseInt(num)
  var s: string
  if decimals >= 0 and sp.endsWith("f"): s = formatFloat(v, ffDecimal, decimals)
  else:
    s = formatFloat(v, ffDecimal, 10)
    # 6 significant digits, trailing zeros trimmed (d3 default precision for the empty type)
    let mag = if v == 0: 0 else: int(floor(log10(abs(v))))
    let dec = max(0, 5 - mag)
    s = formatFloat(v, ffDecimal, min(dec, 10))
    if '.' in s: s = s.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  let dot = s.find('.')
  let ip = if dot < 0: s else: s[0 ..< dot]
  let fp = if dot < 0: "" else: s[dot .. ^1]
  prefix & (if comma or spec.len == 0: group(ip) else: ip) & fp

proc treemapScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let (title, root) = parseTreemap(text, fmTitle)
  if root.kids.len == 0: raise newException(ChartError, "Treemap has no data")
  let tc = cv.cfg.cfgSub("treemap")
  const HeaderH = 25.0
  const InnerPad = 10.0
  let padding = tc.cfgFloat("padding", 10)
  let W = tc.cfgFloat("nodeWidth", 100) * InnerPad
  let H = tc.cfgFloat("nodeHeight", 40) * InnerPad
  let showValues = tc.cfgBool("showValues", true)
  let valueFormat = tc.cfgStr("valueFormat", ",")
  let titleH = if title.len > 0: 30.0 else: 0.0
  let root0 = root
  setDepth(root0, 0)
  sumAndSort(root0)
  layout(root0, W, H, padding, HeaderH + InnerPad, InnerPad)

  var fillScale = Scale(palette: @[rgba(0, 0, 0, 0)])
  var peerScale = Scale(palette: @[rgba(0, 0, 0, 0)])
  var labelScale = Scale()
  for i in 0 .. 11:
    fillScale.palette.add cv.color("cScale" & $i)
    peerScale.palette.add cv.color("cScalePeer" & $i)
    labelScale.palette.add cv.color("cScaleLabel" & $i)

  var branches: seq[Node]
  var leaves: seq[Node]
  proc walk(n: Node) =
    if n.kids.len > 0: branches.add n else: leaves.add n
    for k in n.kids: walk(k)
  walk(root0)

  let sc = pvg_scene_new()
  let root1 = pvg_scene_new()
  discard pvg_paint_translate(sc, 0, cfloat(titleH))
  discard pvg_scene_add(root1, sc)
  if title.len > 0:
    drawT(root1, title, W / 2, titleH / 2, 14, cv.color("titleColor"), vMiddle, aMiddle)

  # sections: fill/peer in node order (the root consumes the 'transparent' slot), then labels
  var secFill, secPeer: seq[Color]
  for b in branches:
    secFill.add pick(fillScale, b.name)
    secPeer.add pick(peerScale, b.name)
  var secLabel: seq[Color]
  for b in branches: secLabel.add (if b.depth == 0: rgba(0, 0, 0) else: pick(labelScale, b.name))
  for bi, b in branches:
    if b.depth == 0: continue
    let w = b.x1 - b.x0
    var fill = withAlpha(secFill[bi], 0.6)
    var stroke = withAlpha(secPeer[bi], 0.4)
    var sw = 2.0
    if "fill" in b.styles:
      let c = parseCssColor(b.styles["fill"]); if c.isSome: fill = c.get
    if "stroke" in b.styles:
      let c = parseCssColor(b.styles["stroke"]); if c.isSome: stroke = c.get
    if "stroke-width" in b.styles:
      try: sw = parseFloat(b.styles["stroke-width"].replace("px", "")) except ValueError: discard
    kRect(sc, b.x0, b.y0, w, b.y1 - b.y0, some(fill), some(stroke), sw)
    # header label with ellipsis
    var avail: float
    if showValues and b.value != 0: avail = (w - 10) - 30 - 10 - 6
    else: avail = w - 6 - 6
    avail = max(15.0, avail)
    var label = b.name
    if textW(label, 12) > avail:
      var cur = label
      var done = false
      while cur.len > 0 and not done:
        cur = label[0 ..< cur.len - 1]
        if cur.len == 0:
          label = (if textW("...", 12) > avail: "" else: "...")
          done = true
        else:
          label = cur & "..."
          if textW(label, 12) <= avail: done = true
    var lc = secLabel[bi]
    if "color" in b.styles:
      let c = parseCssColor(b.styles["color"]); if c.isSome: lc = c.get
    drawT(sc, label, b.x0 + 6, b.y0 + HeaderH / 2, 12, lc, vMiddle, aStart)
    if showValues and b.value != 0:
      drawT(sc, fmtValue(b.value, valueFormat), b.x0 + w - 10, b.y0 + HeaderH / 2, 10, lc, vMiddle, aEnd)

  # leaves
  let complex = leaves.len > 20
  let baseLabel = if complex: 16.0 else: 38.0
  let baseValue = if complex: 14.0 else: 28.0
  let minLabel = if complex: 4.0 else: 8.0
  let minValue = if complex: 4.0 else: 6.0
  let lpad = if complex: 2.0 else: 4.0
  let minDisplay = if complex: 8.0 else: 10.0
  let gap = if complex: 1.0 else: 2.0
  for l in leaves:
    let w = l.x1 - l.x0
    let h = l.y1 - l.y0
    let parentName = if l.parent != nil: l.parent.name else: l.name
    let base = pick(fillScale, parentName)
    var fill = withAlpha(base, 0.3)
    var stroke = base
    if "fill" in l.styles:
      let c = parseCssColor(l.styles["fill"]); if c.isSome: fill = c.get
    if "stroke" in l.styles:
      let c = parseCssColor(l.styles["stroke"]); if c.isSome: stroke = c.get
    kRect(sc, l.x0, l.y0, w, h, some(fill), some(stroke), 3)
    var lc = pick(labelScale, l.name)
    if "color" in l.styles:
      let c = parseCssColor(l.styles["color"]); if c.isSome: lc = c.get
    let availW = w - 2 * lpad
    let availH = h - 2 * lpad
    if availW < minDisplay or availH < minDisplay: continue
    var fs = baseLabel
    while textW(l.name, fs) > availW and fs > minLabel: fs -= 1
    var vfs = max(minValue, min(baseValue, round(fs * 0.6)))
    var combined = fs + gap + vfs
    while combined > availH and fs > minLabel:
      fs -= 1
      vfs = max(minValue, min(baseValue, round(fs * 0.6)))
      if vfs < minValue and fs == minLabel: break
      combined = fs + gap + vfs
    var hide = false
    if complex: hide = fs < minLabel or availH < minLabel
    else: hide = textW(l.name, fs) > availW or fs < minLabel or availH < fs
    if hide: continue
    drawT(sc, l.name, l.x0 + w / 2, l.y0 + h / 2, fs, lc, vMiddle, aMiddle)
    if showValues and l.value != 0:
      let valueTop = h / 2 + fs / 2 + gap
      let vs = fmtValue(l.value, valueFormat)
      if not (textW(vs, vfs) > w - 2 * lpad or valueTop + vfs > h - 4):
        drawT(sc, vs, l.x0 + w / 2, l.y0 + valueTop, vfs, lc, vHang, aMiddle)
  (root1, (minX: 0.0, minY: 0.0, maxX: W, maxY: H + titleH))
