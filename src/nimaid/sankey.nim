## Sankey diagrams (Mermaid `sankey` / `sankey-beta`): CSV grammar (sankey.jison), sankeyRenderer.ts, and a port of d3-sankey 0.12
## (node values, depth/height, layers + alignment, 6-iteration relaxation with collision resolution, link breadths).
import std/[strutils, math, options, json, tables, algorithm]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit
from purevg import pvg_linear_gradient_new, pvg_gradient_add_stop, Pvg_Gradient

type
  SNode = ref object
    id: string
    index, depth, height, layer: int
    value, x0, x1, y0, y1: float
    sourceLinks, targetLinks: seq[SLink]
  SLink = ref object
    source, target: SNode
    value, width, y0, y1: float
    index: int

proc parseCsvLine(l: string): seq[string] =
  var cur = ""
  var q = false
  var i = 0
  while i < l.len:
    let c = l[i]
    if q:
      if c == '"':
        if i + 1 < l.len and l[i + 1] == '"': cur.add '"'; inc i
        else: q = false
      else: cur.add c
    elif c == '"': q = true
    elif c == ',': result.add cur.strip(); cur = ""
    else: cur.add c
    inc i
  result.add cur.strip()

proc parseSankey(text: string): (seq[SNode], seq[SLink]) =
  var nodes: seq[SNode]
  var links: seq[SLink]
  var byId = initTable[string, SNode]()
  var started = false
  proc node(id: string): SNode =
    if id notin byId:
      let n = SNode(id: id, index: nodes.len)
      byId[id] = n; nodes.add n
    byId[id]
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    if l.strip().len == 0: continue
    if not started:
      if not l.strip().toLowerAscii.startsWith("sankey"): raise newException(ChartError, "Parse error: expecting 'sankey-beta'")
      started = true; continue
    let f = parseCsvLine(l)
    if f.len < 3: raise newException(ChartError, "Parse error: a sankey row is 'source,target,value', got '" & l.strip() & "'")
    var v: float
    try: v = parseFloat(f[2]) except ValueError: raise newException(ChartError, "Parse error: '" & f[2] & "' is not a number")
    let s = node(f[0])
    let t = node(f[1])
    let lk = SLink(source: s, target: t, value: v, index: links.len)
    links.add lk
  (nodes, links)

# ------------------------------------------------------------------ d3-sankey
proc d3Layout(nodes: seq[SNode], links: seq[SLink], x0, y0, x1, y1, dx, dyIn: float, align: string, iterations = 6) =
  for n in nodes: n.sourceLinks = @[]; n.targetLinks = @[]
  for l in links:
    l.source.sourceLinks.add l
    l.target.targetLinks.add l
  for n in nodes:
    var a, b = 0.0
    for l in n.sourceLinks: a += l.value
    for l in n.targetLinks: b += l.value
    n.value = max(a, b)
  proc bfs(depthMode: bool) =
    let cnt = nodes.len
    var current = nodes
    var x = 0
    while current.len > 0:
      var nxt: seq[SNode]
      for n in current:
        if depthMode: n.depth = x else: n.height = x
        for l in (if depthMode: n.sourceLinks else: n.targetLinks):
          let o = if depthMode: l.target else: l.source
          if o notin nxt: nxt.add o
      inc x
      if x > cnt: raise newException(ChartError, "circular link")
      current = nxt
  bfs(true)
  bfs(false)
  # layers
  var maxDepth = 0
  for n in nodes: maxDepth = max(maxDepth, n.depth)
  let xc = maxDepth + 1
  let kx = if xc > 1: (x1 - x0 - dx) / float(xc - 1) else: 0.0
  var columns = newSeq[seq[SNode]](xc)
  for n in nodes:
    var i: int
    case align
    of "left": i = n.depth
    of "right": i = xc - 1 - n.height
    of "center":
      if n.targetLinks.len > 0: i = n.depth
      elif n.sourceLinks.len > 0:
        var m = high(int)
        for l in n.sourceLinks: m = min(m, l.target.depth)
        i = m - 1
      else: i = 0
    else: i = if n.sourceLinks.len > 0: n.depth else: xc - 1       # justify
    i = max(0, min(xc - 1, i))
    n.layer = i
    n.x0 = x0 + float(i) * kx
    n.x1 = n.x0 + dx
    columns[i].add n
  var maxLen = 0
  for c in columns: maxLen = max(maxLen, c.len)
  let py = if maxLen > 1: min(dyIn, (y1 - y0) / float(maxLen - 1)) else: dyIn
  proc ascBreadth(a, b: SNode): int = cmp(a.y0, b.y0)
  proc ascTarget(a, b: SLink): int =
    let c = cmp(a.target.y0, b.target.y0)
    if c != 0: c else: cmp(a.index, b.index)
  proc ascSource(a, b: SLink): int =
    let c = cmp(a.source.y0, b.source.y0)
    if c != 0: c else: cmp(a.index, b.index)
  proc reorderLinks(ns: seq[SNode]) =
    for n in ns:
      n.sourceLinks.sort(ascTarget)
      n.targetLinks.sort(ascSource)
  proc reorderNodeLinks(n: SNode) =
    for l in n.targetLinks: l.source.sourceLinks.sort(ascTarget)
    for l in n.sourceLinks: l.target.targetLinks.sort(ascSource)
  # initializeNodeBreadths
  var ky = Inf
  for c in columns:
    var s = 0.0
    for n in c: s += n.value
    ky = min(ky, (y1 - y0 - float(c.len - 1) * py) / s)
  for c in columns.mitems:
    var y = y0
    for n in c:
      n.y0 = y
      n.y1 = y + n.value * ky
      y = n.y1 + py
      for l in n.sourceLinks: l.width = l.value * ky
    let off = (y1 - y + py) / float(c.len + 1)
    for i, n in c:
      n.y0 += off * float(i + 1); n.y1 += off * float(i + 1)
    reorderLinks(c)
  proc targetTop(source, target: SNode): float =
    var y = source.y0 - float(source.sourceLinks.len - 1) * py / 2
    for l in source.sourceLinks:
      if l.target == target: break
      y += l.width + py
    for l in target.targetLinks:
      if l.source == source: break
      y -= l.width
    y
  proc sourceTop(source, target: SNode): float =
    var y = target.y0 - float(target.targetLinks.len - 1) * py / 2
    for l in target.targetLinks:
      if l.source == source: break
      y += l.width + py
    for l in source.sourceLinks:
      if l.target == target: break
      y -= l.width
    y
  proc topToBottom(ns: var seq[SNode], yStart: float, i0: int, alpha: float) =
    var y = yStart
    var i = i0
    while i < ns.len:
      let n = ns[i]
      let d = (y - n.y0) * alpha
      if d > 1e-6: n.y0 += d; n.y1 += d
      y = n.y1 + py
      inc i
  proc bottomToTop(ns: var seq[SNode], yStart: float, i0: int, alpha: float) =
    var y = yStart
    var i = i0
    while i >= 0:
      let n = ns[i]
      let d = (n.y1 - y) * alpha
      if d > 1e-6: n.y0 -= d; n.y1 -= d
      y = n.y0 - py
      dec i
  proc resolveCollisions(ns: var seq[SNode], alpha: float) =
    let i = ns.len shr 1
    let subject = ns[i]
    bottomToTop(ns, subject.y0 - py, i - 1, alpha)
    topToBottom(ns, subject.y1 + py, i + 1, alpha)
    bottomToTop(ns, y1, ns.len - 1, alpha)
    topToBottom(ns, y0, 0, alpha)
  for it in 0 ..< iterations:
    let alpha = pow(0.99, float(it))
    let beta = max(1 - alpha, float(it + 1) / float(iterations))
    # right to left
    for i in countdown(columns.len - 2, 0):
      for source in columns[i]:
        var y, w = 0.0
        for l in source.sourceLinks:
          let v = l.value * float(l.target.layer - source.layer)
          y += sourceTop(source, l.target) * v
          w += v
        if not (w > 0): continue
        let d = (y / w - source.y0) * alpha
        source.y0 += d; source.y1 += d
        reorderNodeLinks(source)
      columns[i].sort(ascBreadth)
      resolveCollisions(columns[i], beta)
    # left to right
    for i in 1 ..< columns.len:
      for target in columns[i]:
        var y, w = 0.0
        for l in target.targetLinks:
          let v = l.value * float(target.layer - l.source.layer)
          y += targetTop(l.source, target) * v
          w += v
        if not (w > 0): continue
        let d = (y / w - target.y0) * alpha
        target.y0 += d; target.y1 += d
        reorderNodeLinks(target)
      columns[i].sort(ascBreadth)
      resolveCollisions(columns[i], beta)
  # computeLinkBreadths
  for n in nodes:
    var a = n.y0
    var b = a
    for l in n.sourceLinks: l.y0 = a + l.width / 2; a += l.width
    for l in n.targetLinks: l.y1 = b + l.width / 2; b += l.width

const Tableau10 = ["#4e79a7", "#f28e2c", "#e15759", "#76b7b2", "#59a14f", "#edc949", "#af7aa1", "#ff9da7", "#9c755f", "#bab0ab"]

proc sankeyScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let (nodes, links) = parseSankey(text)
  if links.len == 0: raise newException(ChartError, "Sankey has no links")
  let sc = cv.cfg.cfgSub("sankey")
  let W = sc.cfgFloat("width", 600)
  var H = sc.cfgFloat("height", 400)
  let showValues = sc.cfgBool("showValues", true)
  let nodeW = sc.cfgFloat("nodeWidth", 10)
  let nodePad = sc.cfgFloat("nodePadding", 12)
  let alignMode = sc.cfgStr("nodeAlignment", "justify")
  let prefix = sc.cfgStr("prefix", "")
  let suffix = sc.cfgStr("suffix", "")
  let linkColor = sc.cfgStr("linkColor", "gradient")
  let labelStyle = sc.cfgStr("labelStyle", "auto")          # auto | legacy | outlined
  let nodeColors = sc.cfgSub("nodeColors")
  let pad = nodePad + (if showValues: 15.0 else: 0.0)

  # Auto height: unless a height is configured, grow the canvas until the nodes fill a healthy share of every
  # column (otherwise busy diagrams collapse into hairlines because the padding eats the whole height).
  let fixedHeight = sc.hasKey("height")
  d3Layout(nodes, links, 0, 0, W, H, nodeW, pad, alignMode)
  if not fixedHeight:
    for _ in 0 ..< 14:
      var util = 0.0
      var cols = initTable[int, float]()
      for n in nodes: cols[n.layer] = cols.getOrDefault(n.layer, 0.0) + (n.y1 - n.y0)
      for _, v in cols: util = max(util, v / H)
      if util >= 0.55 or H >= 2400: break
      H *= 1.18
      d3Layout(nodes, links, 0, 0, W, H, nodeW, pad, alignMode)

  var palette: seq[Color]
  for c in Tableau10: palette.add parseCssColor(c).get
  var assigned: seq[string]
  proc colorOf(id: string): Color =
    if nodeColors.hasKey(id):
      let c = parseCssColor(nodeColors[id].getStr())
      if c.isSome: return c.get
    var i = assigned.find(id)
    if i < 0: assigned.add id; i = assigned.high
    palette[i mod palette.len]

  let root = pvg_scene_new()
  var minX, minY = Inf
  var maxX, maxY = -Inf
  proc grow(x0, y0, x1, y1: float) =
    minX = min(minX, x0); minY = min(minY, y0); maxX = max(maxX, x1); maxY = max(maxY, y1)
  let bg = cv.color("background", rgba(255, 255, 255))
  let textColor = cv.color("textColor")
  let muted = mixColor(textColor, bg, 0.45)

  # ---- ribbons first (so labels and nodes stay readable on top)
  for l in links:
    let sh = pvg_shape_new()
    let x0 = l.source.x1
    let x1 = l.target.x0
    let mid = (x0 + x1) / 2
    discard pvg_shape_move_to(sh, cfloat(x0), cfloat(l.y0))
    discard pvg_shape_cubic_to(sh, cfloat(mid), cfloat(l.y0), cfloat(mid), cfloat(l.y1), cfloat(x1), cfloat(l.y1))
    let sw = max(1.0, l.width)
    case linkColor
    of "gradient":
      let g = pvg_linear_gradient_new(cfloat(x0), 0, cfloat(x1), 0)
      let a = colorOf(l.source.id)
      let b = colorOf(l.target.id)
      discard pvg_gradient_add_stop(g, 0, a.r, a.g, a.b, 118)
      discard pvg_gradient_add_stop(g, 1, b.r, b.g, b.b, 118)
      discard pvg_shape_set_stroke_gradient(sh, g)
      discard pvg_shape_set_stroke_width(sh, cfloat(sw))
    else:
      var c: Color
      case linkColor
      of "source": c = colorOf(l.source.id)
      of "target": c = colorOf(l.target.id)
      else:
        let pc = parseCssColor(linkColor)
        c = if pc.isSome: pc.get else: rgba(128, 128, 128)
      styleShape(sh, none(Color), some(withAlpha(c, 0.46)), sw)
    discard pvg_scene_add(root, sh)
    grow(x0, min(l.y0, l.y1) - sw / 2, x1, max(l.y0, l.y1) + sw / 2)

  # ---- nodes: slightly rounded, with a hairline darker edge
  for n in nodes:
    let c = colorOf(n.id)
    kRect(root, n.x0, n.y0, n.x1 - n.x0, max(n.y1 - n.y0, 1.0), some(c), some(mixColor(c, rgba(0, 0, 0), 0.25)), 0.6, 1.5)
    grow(n.x0, n.y0, n.x1, n.y1)

  # ---- labels: first column on the left, last column on the right, the rest to the right of their node;
  #      value in a muted tone; vertical de-collision; a soft pill keeps text legible over ribbons.
  var lastLayer = 0
  for n in nodes: lastLayer = max(lastLayer, n.layer)
  type Lab = object
    n: SNode
    name, val: string
    anchorStart: bool
    cy: float
  var labs: seq[Lab]
  for n in nodes:
    var startSide: bool
    case labelStyle
    of "legacy": startSide = n.x0 < W / 2
    of "outlined": startSide = n.layer >= (lastLayer + 1) div 2
    else: startSide = n.layer != 0        # auto: first column labelled on the left, everything else to the right
    labs.add Lab(n: n, name: n.id, val: (if showValues: prefix & fmtNum(round(n.value * 100) / 100, 2) & suffix else: ""),
                 anchorStart: startSide, cy: (n.y0 + n.y1) / 2)
  # de-collide per (layer, side)
  const LabH = 17.0
  for layer in 0 .. lastLayer:
    for side in [true, false]:
      var idx: seq[int]
      for i, lb in labs:
        if lb.n.layer == layer and lb.anchorStart == side: idx.add i
      idx.sort(proc(a, b: int): int = cmp(labs[a].cy, labs[b].cy))
      for k in 1 ..< idx.len:
        let prev = labs[idx[k - 1]].cy
        if labs[idx[k]].cy < prev + LabH: labs[idx[k]].cy = prev + LabH
  # second pass: labels from neighbouring columns can still overlap horizontally -> push the lower one down
  proc extent(lb: Lab): (float, float) =
    let tw = textW(lb.name, 14) + (if lb.val.len > 0: 7 + textW(lb.val, 14) else: 0.0)
    if lb.anchorStart: (lb.n.x1 + 3, lb.n.x1 + 11 + tw) else: (lb.n.x0 - 11 - tw, lb.n.x0 - 3)
  var order: seq[int]
  for i in 0 ..< labs.len: order.add i
  order.sort(proc(a, b: int): int = cmp(labs[a].cy, labs[b].cy))
  for oi in 0 ..< order.len:
    let j = order[oi]
    for ok in 0 ..< oi:
      let k = order[ok]
      let (aj, bj) = extent(labs[j])
      let (ak, bk) = extent(labs[k])
      if aj < bk and ak < bj and labs[j].cy < labs[k].cy + LabH: labs[j].cy = labs[k].cy + LabH
  for lb in labs:
    let n = lb.n
    let nameW = textW(lb.name, 14)
    let valW = if lb.val.len > 0: textW(lb.val, 14) else: 0.0
    let totalW = nameW + (if lb.val.len > 0: 7 + valW else: 0.0)
    let lx = if lb.anchorStart: n.x1 + 7 else: n.x0 - 7
    let left = if lb.anchorStart: lx else: lx - totalW
    kRect(root, left - 4, lb.cy - 9.5, totalW + 8, 19, some(withAlpha(bg, 0.78)), none(Color), 0, 4)
    drawTextPx(root, lb.name, left, lb.cy + 4.8, 14, textColor, aStart)
    if lb.val.len > 0: drawTextPx(root, lb.val, left + nameW + 7, lb.cy + 4.8, 14, muted, aStart)
    grow(left - 4, lb.cy - 10, left + totalW + 4, lb.cy + 10)
  (root, (minX: minX, minY: minY, maxX: maxX, maxY: maxY))
