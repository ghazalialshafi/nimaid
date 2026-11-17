import std/[tables, math]
import graphlib, util

proc normalizeEdge(g: Graph, e: Edge) =
  var v = e.v
  var vRank = g.node(v).rank
  let w = e.w
  let wRank = g.node(w).rank
  let edgeLabel = g.edge(e)
  let labelRank = edgeLabel.labelRank
  if wRank == vRank + 1: return
  g.removeEdge(e)
  var i = 0
  inc vRank
  while vRank < wRank:
    edgeLabel.points = @[]
    let attrs = newNodeLabel()
    attrs.edgeLabel = edgeLabel
    attrs.edgeObj = e
    attrs.hasEdgeObj = true
    attrs.rank = vRank
    let dummy = g.addDummyNode("edge", attrs, "_d")
    if float(vRank) == labelRank:
      attrs.width = edgeLabel.width
      attrs.height = edgeLabel.height
      attrs.dummy = "edge-label"
      attrs.labelpos = edgeLabel.labelpos
    g.setEdge(v, dummy, newEdgeLabel(weight = edgeLabel.weight), e.name)
    if i == 0: g.label.dummyChains.add dummy
    v = dummy
    inc i; inc vRank
  g.setEdge(v, w, newEdgeLabel(weight = edgeLabel.weight), e.name)

proc run*(g: Graph) =
  g.label.dummyChains = @[]
  for e in g.edges: normalizeEdge(g, e)

proc undo*(g: Graph) =
  for start in g.label.dummyChains:
    var v = start
    var node = g.node(v)
    let orig = node.edgeLabel
    g.setEdge(node.edgeObj, orig)
    while node.dummy != "":
      let w = g.successors(v)[0]
      g.removeNode(v)
      orig.points.add Point(x: node.x, y: node.y)
      if node.dummy == "edge-label":
        orig.x = node.x; orig.y = node.y
        orig.hasPos = true
        orig.width = node.width; orig.height = node.height
      v = w
      node = g.node(v)

proc parentDummyChains*(g: Graph) =
  var post = initTable[string, (int, int)]()
  var lim = 0
  proc dfs(v: string) =
    let low = lim
    for c in g.children(v): dfs(c)
    post[v] = (low, lim)
    inc lim
  for v in g.children(GraphRoot): dfs(v)
  for start in g.label.dummyChains:
    var v = start
    let eo = g.node(v).edgeObj
    # findPath
    var vPath, wPath: seq[string]
    let low = min(post[eo.v][0], post[eo.w][0])
    let lm = max(post[eo.v][1], post[eo.w][1])
    var par = eo.v
    while true:
      par = g.parent(par)
      vPath.add par
      if not (par != "" and (post[par][0] > low or lm > post[par][1])): break
    let lca = par
    var wp = eo.w
    while true:
      wp = g.parent(wp)
      if wp == lca: break
      wPath.add wp
    var path = vPath
    for i in countdown(wPath.high, 0): path.add wPath[i]
    var pathIdx = 0
    var pathV = path[0]
    var ascending = true
    while v != eo.w:
      let node = g.node(v)
      if ascending:
        while true:
          pathV = path[pathIdx]
          if pathV != lca and g.node(pathV).maxRank < node.rank: inc pathIdx
          else: break
        if pathV == lca: ascending = false
      if not ascending:
        while pathIdx < path.len - 1 and g.node(path[pathIdx + 1]).minRank <= node.rank:
          inc pathIdx
        pathV = path[pathIdx]
      if pathV != "": g.setParent(v, pathV)
      v = g.successors(v)[0]

proc addBorderSegments*(g: Graph) =
  proc addBN(prop: string, prefix, sg: string, sgNode: NodeLabel, rank: int) =
    let label = newNodeLabel()
    label.rank = rank
    label.borderType = prop
    let arr = if prop == "borderLeft": addr sgNode.borderLeft else: addr sgNode.borderRight
    let prev = if rank > 0: arr[][rank - 1] else: ""
    let curr = g.addDummyNode("border", label, prefix)
    arr[][rank] = curr
    g.setParent(curr, sg)
    if prev != "": g.setEdge(prev, curr, newEdgeLabel(weight = 1))
  proc dfs(v: string) =
    let kids = g.children(v)
    let node = g.node(v)
    for c in kids: dfs(c)
    if node != nil and node.minRank != NoVal:
      node.borderLeft = newSeq[string](node.maxRank + 1)
      node.borderRight = newSeq[string](node.maxRank + 1)
      for r in node.minRank .. node.maxRank:
        addBN("borderLeft", "_bl", v, node, r)
        addBN("borderRight", "_br", v, node, r)
  for v in g.children(GraphRoot): dfs(v)
