import src/dagre

# --- basic layout -----------------------------------------------------------
let g = newGraph(multigraph = true, compound = true)
g.label.rankdir = "LR"
g.label.ranksep = 60
for (id, w, h) in [("kspacey", 144.0, 100.0), ("swilliams", 160.0, 100.0), ("bpitt", 108.0, 100.0), ("hford", 168.0, 100.0)]:
  g.setNode(id, newNodeLabel(w, h))
g.setEdge("kspacey", "swilliams")
g.setEdge("swilliams", "bpitt", newEdgeLabel(width = 40, height = 14))   # edge with a label box
g.setEdge("kspacey", "hford")
g.setEdge("bpitt", "kspacey")                                           # cycle: handled automatically
layout(g)
echo "graph: ", g.label.width, " x ", g.label.height
for v in g.nodes:
  let n = g.node(v)
  echo v, " -> (", n.x, ", ", n.y, ")"
for e in g.edges:
  echo e.v, "->", e.w, ": ", g.edge(e).points

# --- a cluster laid out with its own direction -------------------------------
let c = newGraph(multigraph = true, compound = true)
for id in ["a", "b", "x", "y", "z"]: c.setNode(id, newNodeLabel(40, 20))
c.setNode("grp", newNodeLabel())
c.node("grp").rankdir = "LR"                 # this cluster flows left-to-right, the rest top-to-bottom
for id in ["x", "y", "z"]: c.setParent(id, "grp")
c.setEdge("a", "x"); c.setEdge("x", "y"); c.setEdge("y", "z"); c.setEdge("z", "b")
layout(c)
echo "cluster grp: ", c.node("grp").width, " x ", c.node("grp").height

# --- options: corePath, custom ordering, dynamic re-layout -------------------
var opts = LayoutOptions(corePath: @["a", "x", "y", "z", "b"])
opts.customOrder = proc(gr: Graph, defaultOrder: OrderFn) =
  defaultOrder(gr, LayoutOptions(disableOptimalOrderHeuristic: true), nil)   # e.g. keep the initial order
layout(c, opts)
# Calling layout() again on the same graph reuses the previous result for stability
# (acyclic choices / ordering); turn it off with LayoutOptions(useDynamic: false).
