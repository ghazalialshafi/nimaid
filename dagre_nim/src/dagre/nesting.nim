import std/[tables]
import graphlib, util

proc treeDepths(g: Graph): Table[string, int] =
  var depths: Table[string, int]
  proc dfs(v: string, d: int) =
    for c in g.children(v): dfs(c, d + 1)
    depths[v] = d
  for v in g.children(GraphRoot): dfs(v, 1)
  depths

proc run*(g: Graph) =
  let root = g.addDummyNode("root", newNodeLabel(), "_root")
  let depths = treeDepths(g)
  var mx = 0
  for _, d in depths: mx = max(mx, d)
  let height = mx - 1
  let nodeSep = 2 * height + 1
  g.label.nestingRoot = root
  for e in g.edges: g.edge(e).minlen *= nodeSep
  var weight = 1.0
  for e in g.edges: weight += g.edge(e).weight
  proc dfs(v: string) =
    let kids = g.children(v)
    if kids.len == 0:
      if v != root: g.setEdge(root, v, newEdgeLabel(weight = 0, minlen = nodeSep))
      return
    let top = g.addBorderNode("_bt")
    let bottom = g.addBorderNode("_bb")
    let label = g.node(v)
    g.setParent(top, v); label.borderTop = top
    g.setParent(bottom, v); label.borderBottom = bottom
    for child in kids:
      dfs(child)
      let cn = g.node(child)
      let childTop = if cn.borderTop != "": cn.borderTop else: child
      let childBottom = if cn.borderBottom != "": cn.borderBottom else: child
      let thisWeight = if cn.borderTop != "": weight else: 2 * weight
      let minlen = if childTop != childBottom: 1 else: height - depths.getOrDefault(v, 0) + 1
      let l1 = newEdgeLabel(weight = thisWeight, minlen = minlen); l1.nestingEdge = true
      g.setEdge(top, childTop, l1)
      let l2 = newEdgeLabel(weight = thisWeight, minlen = minlen); l2.nestingEdge = true
      g.setEdge(childBottom, bottom, l2)
    if g.parent(v) == "":
      g.setEdge(root, top, newEdgeLabel(weight = 0, minlen = height + depths.getOrDefault(v, 0)))
  for child in g.children(GraphRoot): dfs(child)
  g.label.nodeRankFactor = nodeSep

proc cleanup*(g: Graph) =
  g.removeNode(g.label.nestingRoot)
  g.label.nestingRoot = ""
  for e in g.edges:
    if g.edge(e).nestingEdge: g.removeEdge(e)
