## Minimal graphlib (insertion-ordered, multigraph + compound support)
import std/[tables, sets, math]

const
  GraphRoot* = "\x00"
  NoVal* = low(int)

type
  Point* = object
    x*, y*: float
  Edge* = object
    v*, w*: string
    name*: string
  EdgeLabel* = ref object
    minlen*: int
    weight*: float
    width*, height*: float
    labelpos*: string
    labeloffset*: float
    labelRank*: float        ## NaN = unset
    points*: seq[Point]
    x*, y*: float
    hasPos*: bool            ## true once x/y were assigned (label position)
    reversed*: bool
    forwardName*: string
    nestingEdge*: bool
    cutvalue*: float
  OldNode* = object
    rank*, order*: int
    edgeObj*: Edge
    hasEdgeObj*: bool
  OldNodes* = ref object
    ## snapshot of a previous layout's nodes (used for dynamic re-layout)
    nodes*: Table[string, OldNode]
    byEdge*: Table[(string, string, int), int]
  SelfEdge* = object
    e*: Edge
    label*: EdgeLabel
  NodeLabel* = ref object
    width*, height*, x*, y*: float
    rank*, order*, minRank*, maxRank*: int   ## NoVal = unset
    half*: bool                              ## edge-proxy sitting on a half rank
    dummy*, borderType*, borderTop*, borderBottom*, labelpos*: string
    borderLeft*, borderRight*: seq[string]
    bl*, br*: string                         ## layer-graph border nodes
    edgeObj*: Edge
    hasEdgeObj*: bool
    edgeLabel*: EdgeLabel
    selfEdges*: seq[SelfEdge]
    low*, lim*: int
    parent*: string
    rankdir*: string                         ## per-cluster rank direction (clusters only)
  GraphLabel* = object
    ranksep*, edgesep*, nodesep*, marginx*, marginy*: float
    rankdir*, align*, rankalign*, acyclicer*, ranker*: string
    nestingRoot*: string
    nodeRankFactor*: int
    dummyChains*: seq[string]
    maxRank*: int
    width*, height*: float
    root*: string

  EdgeRec = object
    v, w: int
    name: string
    label: EdgeLabel
    alive: bool

  Graph* = ref object
    directed*, multigraph*, compound*: bool
    label*: GraphLabel
    idx: Table[string, int]
    names: seq[string]
    labels: seq[NodeLabel]
    alive: seq[bool]
    par: seq[int]
    kids: seq[seq[int]]       ## child lists (may contain -1 holes)
    kidLive: seq[int]
    rootKids: seq[int]
    rootLive: int
    slot: seq[int]
    inE, outE: seq[seq[int]]
    eidx: Table[string, int]
    es: seq[EdgeRec]
    nNodes, nEdges: int
    prevGraph*: Graph        ## layout graph of the previous layout() call (dynamic layout)
    prevOld*: OldNodes

proc newGraphLabel*(): GraphLabel =
  GraphLabel(ranksep: 50, edgesep: 20, nodesep: 50, rankdir: "TB",
             rankalign: "center", maxRank: NoVal)

proc newEdgeLabel*(minlen = 1, weight = 1.0, width = 0.0, height = 0.0,
                   labelpos = "r", labeloffset = 10.0): EdgeLabel =
  EdgeLabel(minlen: minlen, weight: weight, width: width, height: height,
            labelpos: labelpos, labeloffset: labeloffset, labelRank: NaN)

proc newNodeLabel*(width = 0.0, height = 0.0): NodeLabel =
  NodeLabel(width: width, height: height, rank: NoVal, order: NoVal,
            minRank: NoVal, maxRank: NoVal)

proc newGraph*(directed = true, multigraph = false, compound = false): Graph =
  Graph(directed: directed, multigraph: multigraph, compound: compound,
        label: newGraphLabel())

proc removeVal(s: var seq[int], x: int) =
  let k = s.find(x)
  if k >= 0: s.delete(k)

proc listAdd(g: Graph, parent: int, v: int) =
  if parent < 0:
    g.slot[v] = g.rootKids.len
    g.rootKids.add v
    inc g.rootLive
  else:
    g.slot[v] = g.kids[parent].len
    g.kids[parent].add v
    inc g.kidLive[parent]

proc compact(g: Graph, l: var seq[int]) =
  var j = 0
  for i in 0 ..< l.len:
    if l[i] >= 0:
      l[j] = l[i]; g.slot[l[j]] = j; inc j
  l.setLen(j)

proc listDel(g: Graph, parent: int, v: int) =
  if parent < 0:
    g.rootKids[g.slot[v]] = -1
    dec g.rootLive
    if g.rootKids.len > 64 and g.rootLive * 2 < g.rootKids.len: g.compact(g.rootKids)
  else:
    g.kids[parent][g.slot[v]] = -1
    dec g.kidLive[parent]
    if g.kids[parent].len > 64 and g.kidLive[parent] * 2 < g.kids[parent].len: g.compact(g.kids[parent])
  g.slot[v] = -1

proc nodeCount*(g: Graph): int = g.nNodes
proc edgeCount*(g: Graph): int = g.nEdges
proc hasNode*(g: Graph, v: string): bool = v in g.idx

proc addNode(g: Graph, v: string, label: NodeLabel) =
  let i = g.names.len
  g.names.add v; g.labels.add label; g.alive.add true; g.par.add -1
  g.kids.add @[]; g.kidLive.add 0; g.slot.add -1; g.inE.add @[]; g.outE.add @[]
  g.idx[v] = i
  g.listAdd(-1, i)
  inc g.nNodes

proc setNode*(g: Graph, v: string) =
  if v notin g.idx: g.addNode(v, newNodeLabel())

proc setNode*(g: Graph, v: string, label: NodeLabel) =
  if v in g.idx: g.labels[g.idx[v]] = label
  else: g.addNode(v, label)

proc node*(g: Graph, v: string): NodeLabel =
  let i = g.idx.getOrDefault(v, -1)
  if i < 0: return nil
  g.labels[i]

proc nodes*(g: Graph): seq[string] =
  for i in 0 ..< g.names.len:
    if g.alive[i]: result.add g.names[i]

proc parent*(g: Graph, v: string): string =
  if not g.compound: return ""
  let i = g.idx.getOrDefault(v, -1)
  if i < 0 or g.par[i] < 0: return ""
  g.names[g.par[i]]

proc children*(g: Graph, v: string = GraphRoot): seq[string] =
  if not g.compound:
    if v == GraphRoot: return g.nodes()
    return @[]
  if v == GraphRoot:
    for i in g.rootKids:
      if i >= 0: result.add g.names[i]
  else:
    let i = g.idx.getOrDefault(v, -1)
    if i >= 0:
      for c in g.kids[i]:
        if c >= 0: result.add g.names[c]

proc hasChildren*(g: Graph, v: string): bool =
  if not g.compound: return false
  let i = g.idx.getOrDefault(v, -1)
  i >= 0 and g.kidLive[i] > 0

proc setParent*(g: Graph, v: string, p: string = "") =
  doAssert g.compound, "cannot set parent in a non-compound graph"
  g.setNode(v)
  if p != "": g.setNode(p)
  let vi = g.idx[v]
  g.listDel(g.par[vi], vi)
  if p == "":
    g.par[vi] = -1
    g.listAdd(-1, vi)
  else:
    let pi = g.idx[p]
    g.par[vi] = pi
    g.listAdd(pi, vi)

# ---------------------------------------------------------------- edges
proc rawKey(v, w, name: string): string = v & "\x01" & w & "\x01" & name

proc norm(g: Graph, v, w, name: string): (string, string, string) =
  var a = v
  var b = w
  if not g.directed and a > b: swap(a, b)
  (a, b, (if g.multigraph: name else: ""))

proc hasEdge*(g: Graph, v, w: string, name = ""): bool =
  let (a, b, n) = g.norm(v, w, name)
  rawKey(a, b, n) in g.eidx

proc edge*(g: Graph, v, w: string, name = ""): EdgeLabel =
  let (a, b, n) = g.norm(v, w, name)
  let i = g.eidx.getOrDefault(rawKey(a, b, n), -1)
  if i < 0: return nil
  g.es[i].label

proc edge*(g: Graph, e: Edge): EdgeLabel = g.edge(e.v, e.w, e.name)
proc hasEdge*(g: Graph, e: Edge): bool = g.hasEdge(e.v, e.w, e.name)

proc setEdge*(g: Graph, v, w: string, label: EdgeLabel = nil, name = "") =
  let (a, b, n) = g.norm(v, w, name)
  let key = rawKey(a, b, n)
  let lab = if label.isNil: newEdgeLabel() else: label
  if key in g.eidx:
    if not label.isNil: g.es[g.eidx[key]].label = lab
    return
  g.setNode(a); g.setNode(b)
  let i = g.es.len
  let ai = g.idx[a]
  let bi = g.idx[b]
  g.es.add EdgeRec(v: ai, w: bi, name: n, label: lab, alive: true)
  g.eidx[key] = i
  g.outE[ai].add i
  g.inE[bi].add i
  inc g.nEdges

proc setEdge*(g: Graph, e: Edge, label: EdgeLabel) = g.setEdge(e.v, e.w, label, e.name)

proc removeEdgeIdx(g: Graph, i: int, skipNode = -1) =
  if not g.es[i].alive: return
  g.es[i].alive = false
  if g.es[i].v != skipNode: g.outE[g.es[i].v].removeVal i
  if g.es[i].w != skipNode: g.inE[g.es[i].w].removeVal i
  g.eidx.del rawKey(g.names[g.es[i].v], g.names[g.es[i].w], g.es[i].name)
  dec g.nEdges

proc removeEdge*(g: Graph, v, w: string, name = "") =
  let (a, b, n) = g.norm(v, w, name)
  let i = g.eidx.getOrDefault(rawKey(a, b, n), -1)
  if i >= 0: g.removeEdgeIdx i

proc removeEdge*(g: Graph, e: Edge) = g.removeEdge(e.v, e.w, e.name)

proc removeNode*(g: Graph, v: string) =
  let i = g.idx.getOrDefault(v, -1)
  if i < 0: return
  for ei in g.inE[i] & g.outE[i]: g.removeEdgeIdx(ei, i)
  g.inE[i] = @[]
  g.outE[i] = @[]
  if g.compound:
    g.listDel(g.par[i], i)
    for c in g.kids[i]:
      if c >= 0:
        g.par[c] = -1
        g.listAdd(-1, c)
    g.kids[i] = @[]
    g.kidLive[i] = 0
  g.alive[i] = false
  g.labels[i] = nil
  g.idx.del v
  dec g.nNodes

proc eobj(g: Graph, i: int): Edge =
  Edge(v: g.names[g.es[i].v], w: g.names[g.es[i].w], name: g.es[i].name)

proc edges*(g: Graph): seq[Edge] =
  for i in 0 ..< g.es.len:
    if g.es[i].alive: result.add g.eobj(i)

proc inEdges*(g: Graph, v: string): seq[Edge] =
  let i = g.idx.getOrDefault(v, -1)
  if i >= 0:
    for e in g.inE[i]: result.add g.eobj(e)

proc outEdges*(g: Graph, v: string, w = ""): seq[Edge] =
  let i = g.idx.getOrDefault(v, -1)
  if i >= 0:
    for e in g.outE[i]:
      if w == "" or g.names[g.es[e].w] == w: result.add g.eobj(e)

proc nodeEdges*(g: Graph, v: string): seq[Edge] = g.inEdges(v) & g.outEdges(v)

proc predecessors*(g: Graph, v: string): seq[string] =
  let i = g.idx.getOrDefault(v, -1)
  if i < 0: return
  var seen = initHashSet[int]()
  for e in g.inE[i]:
    let u = g.es[e].v
    if u notin seen: seen.incl u; result.add g.names[u]

proc successors*(g: Graph, v: string): seq[string] =
  let i = g.idx.getOrDefault(v, -1)
  if i < 0: return
  var seen = initHashSet[int]()
  for e in g.outE[i]:
    let u = g.es[e].w
    if u notin seen: seen.incl u; result.add g.names[u]

proc neighbors*(g: Graph, v: string): seq[string] =
  result = g.predecessors(v)
  for s in g.successors(v):
    if s notin result: result.add s

proc sources*(g: Graph): seq[string] =
  for i in 0 ..< g.names.len:
    if g.alive[i] and g.inE[i].len == 0: result.add g.names[i]
