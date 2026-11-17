import std/[tables, math, algorithm]
import graphlib

var idCounter = 0
proc uniqueId*(prefix: string): string =
  inc idCounter
  prefix & $idCounter

proc rangeSeq*(start, limit: int, step = 1): seq[int] =
  var i = start
  if step > 0:
    while i < limit: result.add i; i += step
  else:
    while i > limit: result.add i; i += step

proc addDummyNode*(g: Graph, kind: string, attrs: NodeLabel, name: string): string =
  var v = name
  while g.hasNode(v): v = uniqueId(name)
  attrs.dummy = kind
  g.setNode(v, attrs)
  v

proc addBorderNode*(g: Graph, prefix: string, rank = NoVal, order = NoVal): string =
  let n = newNodeLabel()
  if rank != NoVal:
    n.rank = rank
    n.order = order
  g.addDummyNode("border", n, prefix)

proc simplify*(g: Graph): Graph =
  result = newGraph()
  result.label = g.label
  for v in g.nodes: result.setNode(v, g.node(v))
  for e in g.edges:
    let sl = result.edge(e.v, e.w)
    let l = g.edge(e)
    let pw = if sl.isNil: 0.0 else: sl.weight
    let pm = if sl.isNil: 1 else: sl.minlen
    result.setEdge(e.v, e.w, newEdgeLabel(minlen = max(pm, l.minlen), weight = pw + l.weight))

proc asNonCompoundGraph*(g: Graph): Graph =
  result = newGraph(multigraph = g.multigraph)
  result.label = g.label
  for v in g.nodes:
    if not g.hasChildren(v): result.setNode(v, g.node(v))
  for e in g.edges: result.setEdge(e, g.edge(e))

proc intersectRect*(rect: NodeLabel, p: Point): Point =
  let x = rect.x
  let y = rect.y
  let dx = p.x - x
  let dy = p.y - y
  var w = rect.width / 2
  var h = rect.height / 2
  if dx == 0 and dy == 0:
    raise newException(ValueError, "Not possible to find intersection inside of the rectangle")
  var sx, sy: float
  if dx == 0 or abs(dy) * w > abs(dx) * h:
    if dy < 0: h = -h
    sx = h * dx / dy
    sy = h
  else:
    if dx < 0: w = -w
    sx = w
    sy = w * dy / dx
  Point(x: x + sx, y: y + sy)

proc maxRank*(g: Graph): int =
  result = NoVal
  for v in g.nodes:
    let r = g.node(v).rank
    if r != NoVal and r > result: result = r
  if result == NoVal: result = 0

proc buildLayerMatrix*(g: Graph): seq[seq[string]] =
  result = newSeq[seq[string]](maxRank(g) + 1)
  for v in g.nodes:
    let n = g.node(v)
    if n.rank != NoVal and n.order != NoVal:
      while result[n.rank].len <= n.order: result[n.rank].add ""
      result[n.rank][n.order] = v

proc normalizeRanks*(g: Graph) =
  var mn = high(int)
  for v in g.nodes:
    let r = g.node(v).rank
    if r != NoVal and r < mn: mn = r
  for v in g.nodes:
    let n = g.node(v)
    if n.rank != NoVal: n.rank -= mn

proc removeEmptyRanks*(g: Graph) =
  var offset = high(int)
  for v in g.nodes:
    let r = g.node(v).rank
    if r != NoVal and r < offset: offset = r
  var layers: seq[seq[string]]
  for v in g.nodes:
    let n = g.node(v)
    if n.rank == NoVal or n.half: continue
    let r = n.rank - offset
    while layers.len <= r: layers.add @[]
    layers[r].add v
  var delta = 0
  let f = g.label.nodeRankFactor
  for i, vs in layers:
    if vs.len == 0 and i mod f != 0: dec delta
    elif vs.len > 0 and delta != 0:
      for v in vs: g.node(v).rank += delta
