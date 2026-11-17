## Mindmaps: indentation tree, balanced left/right layout, coloured branches.
import std/[strutils, options, math]
import gfx, theme, label, textmetrics, painter, drawkit, shapes, shapereg, dagre_adapter

type
  MNode = ref object
    text, shape: string
    depth: int
    kids: seq[MNode]
    w, h, subH: float
    x, y: float
    branch: int

  MindError* = object of CatchableError

proc parseShape(t: string): (string, string) =
  ## returns (shape, text) for  id[text]  id(text)  id((text))  id))text((  id)text(  id{{text}}
  let s = t.strip()
  proc inner(a, b: string): (bool, string) =
    let i = s.find(a)
    if i >= 0 and s.endsWith(b) and s.len >= i + a.len + b.len: (true, s[i + a.len ..< s.len - b.len]) else: (false, "")
  for (a, b, sh) in [("((", "))", "circle"), ("))", "((", "bang"), ("{{", "}}", "hexagon"), (")", "(", "cloud"),
                     ("[", "]", "squareRect"), ("(", ")", "roundedRect")]:
    let r = inner(a, b)
    if r[0]: return (sh, r[1].strip(chars = {'"', ' ', '`'}))
  ("roundedRect", s.strip(chars = {'"', '`'}))

proc mindmapScene*(text: string, th: FlowTheme): (Pvg_Paint, DiagramBounds) =
  var root: MNode = nil
  var stack: seq[MNode]
  var started = false
  for raw in text.replace("\r\n", "\n").split('\n'):
    var line = raw.replace("\t", "    ")
    let pc = line.find("%%")
    if pc >= 0: line = line[0 ..< pc]
    if line.strip().len == 0: continue
    if not started:
      if line.strip().toLowerAscii.startsWith("mindmap"): started = true; continue
      raise newException(MindError, "Parse error: expecting 'mindmap'")
    let t = line.strip()
    if t.startsWith("::"): continue
    let indent = line.len - line.strip(trailing = false).len
    var body = t
    let cls = body.find(":::")
    if cls > 0: body = body[0 ..< cls]
    let (shape, txt) = parseShape(body)
    let n = MNode(text: txt, shape: shape, depth: indent)
    while stack.len > 0 and stack[^1].depth >= indent: stack.setLen(stack.len - 1)
    if stack.len == 0:
      if root.isNil: root = n
      else: raise newException(MindError, "Parse error: mindmap must have a single root")
    else:
      stack[^1].kids.add n
    stack.add n
  if root.isNil: raise newException(MindError, "Parse error: empty mindmap")

  let hGap = 70.0
  let vGap = 14.0
  proc measure(n: MNode, lvl: int) =
    let lab = prepLabel(n.text)
    n.text = lab
    let tm = measureLabel(lab, 16)
    let g = buildGeom(canonicalShape(n.shape), float(tm.w), float(tm.h), 8.0)
    n.w = g.w
    n.h = g.h
    for k in n.kids: measure(k, lvl + 1)
    var s = 0.0
    for k in n.kids: s += k.subH
    if n.kids.len > 1: s += vGap * float(n.kids.len - 1)
    n.subH = max(n.h, s)
  measure(root, 0)
  # split root children into two balanced sides
  var left, right: seq[MNode]
  var lh, rh = 0.0
  for i, k in root.kids:
    k.branch = i
    if rh <= lh: right.add k; rh += k.subH + vGap
    else: left.add k; lh += k.subH + vGap
  proc place(n: MNode, cx, topY: float, sign: float) =
    n.y = topY + n.subH / 2
    n.x = cx
    var y = topY + (n.subH - (block:
      var s = 0.0
      for k in n.kids: s += k.subH
      if n.kids.len > 1: s += vGap * float(n.kids.len - 1)
      s)) / 2
    for k in n.kids:
      k.branch = n.branch
      let kx = cx + sign * (n.w / 2 + hGap + k.w / 2)
      place(k, kx, y, sign)
      y += k.subH + vGap
  root.x = 0
  root.y = 0
  proc placeSide(side: seq[MNode], sign: float) =
    var total = 0.0
    for k in side: total += k.subH
    if side.len > 1: total += vGap * float(side.len - 1)
    var y = -total / 2
    for k in side:
      place(k, sign * (root.w / 2 + hGap + k.w / 2), y, sign)
      y += k.subH + vGap
  placeSide(right, 1)
  placeSide(left, -1)

  let sc = pvg_scene_new()
  var minX, minY, maxX, maxY = 0.0
  proc branchColor(b: int, stroke: bool): Color =
    let hues = [240.0, 60.0, 150.0, 330.0, 30.0, 190.0, 280.0, 100.0]
    if stroke: hsl(hues[b mod 8], 0.65, 0.55) else: hsl(hues[b mod 8], 0.9, 0.88)
  proc edges(n: MNode, isRoot: bool) =
    for k in n.kids:
      let sign = if k.x >= n.x: 1.0 else: -1.0
      let x1 = n.x + sign * n.w / 2
      let x2 = k.x - sign * k.w / 2
      let mx = (x1 + x2) / 2
      let wdt = max(2.0, 9.0 - float(k.depth div 4) * 2.5)
      kCurve(sc, x1, n.y, mx, n.y, mx, k.y, x2, k.y, branchColor(k.branch, true), wdt)
      edges(k, false)
  edges(root, true)
  proc drawNode(n: MNode, isRoot: bool) =
    let canon = canonicalShape(n.shape)
    let g = buildGeom(canon, 0, 0, 8.0)      # placeholder, real geometry below
    discard g
    let tm = measureLabel(n.text, 16)
    let geo = buildGeom(canon, float(tm.w), float(tm.h), 8.0)
    var node = LayoutResultNode(id: "m", x: n.x, y: n.y, width: geo.w, height: geo.h, label: n.text, shape: canon, geom: geo)
    if isRoot:
      node.styles = @["fill:#9370DB", "stroke:#7b52c4", "color:#ffffff"]
    else:
      let f = branchColor(n.branch, false)
      let s = branchColor(n.branch, true)
      node.styles = @["fill:#" & toHex(int(f.r) * 65536 + int(f.g) * 256 + int(f.b), 6), "stroke:#" & toHex(int(s.r) * 65536 + int(s.g) * 256 + int(s.b), 6), "color:#222222"]
    discard pvg_scene_add(sc, buildNodePaint(node, th))
    minX = min(minX, n.x - geo.w / 2)
    maxX = max(maxX, n.x + geo.w / 2)
    minY = min(minY, n.y - geo.h / 2)
    maxY = max(maxY, n.y + geo.h / 2)
    for k in n.kids: drawNode(k, false)
  drawNode(root, true)
  (sc, (minX, minY, maxX, maxY))
