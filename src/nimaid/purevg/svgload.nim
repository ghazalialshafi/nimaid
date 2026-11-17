## SVG picture loader. <use> inliner + nanosvg parser (user's port) -> pure-Nim paint model.
import std/[strutils, tables, math]
import core, raster, nanosvg

type
  Node = ref object
    tag: string               ## "" = text node
    attrs: seq[(string, string)]
    kids: seq[Node]
    text: string

  PicPaint* = object
    kind*: int                ## 0 none, 1 color, 2 linear, 3 radial
    rgba*: array[4, float]
    ramp*: ref Ramp
    xf*: array[6, float]
    stops*: seq[tuple[off: float, rgba: array[4, float]]]
  PicShape* = object
    segs*: seq[Seg]
    fill*, stroke*: PicPaint
    opacity*, sw*, miter*: float
    evenOdd*: bool
    dash*: seq[float]
    cap*, join*: int
  Picture* = ref object
    w*, h*: float
    shapes*: seq[PicShape]

# ---------------------------------------------------------------- tiny XML tree
proc parseXml(s: string): Node =
  result = Node(tag: "#root")
  var stack = @[result]
  var i = 0
  while i < s.len:
    if s[i] != '<':
      let e = s.find('<', i); let j = if e < 0: s.len else: e
      let t = s[i ..< j]
      if t.strip.len > 0: stack[^1].kids.add Node(text: t)
      i = j; continue
    if s.continuesWith("<!--", i): (let e = s.find("-->", i); i = if e < 0: s.len else: e + 3; continue)
    if s.continuesWith("<?", i) or s.continuesWith("<!", i): (let e = s.find('>', i); i = if e < 0: s.len else: e + 1; continue)
    if s.continuesWith("</", i):
      let e = s.find('>', i); i = if e < 0: s.len else: e + 1
      if stack.len > 1: stack.setLen(stack.len - 1)
      continue
    var j = i + 1
    while j < s.len and s[j] notin {' ', '\t', '\n', '\r', '>', '/'}: inc j
    let n = Node(tag: s[i + 1 ..< j])
    var selfClose = false
    while j < s.len:
      while j < s.len and s[j] in {' ', '\t', '\n', '\r'}: inc j
      if j >= s.len: break
      if s[j] == '>': inc j; break
      if s[j] == '/': selfClose = true; inc j; continue
      var k = j
      while k < s.len and s[k] notin {'=', ' ', '>', '/'}: inc k
      let name = s[j ..< k]
      j = k
      while j < s.len and s[j] in {' ', '='}: inc j
      if j < s.len and s[j] in {'"', '\''}:
        let q = s[j]; let e = s.find(q, j + 1)
        let ee = if e < 0: s.len else: e
        n.attrs.add (name, s[j + 1 ..< ee]); j = ee + 1
      else: j = k + 1
    stack[^1].kids.add n
    if not selfClose: stack.add n
    i = j

proc attr(n: Node, name: string): string =
  for (k, v) in n.attrs:
    if k == name: return v

proc collectIds(n: Node, ids: var Table[string, Node]) =
  let id = n.attr("id")
  if id.len > 0: ids[id] = n
  for k in n.kids: collectIds(k, ids)

proc expand(n: Node, ids: Table[string, Node], depth: int): Node =
  ## Returns a copy with every <use> replaced by <g transform=..>copy of target</g>.
  if n.tag == "" : return n
  if n.tag == "use" and depth < 12:
    var href = n.attr("xlink:href"); if href.len == 0: href = n.attr("href")
    if href.startsWith("#") and href[1 .. ^1] in ids:
      let tgt = ids[href[1 .. ^1]]
      let g = Node(tag: "g")
      var tr = n.attr("transform")
      let x = n.attr("x"); let y = n.attr("y")
      if x.len > 0 or y.len > 0:
        tr = tr & " translate(" & (if x.len > 0: x else: "0") & " " & (if y.len > 0: y else: "0") & ")"
      for (k, v) in n.attrs:
        if k notin ["xlink:href", "href", "x", "y", "width", "height", "transform", "id"]: g.attrs.add (k, v)
      if tr.len > 0: g.attrs.add ("transform", tr)
      let t = Node(tag: (if tgt.tag in ["symbol", "svg"]: "g" else: tgt.tag), kids: tgt.kids)
      for (k, v) in tgt.attrs:
        if k != "id": t.attrs.add (k, v)
      g.kids.add expand(t, ids, depth + 1)
      return g
    return Node(tag: "g")
  result = Node(tag: n.tag, attrs: n.attrs, text: n.text)
  for k in n.kids: result.kids.add expand(k, ids, depth)

proc serialize(n: Node, o: var string) =
  if n.tag == "": o.add n.text; return
  if n.tag == "#root":
    for k in n.kids: serialize(k, o)
    return
  o.add "<" & n.tag
  for (k, v) in n.attrs: o.add " " & k & "=\"" & v & "\""
  if n.kids.len == 0: o.add "/>"
  else:
    o.add ">"
    for k in n.kids: serialize(k, o)
    o.add "</" & n.tag & ">"

proc inlineUse*(svg: string): string =
  if "<use" notin svg: return svg
  let root = parseXml(svg)
  var ids = initTable[string, Node]()
  collectIds(root, ids)
  serialize(expand(root, ids, 0), result)

# ---------------------------------------------------------------- nanosvg -> Picture
proc rgbaOf(c: uint32): array[4, float32] =
  [float32(c and 255) / 255, float32((c shr 8) and 255) / 255, float32((c shr 16) and 255) / 255, float32((c shr 24) and 255) / 255]

proc convPaint(p: NSVGpaint): PicPaint =
  case p.kind
  of nsvgPaintColor:
    result.kind = 1
    let c = rgbaOf(p.color)
    result.rgba = [c[0].float, c[1].float, c[2].float, c[3].float]
  of nsvgPaintLinearGradient, nsvgPaintRadialGradient:
    let g = p.gradient
    if g == nil or g.stops.len == 0: return
    result.kind = if p.kind == nsvgPaintLinearGradient: 2 else: 3
    for i in 0..5: result.xf[i] = g.xform[i].float
    for st in g.stops:
      let c = rgbaOf(st.color)
      result.stops.add (clamp(st.offset.float, 0.0, 1.0), [c[0].float, c[1].float, c[2].float, c[3].float])
    new(result.ramp)
    let n = g.stops.len
    template put(i: int, c: array[4, float32]) = result.ramp[][i] = c
    if n == 1:
      for i in 0..255: put(i, rgbaOf(g.stops[0].color))
    else:
      var ca = rgbaOf(g.stops[0].color); var cb = ca
      var ia = int(clamp(g.stops[0].offset, 0, 1) * 255)
      for i in 0..<ia: put(i, ca)
      var ib = ia
      for i in 0..<n - 1:
        ca = rgbaOf(g.stops[i].color); cb = rgbaOf(g.stops[i + 1].color)
        ia = int(clamp(g.stops[i].offset, 0, 1) * 255); ib = int(clamp(g.stops[i + 1].offset, 0, 1) * 255)
        let cnt = ib - ia
        if cnt <= 0: continue
        for j in 0..<cnt:
          let u = j.float32 / cnt.float32
          put(ia + j, [ca[0] + (cb[0] - ca[0]) * u, ca[1] + (cb[1] - ca[1]) * u,
                       ca[2] + (cb[2] - ca[2]) * u, ca[3] + (cb[3] - ca[3]) * u])
      for i in ib..255: put(i, cb)
  else: discard

proc loadSvg*(svg: string): Picture =
  let img = nsvgParse(inlineUse(svg), "px", 96)
  if img == nil or img.width <= 0 or img.height <= 0: return nil
  result = Picture(w: img.width.float, h: img.height.float)
  for sh in img.shapes:
    var s = PicShape(opacity: sh.opacity.float, sw: sh.strokeWidth.float, miter: sh.miterLimit.float,
                     evenOdd: sh.fillRule == nsvgFillEvenOdd, cap: ord(sh.strokeLineCap), join: ord(sh.strokeLineJoin))
    s.fill = convPaint(sh.fill); s.stroke = convPaint(sh.stroke)
    for i in 0..<sh.strokeDashCount: s.dash.add sh.strokeDashArray[i].float
    for p in sh.paths:
      if p.pts.len < 2: continue
      s.segs.add Seg(op: 'M', v: [p.pts[0].float, p.pts[1].float, 0, 0, 0, 0])
      var i = 2
      while i + 5 < p.pts.len:
        s.segs.add Seg(op: 'C', v: [p.pts[i].float, p.pts[i+1].float, p.pts[i+2].float, p.pts[i+3].float, p.pts[i+4].float, p.pts[i+5].float])
        i += 6
      if p.closed: s.segs.add Seg(op: 'Z')
    result.shapes.add s
