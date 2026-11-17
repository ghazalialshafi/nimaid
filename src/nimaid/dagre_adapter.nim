import std/[tables, sets, strutils, math, algorithm, os, json]
import types, flowdb, geom, linewithoffset, edges
import dagre/graphlib
import label, outline, shapes, shapereg
import dagre/layout
import dagre/order

type
  SelfLoopSegment = object
    order: int
    edge: RenderEdge

  LayoutResultNode* = object
    id*: string
    x*, y*, width*, height*: float
    label*: string
    labelType*: FlowLabelKind
    isGroup*: bool
    parentId*: string
    shape*: string
    domId*: string
    styles*: seq[string]
    classes*: seq[string]
    colorIndex*: int
    compiledStyles*: seq[string]
    geom*: Geom
    link*: string

  LayoutResultEdge* = object
    id*: string
    source*: string
    target*: string
    label*: string
    labelType*: FlowLabelKind
    points*: seq[Point]
    markerPoints*: seq[Point]   ## endpoints before marker shortening: arrowheads are drawn here
    labelPos*: Point
    stroke*: FlowEdgeStroke
    arrowTypeStart*: string
    arrowTypeEnd*: string
    styles*: seq[string]
    compiledStyles*: seq[string]
    classes*: seq[string]
    curve*: string

  LayoutResult* = object
    width*, height*: float
    nodes*: Table[string, LayoutResultNode]
    edges*: seq[LayoutResultEdge]
    subgraphs*: seq[LayoutResultNode]
    title*: string

proc getDefaultSelfLoopSide(rankdir: string): string =
  case rankdir
  of "BT": "bottom"
  of "LR": "right"
  of "RL": "left"
  of "TB": "top"
  else: "top"

proc getSelfLoopSide(node: LayoutResultNode, dummyPoints: seq[Point], rankdir: string): string =
  if dummyPoints.len == 0:
    return getDefaultSelfLoopSide(rankdir)
  var avgX = 0.0
  var avgY = 0.0
  for p in dummyPoints:
    avgX += p.x
    avgY += p.y
  avgX /= float(dummyPoints.len)
  avgY /= float(dummyPoints.len)
  let dx = avgX - node.x
  let dy = avgY - node.y
  if abs(dx) > abs(dy):
    return if dx > 0.0: "right" else: "left"
  if abs(dy) > 0.0:
    return if dy > 0.0: "bottom" else: "top"
  getDefaultSelfLoopSide(rankdir)

proc getSelfLoopPoints(node: LayoutResultNode, side: string, labelW: float): seq[Point] =
  let x = node.x
  let y = node.y
  let hw = node.width / 2.0
  let hh = node.height / 2.0
  let maxSpan = max(36.0, min(100.0, node.width * 0.8))
  let span = clamp(max(labelW, node.width * 0.35), 36.0, maxSpan)
  let depth = clamp(min(node.width, node.height) * 0.45, 24.0, 48.0)

  case side
  of "bottom":
    let b = y + hh
    @[Point(x: x - span / 2.0, y: b), Point(x: x - span / 2.0, y: b + depth), Point(x: x + span / 2.0, y: b + depth), Point(x: x + span / 2.0, y: b)]
  of "right":
    let r = x + hw
    @[Point(x: r, y: y - span / 2.0), Point(x: r + depth, y: y - span / 2.0), Point(x: r + depth, y: y + span / 2.0), Point(x: r, y: y + span / 2.0)]
  of "left":
    let l = x - hw
    @[Point(x: l, y: y - span / 2.0), Point(x: l - depth, y: y - span / 2.0), Point(x: l - depth, y: y + span / 2.0), Point(x: l, y: y + span / 2.0)]
  else:
    let t = y - hh
    @[Point(x: x - span / 2.0, y: t), Point(x: x - span / 2.0, y: t - depth), Point(x: x + span / 2.0, y: t - depth), Point(x: x + span / 2.0, y: t)]

proc getSelfLoopLabelPos(node: LayoutResultNode, pts: seq[Point], side: string, labelW, labelH: float): Point =
  let gap = 4.0
  case side
  of "bottom":
    var maxY = -Inf
    for p in pts: maxY = max(maxY, p.y)
    Point(x: node.x, y: maxY + labelH / 2.0 + gap)
  of "right":
    var maxX = -Inf
    for p in pts: maxX = max(maxX, p.x)
    Point(x: maxX + labelW / 2.0 + gap, y: node.y)
  of "left":
    var minX = Inf
    for p in pts: minX = min(minX, p.x)
    Point(x: minX - labelW / 2.0 - gap, y: node.y)
  else:
    var minY = Inf
    for p in pts: minY = min(minY, p.y)
    Point(x: node.x, y: minY - labelH / 2.0 - gap)

proc clipEdgePoints(
  sourceNode: LayoutResultNode,
  targetNode: LayoutResultNode,
  rawPoints: seq[Point],
  pad: float
): seq[Point] =
  if rawPoints.len < 2:
    return rawPoints
  result = rawPoints
  let n = result.len
  result[0] = intersectGeom(sourceNode.geom, sourceNode.x, sourceNode.y,
                            sourceNode.width, sourceNode.height, result[1])
  result[n - 1] = intersectGeom(targetNode.geom, targetNode.x, targetNode.y,
                                targetNode.width, targetNode.height, result[n - 2])

# =============================================================================
# Recursive layout: port of mermaid's dagre driver (mermaid-graphlib.js + index.js)
# =============================================================================
type
  LNode = ref object
    rn: RenderNode
    geom: Geom
    dummy: bool
    isCluster: bool            ## "clusterNode": laid out independently as a sub-graph
    sub: Graph
    x, y, w, h: float
    childCx, childCy: float    ## centre of the cluster box inside its own sub-layout

  LEdge = ref object
    re: RenderEdge
    fromCluster, toCluster: string
    selfId: string
    selfOrder: int             ## -1: ordinary edge
    pts: seq[Point]
    lpos: Point
    hasPos: bool

  ClusterInfo = object
    id: string                 ## anchor node that stands in for the cluster on edges
    externalConnections: bool

var
  useLegacyDagre* = true   ## true: dagre-d3-es ordering (what mermaid uses); false: dagre_nim's modern tie-breaking
  gNodes: Table[string, LNode]
  gEdges: Table[string, LEdge]
  clusterDb: Table[string, ClusterInfo]
  descendants: Table[string, seq[string]]

proc isDescendant(id, ancestor: string): bool =
  id in descendants.getOrDefault(ancestor)

proc edgeInCluster(e: Edge, clusterId: string): bool =
  if e.v == clusterId or e.w == clusterId: return false
  let d = descendants.getOrDefault(clusterId)
  e.v in d or e.w in d

proc extractDescendants(id: string, g: Graph): seq[string] =
  let ch = g.children(id)
  result = ch
  for c in ch: result.add extractDescendants(c, g)

proc findCommonEdges(g: Graph, id1, id2: string): seq[(string, string)] =
  var e1: seq[(string, string)]
  var e2: seq[(string, string)]
  for e in g.edges:
    if e.v == id1 or e.w == id1:
      e1.add ((if e.v == id1: id2 else: e.v), (if e.w == id1: id1 else: e.w))
    if e.v == id2 or e.w == id2:
      e2.add (e.v, e.w)
  for a in e1:
    if a in e2: result.add a

proc findNonClusterChild(id: string, g: Graph, clusterId: string): string =
  let ch = g.children(id)
  if ch.len < 1: return id
  var reserve = ""
  for c in ch:
    let cid = findNonClusterChild(c, g, clusterId)
    let common = findCommonEdges(g, clusterId, cid)
    if cid.len > 0:
      if common.len > 0: reserve = cid
      else: return cid
  reserve

proc getAnchorId(id: string): string =
  if id notin clusterDb: return id
  if not clusterDb[id].externalConnections: return id
  clusterDb[id].id

proc isNodeInExtractableCluster(g: Graph, node, rootId: string): bool =
  var p = g.parent(node)
  while p.len > 0 and p != rootId:
    if p in clusterDb and not clusterDb[p].externalConnections: return true
    p = g.parent(p)
  false

proc findSafeAnchorNode(g: Graph, clusterId, excluded: string): string =
  for c in g.children(clusterId):
    if c == excluded or isDescendant(c, excluded): continue
    let cand = findNonClusterChild(c, g, clusterId)
    if cand.len == 0: continue
    if not isNodeInExtractableCluster(g, cand, clusterId): return cand
  ""

proc copyCluster(clusterId: string, g, newG: Graph, rootId: string) =
  var nodes = g.children(clusterId)
  if clusterId != rootId: nodes.add clusterId
  for node in nodes:
    if g.children(node).len > 0:
      copyCluster(node, g, newG, rootId)
    else:
      newG.setNode(node, g.node(node))
      if rootId != g.parent(node):
        newG.setParent(node, g.parent(node))
      if clusterId != rootId and node != clusterId:
        newG.setParent(node, clusterId)
      for e in g.nodeEdges(node):
        if edgeInCluster(e, rootId):
          newG.setEdge(e.v, e.w, g.edge(e), e.name)
    g.removeNode(node)

proc extractor(g: Graph, depth: int) =
  if depth > 10: return
  var hasChildren = false
  for n in g.nodes:
    if g.children(n).len > 0: hasChildren = true
  if not hasChildren: return
  for node in g.nodes:
    if node notin clusterDb: continue
    if not clusterDb[node].externalConnections and g.children(node).len > 0:
      let nd = gNodes[node]
      var dir = if g.label.rankdir == "TB": "LR" else: "TB"
      if nd.rn.dir.len > 0: dir = (if nd.rn.dir == "TD": "TB" else: nd.rn.dir)
      let cg = newGraph(multigraph = true, compound = true)
      cg.label.rankdir = dir
      cg.label.nodesep = 50
      cg.label.ranksep = 50
      cg.label.marginx = 8
      cg.label.marginy = 8
      copyCluster(node, g, cg, node)
      nd.isCluster = true
      nd.sub = cg
      g.setNode(node, newNodeLabel(0, 0))
  for node in g.nodes:
    let nd = gNodes.getOrDefault(node)
    if not nd.isNil and nd.isCluster: extractor(nd.sub, depth + 1)

proc adjustClustersAndEdges(g: Graph) =
  for id in g.nodes:
    if g.children(id).len > 0:
      descendants[id] = extractDescendants(id, g)
      clusterDb[id] = ClusterInfo(id: findNonClusterChild(id, g, id))
  for id in g.nodes:
    if g.children(id).len > 0:
      for e in g.edges:
        if isDescendant(e.v, id) xor isDescendant(e.w, id):
          clusterDb[id].externalConnections = true
  var keys: seq[string]
  for k in clusterDb.keys: keys.add k
  for id in keys:
    let nonClusterChild = clusterDb[id].id
    let parent = g.parent(nonClusterChild)
    if parent != id and parent in clusterDb and not clusterDb[parent].externalConnections:
      clusterDb[id].id = parent
    var hasOut = false
    for e in g.edges:
      if e.v == id: hasOut = true
    if nonClusterChild.len > 0 and clusterDb[id].externalConnections and hasOut and
       isNodeInExtractableCluster(g, nonClusterChild, id):
      let safe = findSafeAnchorNode(g, id, g.parent(nonClusterChild))
      if safe.len > 0: clusterDb[id].id = safe
  for e in g.edges:
    let le = gEdges[e.name]
    if e.v in clusterDb or e.w in clusterDb:
      let v = getAnchorId(e.v)
      let w = getAnchorId(e.w)
      let lab = g.edge(e)
      g.removeEdge(e)
      if v != e.v:
        let p = g.parent(v)
        if p in clusterDb: clusterDb[p].externalConnections = true
        le.fromCluster = e.v
      if w != e.w:
        let p = g.parent(w)
        if p in clusterDb: clusterDb[p].externalConnections = true
        le.toCluster = e.w
      g.setEdge(v, w, lab, e.name)
  extractor(g, 0)

# ---- measuring + layout ------------------------------------------------------
proc measureNode(nd: LNode, verticalFlow: bool) =
  let n = nd.rn
  if nd.dummy:
    nd.geom = Geom(w: 10, h: 10, kind: okRect)
    nd.geom.paths = @[]
    nd.w = 10
    nd.h = 10
    return
  if n.box.kind.len > 0:
    nd.geom = buildBoxGeom(n.box, proc(t: string, size: float): float = float(measureLabel(t, float32(size)).w))
    nd.w = nd.geom.w
    nd.h = nd.geom.h
    return
  let tm = measureLabel(n.label, 16.0, isNode = true)
  let shape = if n.isGroup: "squareRect" else: canonicalShape(n.shape)
  nd.geom = buildGeom(shape, float(tm.w), float(tm.h), float(n.padding), verticalFlow)
  nd.w = nd.geom.w
  nd.h = nd.geom.h

proc dumpGraph(g: Graph, tag: string, after: bool) =
  let path = getEnv("MMD_DUMP_LAYOUT")
  if path.len == 0: return
  var j = newJObject()
  j["tag"] = %tag
  j["after"] = %after
  j["graph"] = %*{"rankdir": g.label.rankdir, "nodesep": g.label.nodesep, "ranksep": g.label.ranksep,
                  "marginx": g.label.marginx, "marginy": g.label.marginy}
  var ns = newJArray()
  for v in g.nodes:
    let nl = g.node(v)
    ns.add %*{"id": v, "parent": g.parent(v), "width": nl.width, "height": nl.height, "x": nl.x, "y": nl.y}
  j["nodes"] = ns
  var es = newJArray()
  for e in g.edges:
    let l = g.edge(e)
    var pts = newJArray()
    for p in l.points: pts.add %*{"x": p.x, "y": p.y}
    es.add %*{"v": e.v, "w": e.w, "name": e.name, "minlen": l.minlen, "weight": l.weight,
              "width": l.width, "height": l.height, "labelpos": l.labelpos, "x": l.x, "y": l.y, "points": pts}
  j["edges"] = es
  let f = open(path, fmAppend)
  f.writeLine($j)
  f.close()

proc layoutGraph(g: Graph, parentCluster: LNode) =
  let verticalFlow = g.label.rankdir in ["TB", "BT"]
  if parentCluster != nil:
    g.setNode(parentCluster.rn.id, newNodeLabel(0, 0))
    for v in g.nodes:
      if v != parentCluster.rn.id and g.parent(v) == "":
        g.setParent(v, parentCluster.rn.id)
  for v in g.nodes:
    if parentCluster != nil and v == parentCluster.rn.id: continue
    let nd = gNodes[v]
    if nd.isCluster:
      nd.sub.label.ranksep = g.label.ranksep + 25
      nd.sub.label.nodesep = g.label.nodesep
      layoutGraph(nd.sub, nd)
      let nl = g.node(v)
      nl.width = nd.w
      nl.height = nd.h
    elif g.children(v).len > 0:
      discard   # pure compound cluster: dagre sizes it
    else:
      measureNode(nd, verticalFlow)
      let nl = g.node(v)
      nl.width = nd.w
      nl.height = nd.h
  let tag = if parentCluster == nil: "root" else: parentCluster.rn.id
  dumpGraph(g, tag, false)
  layout(g, LayoutOptions(legacyOrder: useLegacyDagre, useDynamic: false))  # dagre-d3-es semantics, as mermaid uses
  dumpGraph(g, tag, true)
  if parentCluster != nil:
    let cl = g.node(parentCluster.rn.id)
    parentCluster.childCx = cl.x
    parentCluster.childCy = cl.y
    parentCluster.w = cl.width
    parentCluster.h = cl.height

proc cutPathAtIntersect(pts: seq[Point], cx, cy, cw, ch: float): seq[Point] =
  func outside(p: Point): bool = abs(p.x - cx) >= cw / 2 or abs(p.y - cy) >= ch / 2
  proc inter(o, i: Point): Point =
    let dx = abs(cx - i.x)
    let w = cw / 2
    var r = if i.x < o.x: w - dx else: w + dx
    let h = ch / 2
    let Q = abs(o.y - i.y)
    let R = abs(o.x - i.x)
    if abs(cy - o.y) * w > abs(cx - o.x) * h:
      let q = if i.y < o.y: o.y - h - cy else: cy - h - o.y
      r = (if Q == 0: 0.0 else: R * q / Q)
      result = Point(x: (if i.x < o.x: i.x + r else: i.x - R + r),
                     y: (if i.y < o.y: i.y + Q - q else: i.y - Q + q))
      if r == 0: result = o
      if R == 0: result.x = o.x
      if Q == 0: result.y = o.y
    else:
      r = if i.x < o.x: o.x - w - cx else: cx - w - o.x
      let q = if R == 0: 0.0 else: Q * r / R
      var x = if i.x < o.x: i.x + R - r else: i.x - R + r
      var y = if i.y < o.y: i.y + q else: i.y - q
      if r == 0:
        x = o.x
        y = o.y
      if R == 0: x = o.x
      if Q == 0: y = o.y
      result = Point(x: x, y: y)
  var lastOut = pts[0]
  var isInside = false
  for p in pts:
    if not outside(p) and not isInside:
      let ip = inter(lastOut, p)
      var present = false
      for q in result:
        if q.x == ip.x and q.y == ip.y: present = true
      if not present: result.add ip
      isInside = true
    else:
      lastOut = p
      if not isInside: result.add p

proc runDagreLayout*(chart: FlowChartData, defaultPadding: float = 8.0): LayoutResult =
  result.title = chart.title
  gNodes = initTable[string, LNode]()
  gEdges = initTable[string, LEdge]()
  clusterDb = initTable[string, ClusterInfo]()
  descendants = initTable[string, seq[string]]()

  let rootDir = if chart.direction.len > 0: (if chart.direction == "TD": "TB" else: chart.direction) else: "TB"
  let g = newGraph(multigraph = true, compound = true)
  g.label.rankdir = rootDir
  g.label.nodesep = 50.0
  g.label.ranksep = 50.0
  g.label.marginx = 8.0
  g.label.marginy = 8.0

  for n0 in chart.nodes:
    var n = n0
    n.label = prepLabel(n.label, markdown = n.labelType == flkMarkdown, wrap = not n.isGroup)
    if n.isGroup: n.label = decodeEntities(n.label)
    gNodes[n.id] = LNode(rn: n)
    g.setNode(n.id, newNodeLabel(0, 0))
  for n in chart.nodes:
    if n.parentId.len > 0: g.setParent(n.id, n.parentId)

  var selfEdges: seq[RenderEdge]
  var chartEdges = chart.edges
  for e in chartEdges.mitems:
    e.label = prepLabel(e.label, markdown = e.labelType == flkMarkdown, fontSize = edgeLabelFontSize)
  for e in chartEdges:
    if e.source == e.target:
      selfEdges.add e
      let node = gNodes[e.source]
      let s1 = e.source & "---" & e.source & "---1-" & e.id
      let s2 = e.source & "---" & e.source & "---2-" & e.id
      for sid in [s1, s2]:
        gNodes[sid] = LNode(rn: RenderNode(id: sid, parentId: node.rn.parentId, padding: 0), dummy: true)
        g.setNode(sid, newNodeLabel(10, 10))
        if node.rn.parentId.len > 0: g.setParent(sid, node.rn.parentId)
      let ls = if e.label.len > 0: edgeLabelSize(e.label) else: (w: 0.0, h: 0.0)
      var seg0 = e
      seg0.label = ""
      seg0.arrowTypeEnd = "none"
      var seg1 = e
      seg1.arrowTypeStart = "none"
      seg1.arrowTypeEnd = "none"
      var seg2 = e
      seg2.label = ""
      seg2.arrowTypeStart = "none"
      let names = [e.id & "-cyc-0", e.id & "-cyc-1", e.id & "-cyc-2"]
      gEdges[names[0]] = LEdge(re: seg0, selfId: e.id, selfOrder: 0,
                               fromCluster: (if node.rn.isGroup: e.source else: ""))
      gEdges[names[1]] = LEdge(re: seg1, selfId: e.id, selfOrder: 1)
      gEdges[names[2]] = LEdge(re: seg2, selfId: e.id, selfOrder: 2,
                               toCluster: (if node.rn.isGroup: e.source else: ""))
      g.setEdge(e.source, s1, newEdgeLabel(minlen = 1, weight = 1.0), names[0])
      g.setEdge(s1, s2, newEdgeLabel(minlen = 1, weight = 1.0, width = ls.w, height = ls.h, labelpos = "c"), names[1])
      g.setEdge(s2, e.source, newEdgeLabel(minlen = 1, weight = 1.0), names[2])
    else:
      gEdges[e.id] = LEdge(re: e, selfOrder: -1)
      let el = newEdgeLabel(minlen = e.minlen, weight = 1.0, labelpos = "c")
      if e.label.len > 0:
        let ls = edgeLabelSize(e.label)
        el.width = ls.w
        el.height = ls.h
      g.setEdge(e.source, e.target, el, e.id)

  adjustClustersAndEdges(g)
  layoutGraph(g, nil)

  # ---- flatten into absolute coordinates ------------------------------------
  var absNodes = initTable[string, LayoutResultNode]()
  var edgeRaw = initTable[string, seq[Point]]()
  var edgeLab = initTable[string, (bool, Point)]()
  var dummyPos = initTable[string, Point]()

  proc nodeItem(nd: LNode, x, y, w, h: float): LayoutResultNode =
    let o = nd.rn
    LayoutResultNode(
      id: o.id, x: x, y: y, width: w, height: h, label: o.label, labelType: o.labelType,
      isGroup: o.isGroup, parentId: o.parentId,
      shape: (if o.isGroup: o.shape else: canonicalShape(o.shape)),
      domId: o.domId, styles: o.styles, compiledStyles: o.compiledStyles,
      classes: o.classes, colorIndex: o.colorIndex, geom: nd.geom, link: o.link)

  proc collect(gr: Graph, parentCluster: LNode, ox, oy: float) =
    for v in gr.nodes:
      if parentCluster != nil and v == parentCluster.rn.id: continue
      let nd = gNodes[v]
      let nl = gr.node(v)
      if nd.isCluster:
        # place the sub-layout so that its cluster box is centred on the node
        let sx = ox + nl.x - nd.childCx
        let sy = oy + nl.y - nd.childCy
        absNodes[v] = nodeItem(nd, ox + nl.x, oy + nl.y, nd.w, nd.h)
        collect(nd.sub, nd, sx, sy)
      elif nd.dummy:
        dummyPos[v] = Point(x: ox + nl.x, y: oy + nl.y)
      else:
        absNodes[v] = nodeItem(nd, ox + nl.x, oy + nl.y, nl.width, nl.height)
    for e in gr.edges:
      let lab = gr.edge(e)
      var pts: seq[Point]
      for p in lab.points: pts.add Point(x: p.x + ox, y: p.y + oy)
      edgeRaw[e.name] = pts
      edgeLab[e.name] = (lab.hasPos, Point(x: lab.x + ox, y: lab.y + oy))
  collect(g, nil, 0, 0)

  var finalNodes = initTable[string, LayoutResultNode]()
  for n0 in chart.nodes:
    let n = gNodes[n0.id].rn
    if n.id in absNodes:
      var item = absNodes[n.id]
      if n.isGroup:   # a cluster is never narrower than its title
        let tw = float(measureLabel(n.label, 16.0).w) + 2 * float(n.padding)
        if item.width < tw: item.width = tw
      finalNodes[n.id] = item
      if n.isGroup: result.subgraphs.add item

  result.nodes = finalNodes

  proc finishEdge(le: LEdge, raw: seq[Point], source, target: string): seq[Point] =
    var pts = raw
    if source in finalNodes and target in finalNodes and pts.len >= 2:
      pts = clipEdgePoints(finalNodes[source], finalNodes[target], pts, defaultPadding)
    if le.toCluster.len > 0 and le.toCluster in finalNodes and raw.len > 0:
      let c = finalNodes[le.toCluster]
      pts = cutPathAtIntersect(raw, c.x, c.y, c.width, c.height)
    if le.fromCluster.len > 0 and le.fromCluster in finalNodes and pts.len > 0:
      let c = finalNodes[le.fromCluster]
      var rev = pts
      rev.reverse()
      pts = cutPathAtIntersect(rev, c.x, c.y, c.width, c.height)
      pts.reverse()
    pts

  for e in chartEdges:
    if e.source == e.target: continue
    let le = gEdges[e.id]
    var pts = finishEdge(le, edgeRaw.getOrDefault(e.id), e.source, e.target)
    let rawPts = pts
    pts = applyPreciseMarkerOffsets(pts, e.arrowTypeStart, e.arrowTypeEnd)
    let (hp, lp) = edgeLab.getOrDefault(e.id, (false, Point()))
    result.edges.add LayoutResultEdge(
      id: e.id, source: e.source, target: e.target, label: e.label, labelType: e.labelType,
      points: pts, markerPoints: rawPts, labelPos: (if hp: lp else: resolveEdgeLabelPosition(pts)),
      stroke: e.stroke, arrowTypeStart: e.arrowTypeStart, arrowTypeEnd: e.arrowTypeEnd,
      styles: e.styles, compiledStyles: e.compiledStyles, classes: e.classes, curve: e.curve)

  for e in selfEdges:
    if e.source notin result.nodes: continue
    let nodeObj = result.nodes[e.source]
    let s1 = e.source & "---" & e.source & "---1-" & e.id
    let s2 = e.source & "---" & e.source & "---2-" & e.id
    var dummyPts: seq[Point]
    if s1 in dummyPos: dummyPts.add dummyPos[s1]
    if s2 in dummyPos: dummyPts.add dummyPos[s2]
    let side = getSelfLoopSide(nodeObj, dummyPts, rootDir)
    let ls = edgeLabelSize(e.label)
    let labelW = if e.label.len > 0: ls.w else: 0.0
    let labelH = if e.label.len > 0: ls.h else: 0.0
    var loopPts = getSelfLoopPoints(nodeObj, side, labelW)
    let loopRaw = loopPts
    loopPts = applyPreciseMarkerOffsets(loopPts, e.arrowTypeStart, e.arrowTypeEnd)
    result.edges.add LayoutResultEdge(
      id: e.id, source: e.source, target: e.target, label: e.label, labelType: e.labelType,
      points: loopPts, markerPoints: loopRaw, labelPos: getSelfLoopLabelPos(nodeObj, loopPts, side, labelW, labelH),
      stroke: e.stroke, arrowTypeStart: e.arrowTypeStart, arrowTypeEnd: e.arrowTypeEnd,
      styles: e.styles, compiledStyles: e.compiledStyles, classes: e.classes, curve: e.curve)
