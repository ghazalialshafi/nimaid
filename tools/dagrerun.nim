## Reads a graph JSON (same shape as the MMD_DUMP_LAYOUT "pre" records), runs dagre_nim, prints result JSON.
import std/[json, os]
import dagre/[graphlib, layout, order]

let j = parseFile(paramStr(1))
let g = newGraph(multigraph = true, compound = true)
let gl = j["graph"]
g.label.rankdir = gl["rankdir"].getStr()
g.label.nodesep = gl["nodesep"].getFloat()
g.label.ranksep = gl["ranksep"].getFloat()
g.label.marginx = gl["marginx"].getFloat()
g.label.marginy = gl["marginy"].getFloat()
if gl.hasKey("edgesep"): g.label.edgesep = gl["edgesep"].getFloat()
for n in j["nodes"]:
  g.setNode(n["id"].getStr(), newNodeLabel(n["width"].getFloat(), n["height"].getFloat()))
for n in j["nodes"]:
  if n["parent"].getStr().len > 0: g.setParent(n["id"].getStr(), n["parent"].getStr())
for e in j["edges"]:
  g.setEdge(e["v"].getStr(), e["w"].getStr(),
            newEdgeLabel(minlen = e["minlen"].getInt(), weight = e["weight"].getFloat(),
                         width = e["width"].getFloat(), height = e["height"].getFloat(),
                         labelpos = e["labelpos"].getStr()), e["name"].getStr())
layout(g, LayoutOptions(legacyOrder: true, useDynamic: false))
var o = newJObject()
var ns = newJArray()
for v in g.nodes:
  let nl = g.node(v)
  ns.add %*{"id": v, "x": nl.x, "y": nl.y, "width": nl.width, "height": nl.height}
o["nodes"] = ns
var es = newJArray()
for e in g.edges:
  let l = g.edge(e)
  var pts = newJArray()
  for p in l.points: pts.add %*{"x": p.x, "y": p.y}
  es.add %*{"name": e.name, "points": pts, "x": l.x, "y": l.y}
o["edges"] = es
echo o
