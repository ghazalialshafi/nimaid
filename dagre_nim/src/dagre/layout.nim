import std/[tables, sets, math, strutils, algorithm, sequtils]
import graphlib, util, acyclic, rank, nesting, normalize, order, position

proc buildLayoutGraph(input: Graph): Graph =
  let g = newGraph(multigraph = true, compound = true)
  let il = input.label
  var gl = newGraphLabel()
  gl.nodesep = il.nodesep; gl.edgesep = il.edgesep; gl.ranksep = il.ranksep
  gl.marginx = il.marginx; gl.marginy = il.marginy
  gl.acyclicer = il.acyclicer; gl.ranker = il.ranker; gl.align = il.align
  if il.rankdir != "": gl.rankdir = il.rankdir
  if il.rankalign != "": gl.rankalign = il.rankalign
  g.label = gl
  for v in input.nodes:
    let n = input.node(v)
    let nn = newNodeLabel(n.width, n.height)
    nn.rank = n.rank
    g.setNode(v, nn)
    let p = input.parent(v)
    if p != "": g.setParent(v, p)
  for e in input.edges:
    let l = input.edge(e)
    g.setEdge(e, newEdgeLabel(l.minlen, l.weight, l.width, l.height, l.labelpos, l.labeloffset))
  g

proc makeSpaceForEdgeLabels(g: Graph) =
  g.label.ranksep /= 2
  for e in g.edges:
    let l = g.edge(e)
    l.minlen *= 2
    if l.labelpos.toLowerAscii != "c":
      if g.label.rankdir == "TB" or g.label.rankdir == "BT": l.width += l.labeloffset
      else: l.height += l.labeloffset

proc removeSelfEdges(g: Graph) =
  for e in g.edges:
    if e.v == e.w:
      let n = g.node(e.v)
      n.selfEdges.add SelfEdge(e: e, label: g.edge(e))
      g.removeEdge(e)

proc injectEdgeLabelProxies(g: Graph) =
  for e in g.edges:
    let l = g.edge(e)
    if l.width != 0 and l.height != 0:
      let vr = g.node(e.v).rank
      let wr = g.node(e.w).rank
      let lab = newNodeLabel()
      let d = wr - vr
      lab.rank = vr + d div 2
      lab.half = d mod 2 != 0
      lab.edgeObj = e
      lab.hasEdgeObj = true
      discard g.addDummyNode("edge-proxy", lab, "_ep")

proc assignRankMinMax(g: Graph) =
  var mr = 0
  for v in g.nodes:
    let n = g.node(v)
    if n.borderTop != "":
      n.minRank = g.node(n.borderTop).rank
      n.maxRank = g.node(n.borderBottom).rank
      mr = max(mr, n.maxRank)
  g.label.maxRank = mr

proc removeEdgeLabelProxies(g: Graph) =
  for v in g.nodes:
    let n = g.node(v)
    if n.dummy == "edge-proxy":
      g.edge(n.edgeObj).labelRank = float(n.rank) + (if n.half: 0.5 else: 0.0)
      g.removeNode(v)

proc swapWH(g: Graph) =
  for v in g.nodes:
    let n = g.node(v)
    swap(n.width, n.height)
  for e in g.edges:
    let n = g.edge(e)
    swap(n.width, n.height)

proc adjustCoords(g: Graph) =
  let d = g.label.rankdir.toLowerAscii
  if d == "lr" or d == "rl": swapWH(g)

proc undoCoords(g: Graph) =
  let d = g.label.rankdir.toLowerAscii
  if d == "bt" or d == "rl":
    for v in g.nodes: g.node(v).y = -g.node(v).y
    for e in g.edges:
      let l = g.edge(e)
      for p in l.points.mitems: p.y = -p.y
      if l.hasPos: l.y = -l.y
  if d == "lr" or d == "rl":
    for v in g.nodes:
      let n = g.node(v)
      swap(n.x, n.y)
    for e in g.edges:
      let l = g.edge(e)
      for p in l.points.mitems: swap(p.x, p.y)
      if l.hasPos: swap(l.x, l.y)
    swapWH(g)

proc insertSelfEdges(g: Graph) =
  for layer in buildLayerMatrix(g):
    var shift = 0
    for i, v in layer:
      let n = g.node(v)
      if n.rank == NoVal: n.rank = 0
      n.order = i + shift
      for se in n.selfEdges:
        inc shift
        let d = newNodeLabel(se.label.width, se.label.height)
        d.rank = n.rank
        d.order = i + shift
        d.edgeObj = se.e
        d.hasEdgeObj = true
        d.edgeLabel = se.label
        discard g.addDummyNode("selfedge", d, "_se")
        if se.label.points.len != 7:
          se.label.points = @[Point(x: 0, y: -10), Point(x: 0, y: -10), Point(x: 0, y: 0),
                              Point(x: 0, y: 10), Point(x: 0, y: 10), Point(x: 0, y: 0), Point(x: 0, y: 0)]
      n.selfEdges = @[]

proc positionSelfEdges(g: Graph) =
  for v in g.nodes:
    let n = g.node(v)
    if n.dummy == "selfedge":
      let sn = g.node(n.edgeObj.v)
      let nx = n.x
      let ny = n.y
      let dx = sn.width / 2
      let dy = sn.height / 2
      let el = n.edgeLabel
      el.points = @[Point(x: nx + dx, y: ny - dy), Point(x: nx + dx, y: ny - dy), Point(x: nx, y: ny),
                    Point(x: nx - dx, y: ny + dy), Point(x: nx - dx, y: ny + dy), Point(x: nx, y: ny),
                    Point(x: nx, y: ny)]
      el.x = nx; el.y = ny; el.hasPos = true
      g.setEdge(n.edgeObj, el)
      g.removeNode(v)

proc removeBorderNodes(g: Graph) =
  for v in g.nodes:
    if g.hasChildren(v):
      let n = g.node(v)
      let t = g.node(n.borderTop)
      let b = g.node(n.borderBottom)
      let l = g.node(n.borderLeft[^1])
      let r = g.node(n.borderRight[^1])
      n.width = abs(r.x - l.x)
      n.height = abs(b.y - t.y)
      n.x = l.x + n.width / 2
      n.y = t.y + n.height / 2
  for v in g.nodes:
    if g.node(v).dummy == "border": g.removeNode(v)

proc fixupEdgeLabelCoords(g: Graph) =
  for e in g.edges:
    let l = g.edge(e)
    if l.hasPos:
      if l.labelpos == "l" or l.labelpos == "r": l.width -= l.labeloffset
      case l.labelpos
      of "l": l.x -= l.width / 2 + l.labeloffset
      of "r": l.x += l.width / 2 + l.labeloffset
      else: discard

proc translateGraph(g: Graph) =
  var minX = Inf
  var maxX = 0.0
  var minY = Inf
  var maxY = 0.0
  let mx = g.label.marginx
  let my = g.label.marginy
  proc ext(x, y, w, h: float) =
    minX = min(minX, x - w / 2); maxX = max(maxX, x + w / 2)
    minY = min(minY, y - h / 2); maxY = max(maxY, y + h / 2)
  for v in g.nodes:
    let n = g.node(v)
    ext(n.x, n.y, n.width, n.height)
  for e in g.edges:
    let l = g.edge(e)
    if l.hasPos: ext(l.x, l.y, l.width, l.height)
  minX -= mx
  minY -= my
  for v in g.nodes:
    let n = g.node(v)
    n.x -= minX; n.y -= minY
  for e in g.edges:
    let l = g.edge(e)
    for p in l.points.mitems:
      p.x -= minX; p.y -= minY
    if l.hasPos:
      l.x -= minX; l.y -= minY
  g.label.width = maxX - minX + mx
  g.label.height = maxY - minY + my

proc assignNodeIntersects(g: Graph) =
  for e in g.edges:
    if e.v == e.w: continue
    let l = g.edge(e)
    let nv = g.node(e.v)
    let nw = g.node(e.w)
    var p1, p2: Point
    if l.points.len == 0:
      p1 = Point(x: nw.x, y: nw.y)
      p2 = Point(x: nv.x, y: nv.y)
    else:
      p1 = l.points[0]
      p2 = l.points[^1]
    l.points.insert(intersectRect(nv, p1), 0)
    l.points.add intersectRect(nw, p2)

proc reversePoints(g: Graph) =
  for e in g.edges:
    let l = g.edge(e)
    if l.reversed: l.points.reverse()

when defined(dagreProfile):
  import std/[times, strformat]
  var phaseTimes: Table[string, float]
  template ph(name: string, body: untyped) =
    let t0 = cpuTime()
    body
    phaseTimes[name] = phaseTimes.getOrDefault(name) + cpuTime() - t0
  proc dumpProfile*() =
    for k, v in phaseTimes: stderr.writeLine &"{k:30} {v*1000:9.1f} ms"
else:
  template ph(name: string, body: untyped) = body
  proc dumpProfile*() = discard

proc runLayout(g: Graph, opts: LayoutOptions, prevGraph: Graph, prevOld: OldNodes): OldNodes =
  let dynamic = opts.useDynamic
  let oldGraph = if dynamic: prevGraph else: nil
  let oldNodes = if dynamic: prevOld else: nil
  ph "makeSpaceForEdgeLabels": makeSpaceForEdgeLabels(g)
  ph "removeSelfEdges": removeSelfEdges(g)
  ph "acyclic.run": acyclic.run(g, oldGraph, opts.legacyOrder)
  ph "nesting.run": nesting.run(g)
  ph "rank.rank": rank.rank(asNonCompoundGraph(g))
  ph "injectEdgeLabelProxies": injectEdgeLabelProxies(g)
  ph "removeEmptyRanks": removeEmptyRanks(g)
  ph "nesting.cleanup": nesting.cleanup(g)
  ph "normalizeRanks": normalizeRanks(g)
  ph "assignRankMinMax": assignRankMinMax(g)
  ph "removeEdgeLabelProxies": removeEdgeLabelProxies(g)
  ph "normalize.run": normalize.run(g)
  ph "parentDummyChains": parentDummyChains(g)
  ph "addBorderSegments": addBorderSegments(g)
  ph "order.order": order.order(g, opts, oldNodes)
  ph "insertSelfEdges": insertSelfEdges(g)
  ph "adjustCoords": adjustCoords(g)
  ph "position.position": position.position(g, opts.corePath)
  ph "positionSelfEdges": positionSelfEdges(g)
  if dynamic: result = snapshotOld(g)
  ph "removeBorderNodes": removeBorderNodes(g)
  ph "normalize.undo": normalize.undo(g)
  ph "fixupEdgeLabelCoords": fixupEdgeLabelCoords(g)
  ph "undoCoords": undoCoords(g)
  ph "translateGraph": translateGraph(g)
  ph "assignNodeIntersects": assignNodeIntersects(g)
  ph "reversePoints": reversePoints(g)
  ph "acyclic.undo": acyclic.undo(g)

proc updateInputGraph(input, lg: Graph) =
  for v in input.nodes:
    let il = input.node(v)
    let ll = lg.node(v)
    il.x = ll.x; il.y = ll.y; il.order = ll.order; il.rank = ll.rank
    if lg.hasChildren(v):
      il.width = ll.width; il.height = ll.height
  for e in input.edges:
    let il = input.edge(e)
    let ll = lg.edge(e)
    il.points = ll.points
    if ll.hasPos:
      il.x = ll.x; il.y = ll.y; il.hasPos = true
  input.label.width = lg.label.width
  input.label.height = lg.label.height

# ------------------------------------------------------------ clusters with their own rankdir
type Bounds = object
  minX, minY, maxX, maxY, width, height: float

proc topLevelChildOf(g: Graph, node, cluster: string): string =
  var cur = node
  while cur != "":
    let p = g.parent(cur)
    if p == cluster: return cur
    cur = p

proc updateClusterEdges(g, sub: Graph, dx, dy: float) =
  for e in sub.edges:
    if not g.hasEdge(e): continue
    let src = sub.edge(e)
    let tgt = g.edge(e)
    tgt.points = src.points
    for p in tgt.points.mitems:
      p.x += dx; p.y += dy
    if src.hasPos:
      tgt.x = src.x + dx; tgt.y = src.y + dy; tgt.hasPos = true

proc copyNode(n: NodeLabel): NodeLabel =
  new(result); result[] = n[]
proc copyEdge(e: EdgeLabel): EdgeLabel =
  new(result); result[] = e[]

proc recursiveClusterLayout(g: Graph, opts: LayoutOptions) =
  var clusterNodes: seq[string]
  for v in g.nodes:
    if g.hasChildren(v): clusterNodes.add v
  var bounds = initTable[string, Bounds]()
  var subs = initTable[string, Graph]()
  for v in clusterNodes:
    let node = g.node(v)
    if node.rankdir == "": continue
    let sub = newGraph(multigraph = true, compound = true)
    sub.label.rankdir = node.rankdir
    let kids = g.children(v)
    for c in kids: sub.setNode(c, copyNode(g.node(c)))
    var proxied = initHashSet[(string, string)]()
    for e in g.edges:
      let sc = topLevelChildOf(g, e.v, v)
      let tc = topLevelChildOf(g, e.w, v)
      if sc == e.v and tc == e.w:
        sub.setEdge(e, copyEdge(g.edge(e)))
      elif sc != "" and tc != "" and sc != tc:
        if (sc, tc) notin proxied:
          proxied.incl (sc, tc)
          sub.setEdge(sc, tc, copyEdge(g.edge(e)))
    recursiveClusterLayout(sub, opts)
    let sl = buildLayoutGraph(sub)
    discard runLayout(sl, opts, nil, nil)
    updateInputGraph(sub, sl)
    var b = Bounds(minX: Inf, minY: Inf, maxX: -Inf, maxY: -Inf)
    for u in sub.nodes:
      if u == v: continue
      let n = sub.node(u)
      b.minX = min(b.minX, n.x - n.width / 2); b.maxX = max(b.maxX, n.x + n.width / 2)
      b.minY = min(b.minY, n.y - n.height / 2); b.maxY = max(b.maxY, n.y + n.height / 2)
    if b.minX == Inf or b.minY == Inf or b.maxX == -Inf or b.maxY == -Inf:
      b.minX = 0; b.minY = 0; b.maxX = 0; b.maxY = 0
    b.width = b.maxX - b.minX
    b.height = b.maxY - b.minY
    bounds[v] = b
    subs[v] = sub

  type Isolated = object
    id: string
    sub: Graph
    b: Bounds
    removedNodes: seq[(string, NodeLabel, string)]
    removedEdges: seq[(Edge, EdgeLabel)]
  var isolated: seq[Isolated]
  proc descendants(id: string): seq[string] =
    var queue = g.children(id).filterIt(it != id)
    var qi = 0
    while qi < queue.len:
      let cur = queue[qi]
      inc qi
      result.add cur
      for c in g.children(cur):
        if c != cur: queue.add c
  var rawOrder: seq[string]
  var rawMap = initTable[string, seq[string]]()
  var directKids = initHashSet[string]()
  for v in clusterNodes:
    let node = g.node(v)
    if node.rankdir != "" and v in bounds:
      let ch = g.children(v).filterIt(it != v)
      rawOrder.add v
      rawMap[v] = ch
      for c in ch: directKids.incl c
  var topOrder: seq[string]
  var topKids = initTable[string, seq[string]]()
  var topSets = initTable[string, HashSet[string]]()
  var allIso = initHashSet[string]()
  var owner = initTable[string, string]()
  for v in rawOrder:
    if v notin directKids:
      let d = descendants(v)
      topOrder.add v
      topKids[v] = d
      topSets[v] = d.toHashSet
      for x in d:
        allIso.incl x
        if x notin owner: owner[x] = v      # first cluster listing the id wins
  proc topLevelNode(id: string): string = owner.getOrDefault(id, id)
  var saved: seq[(Edge, EdgeLabel)]
  for e in g.edges:
    if e.v in allIso or e.w in allIso: saved.add (e, g.edge(e))
  var savedParents = initTable[string, string]()
  for id in allIso: savedParents[id] = g.parent(id)
  for v in topOrder:
    let node = g.node(v)
    var rn: seq[(string, NodeLabel, string)]
    for c in topKids[v]:
      let cn = g.node(c)
      if cn.isNil: continue
      rn.add (c, cn, savedParents.getOrDefault(c))
      g.removeNode(c)
    var re: seq[(Edge, EdgeLabel)]
    for (e, l) in saved:
      if e.v in topSets[v] or e.w in topSets[v]: re.add (e, l)
    if node.isNil: continue
    isolated.add Isolated(id: v, sub: subs[v], b: bounds[v], removedNodes: rn, removedEdges: re)
    node.width = bounds[v].width
    node.height = bounds[v].height
  var proxyKeys: seq[(string, string)]
  var proxySeen = initHashSet[(string, string)]()
  for (e, l) in saved:
    let ev = topLevelNode(e.v)
    let ew = topLevelNode(e.w)
    if ev != ew and g.hasNode(ev) and g.hasNode(ew) and (ev, ew) notin proxySeen:
      proxySeen.incl (ev, ew)
      proxyKeys.add (ev, ew)
      let pl = copyEdge(l)
      pl.width = 0; pl.height = 0
      g.setEdge(ev, ew, pl)
  let lg = buildLayoutGraph(g)
  let old = runLayout(lg, opts, g.prevGraph, g.prevOld)
  if opts.useDynamic:
    g.prevGraph = lg
    g.prevOld = old
  updateInputGraph(g, lg)
  for (a, b) in proxyKeys:
    if g.hasEdge(a, b): g.removeEdge(a, b)
  for iso in isolated:
    let cn = g.node(iso.id)
    let cx = if cn.isNil: 0.0 else: cn.x
    let cy = if cn.isNil: 0.0 else: cn.y
    let sx = (iso.b.minX + iso.b.maxX) / 2
    let sy = (iso.b.minY + iso.b.maxY) / 2
    for (id, node, parent) in iso.removedNodes:
      g.setNode(id, node)
      if parent != "": g.setParent(id, parent)
    for (e, l) in iso.removedEdges: g.setEdge(e, l)
    for u in iso.sub.nodes:
      if u == iso.id: continue
      let sn = iso.sub.node(u)
      let mn = g.node(u)
      if not mn.isNil:
        mn.x = cx + (sn.x - sx)
        mn.y = cy + (sn.y - sy)
    updateClusterEdges(g, iso.sub, cx - sx, cy - sy)
    subs.del iso.id
  for v in clusterNodes:
    let node = g.node(v)
    if node.isNil or node.rankdir == "" or v notin subs or v notin bounds: continue
    let sub = subs[v]
    let b = bounds[v]
    let px = node.x
    let py = node.y
    let sx = (b.minX + b.maxX) / 2
    let sy = (b.minY + b.maxY) / 2
    for u in sub.nodes:
      if u == v: continue
      let sn = sub.node(u)
      let mn = g.node(u)
      if not mn.isNil:
        mn.x = px + (sn.x - sx)
        mn.y = py + (sn.y - sy)
    updateClusterEdges(g, sub, px - sx, py - sy)
    subs.del v

proc layout*(g: Graph, opts: LayoutOptions = LayoutOptions()) =
  ## Computes x/y for nodes, `points` (and label x/y) for edges and the
  ## graph's width/height. Results are written back into `g`.
  ## Clusters may carry their own `rankdir` (laid out in isolation).
  if g.nodeCount == 0:
    g.label.width = 0; g.label.height = 0
    return
  recursiveClusterLayout(g, opts)
