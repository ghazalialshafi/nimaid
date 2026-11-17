## Reads a JSON graph spec, lays it out, prints JSON result (for diffing against dagre JS).
import std/[json, os, strutils]
import ../src/dagre

proc num(j: JsonNode, k: string, d: float): float =
  if j.hasKey(k): j[k].getFloat else: d

let spec = parseFile(paramStr(1))
let g = newGraph(multigraph = true, compound = true)
let gs = spec["graph"]
g.label.rankdir = gs{"rankdir"}.getStr("TB")
g.label.nodesep = num(gs, "nodesep", 50)
g.label.edgesep = num(gs, "edgesep", 20)
g.label.ranksep = num(gs, "ranksep", 50)
g.label.marginx = num(gs, "marginx", 0)
g.label.marginy = num(gs, "marginy", 0)
g.label.acyclicer = gs{"acyclicer"}.getStr("")
g.label.ranker = gs{"ranker"}.getStr("")
g.label.align = gs{"align"}.getStr("")
g.label.rankalign = gs{"rankalign"}.getStr("center")
for n in spec["nodes"]:
  g.setNode(n["id"].getStr, newNodeLabel(num(n, "width", 0), num(n, "height", 0)))
for n in spec["nodes"]:
  if n.hasKey("rankdir"): g.node(n["id"].getStr).rankdir = n["rankdir"].getStr
for n in spec["nodes"]:
  if n.hasKey("parent"): g.setParent(n["id"].getStr, n["parent"].getStr)
proc addEdge(e: JsonNode) =
  g.setEdge(e["v"].getStr, e["w"].getStr,
    newEdgeLabel(int(num(e, "minlen", 1)), num(e, "weight", 1), num(e, "width", 0), num(e, "height", 0),
                 e{"labelpos"}.getStr("r"), num(e, "labeloffset", 10)), e{"name"}.getStr(""))
for e in spec["edges"]: addEdge(e)
var opts = LayoutOptions()
if spec.hasKey("corePath"):
  for c in spec["corePath"]: opts.corePath.add c.getStr
if spec{"customOrder"}.getBool(false):
  opts.customOrder = proc(gr: Graph, ord: OrderFn) = ord(gr, LayoutOptions(disableOptimalOrderHeuristic: true), nil)
if spec.hasKey("useDynamic"): opts.useDynamic = spec["useDynamic"].getBool
layout(g, opts)
when defined(dagreProfile): dumpProfile()
if spec.hasKey("second"):
  for e in spec["second"]: addEdge(e)
  layout(g, opts)
var o = %*{"width": g.label.width, "height": g.label.height, "nodes": {}, "edges": []}
for v in g.nodes:
  let n = g.node(v)
  o["nodes"][v] = %*{"x": n.x, "y": n.y, "w": n.width, "h": n.height}
for e in g.edges:
  let l = g.edge(e)
  var pts = newJArray()
  for p in l.points: pts.add %*[p.x, p.y]
  var ej = %*{"v": e.v, "w": e.w, "name": e.name, "points": pts}
  if l.hasPos: ej["x"] = %l.x; ej["y"] = %l.y
  o["edges"].add ej
echo o
