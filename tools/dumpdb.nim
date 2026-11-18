## Parses a flowchart file and prints FlowDB state as JSON (used by tests/conformance.py).
import std/[json, tables, os]
import nimaid, nimaid/[flowparser, preprocess]

let src = readFile(paramStr(1))
let db = newFlowDB()
var j = newJObject()
try:
  parseFlowchart(stripAnyComments(stripDirectives(src)), db)
  j["direction"] = %db.getDirection()
  var vs = newJObject()
  for id, v in db.getVertices():
    var o = %*{"id": v.id, "text": v.text, "classes": v.classes, "styles": v.styles,
               "link": v.link, "linkTarget": v.linkTarget, "dir": v.dir,
               "labelType": (case v.labelType
                             of flkText: "text"
                             of flkString: "string"
                             of flkMarkdown: "markdown")}
    if v.shape.len > 0: o["type"] = %v.shape
    vs[id] = o
  j["vertices"] = vs
  var es = newJArray()
  for e in db.getEdges():
    es.add %*{"id": e.id, "start": e.source, "end": e.target, "type": e.kind, "text": e.text,
              "stroke": (case e.stroke
                         of fesNormal: "normal"
                         of fesThick: "thick"
                         of fesInvisible: "invisible"
                         of fesDotted: "dotted"),
              "length": e.length, "classes": e.classes, "styles": e.styles, "style": e.styles,
              "interpolate": e.interpolate, "labelType": (case e.labelType
                             of flkText: "text"
                             of flkString: "string"
                             of flkMarkdown: "markdown")}
  j["edges"] = es
  var sgs = newJArray()
  for s in db.getSubGraphs():
    var md = newJObject()
    for k, v in s.metadata: md[k] = %v
    sgs.add %*{"id": s.id, "title": s.title, "nodes": s.nodes, "dir": s.dir, "metadata": md,
               "labelType": (case s.labelType
                             of flkText: "text"
                             of flkString: "string"
                             of flkMarkdown: "markdown")}
  j["subgraphs"] = sgs
  var cs = newJObject()
  for id, c in db.getClasses():
    cs[id] = %*{"id": c.id, "styles": c.styles, "textStyles": c.textStyles}
  j["classes"] = cs
  let d = db.getData()
  var ns = newJArray()
  for n in d.nodes:
    ns.add %*{"id": n.id, "label": n.label, "shape": n.shape, "parentId": n.parentId,
              "isGroup": n.isGroup, "classes": n.classes, "styles": n.styles}
  var le = newJArray()
  for e in d.edges:
    le.add %*{"id": e.id, "source": e.source, "target": e.target, "label": e.label,
              "minlen": e.minlen, "arrowTypeStart": e.arrowTypeStart, "arrowTypeEnd": e.arrowTypeEnd}
  j["data4Layout"] = %*{"nodes": ns, "edges": le, "direction": d.direction}
except CatchableError as e:
  j["error"] = %e.msg
echo j
