import std/[tables, sets, algorithm, math, sequtils]
import graphlib, util

type
  OrderFn* = proc(g: Graph, opts: LayoutOptions, old: OldNodes) {.closure.}
  CustomOrderFn* = proc(g: Graph, defaultOrder: OrderFn) {.closure.}
  LayoutOptions* = object
    disableOptimalOrderHeuristic*: bool
    constraints*: seq[tuple[left, right: string]]
    customOrder*: CustomOrderFn          ## replaces the ordering phase: customOrder(graph, defaultOrder)
    corePath*: seq[string]         ## nodes whose edges are aligned first by Brandes-Köpf
    useDynamic*: bool = true       ## reuse the previous layout of the same graph for stability
    legacyOrder*: bool             ## dagre-d3-es / dagre 0.8.x ordering semantics (what mermaid uses)

  BCEntry = object
    v: int
    bc, weight: float
    hasBc: bool
  REntry = object
    vs: seq[int]
    i: int
    bc, weight: float
    hasBc: bool
  SubResult = object
    vs: seq[int]
    bc, weight: float
    hasBc: bool
    usedBias: bool
  MEntry = ref object
    indegree: int
    inl, outl: seq[MEntry]
    vs: seq[int]
    i: int
    bc, weight: float
    hasBc, merged: bool
  Ctx = ref object
    legacy: bool
    n: int
    lab: seq[NodeLabel]
    rank, ord: seq[int]
    isEdgeDummy, edgeRev, hasKids: seq[bool]
    eoV, eoW: seq[int]
    outE, inE: seq[seq[(int, float)]]
    succ: seq[seq[int]]
    bl, br: seq[seq[int]]          ## per node, per rank border ids (-1 none)
    parentOf: seq[int]
    minRank, maxRank: seq[int]
    loc: seq[int]                  ## main id -> local id in the layer graph being processed
    mapArr: seq[MEntry]
  LG = ref object
    nodes: seq[int]                ## local -> main
    kids: seq[seq[int]]            ## local children; index L is the layer-graph root
    par: seq[int]                  ## local parent (root = L, root's parent = -1)
    blL, brL: seq[int]             ## border node main ids for subgraph nodes (-1 none)
    inList: seq[seq[(int, float)]] ## merged in-edges (source main id, weight)
  CG = ref object
    edges: seq[(int, int)]
    seen: HashSet[int64]

proc compareByOldOrder*(old: OldNodes, a, b: NodeLabel): int =
  if old.isNil or a.isNil or b.isNil: return 0
  if a.dummy != "edge" or b.dummy != "edge" or not a.hasEdgeObj or not b.hasEdgeObj: return 0
  let ae = a.edgeObj
  let be = b.edgeObj
  if ae.v notin old.nodes or be.v notin old.nodes or ae.w notin old.nodes or be.w notin old.nodes: return 0
  let target = if ae.w != be.w: old.nodes[ae.v].rank else: old.nodes[ae.w].rank
  if target == NoVal: return 0
  let ka = (ae.v, ae.w, target)
  let kb = (be.v, be.w, target)
  if ka notin old.byEdge or kb notin old.byEdge: return 0
  let oa = old.byEdge[ka]
  let ob = old.byEdge[kb]
  if oa == NoVal or ob == NoVal: return 0
  oa - ob

proc snapshotOld*(g: Graph): OldNodes =
  result = OldNodes()
  for v in g.nodes:
    let n = g.node(v)
    result.nodes[v] = OldNode(rank: n.rank, order: n.order, edgeObj: n.edgeObj, hasEdgeObj: n.hasEdgeObj)
    if n.hasEdgeObj and n.rank != NoVal:
      let k = (n.edgeObj.v, n.edgeObj.w, n.rank)
      if k notin result.byEdge: result.byEdge[k] = n.order

proc truthy(f: float): bool = f != 0.0 and f == f

# ------------------------------------------------------------ context
proc buildCtx(g: Graph): (Ctx, seq[string]) =
  let names = g.nodes
  let n = names.len
  var id = initTable[string, int]()
  for i, v in names: id[v] = i
  let c = Ctx(n: n)
  c.lab = newSeq[NodeLabel](n); c.rank = newSeq[int](n); c.ord = newSeq[int](n)
  c.isEdgeDummy = newSeq[bool](n); c.edgeRev = newSeq[bool](n); c.hasKids = newSeq[bool](n)
  c.eoV = newSeq[int](n); c.eoW = newSeq[int](n)
  c.outE = newSeq[seq[(int, float)]](n); c.inE = newSeq[seq[(int, float)]](n)
  c.succ = newSeq[seq[int]](n); c.bl = newSeq[seq[int]](n); c.br = newSeq[seq[int]](n)
  c.parentOf = newSeq[int](n); c.minRank = newSeq[int](n); c.maxRank = newSeq[int](n)
  c.loc = newSeq[int](n); c.mapArr = newSeq[MEntry](n)
  for i, v in names:
    let nl = g.node(v)
    c.lab[i] = nl
    c.rank[i] = nl.rank; c.ord[i] = nl.order
    c.minRank[i] = nl.minRank; c.maxRank[i] = nl.maxRank
    c.isEdgeDummy[i] = nl.dummy == "edge"
    c.hasKids[i] = g.hasChildren(v)
    let p = g.parent(v)
    c.parentOf[i] = if p == "": -1 else: id[p]
    c.eoV[i] = -1; c.eoW[i] = -1
    if nl.hasEdgeObj:
      c.eoV[i] = id.getOrDefault(nl.edgeObj.v, -1)
      c.eoW[i] = id.getOrDefault(nl.edgeObj.w, -1)
    c.edgeRev[i] = not nl.edgeLabel.isNil and nl.edgeLabel.reversed
    if nl.minRank != NoVal:
      c.bl[i] = newSeq[int](nl.maxRank + 1); c.br[i] = newSeq[int](nl.maxRank + 1)
      for r in 0 .. nl.maxRank:
        c.bl[i][r] = if r < nl.borderLeft.len and nl.borderLeft[r] != "": id[nl.borderLeft[r]] else: -1
        c.br[i][r] = if r < nl.borderRight.len and nl.borderRight[r] != "": id[nl.borderRight[r]] else: -1
  for e in g.edges:
    let a = id[e.v]
    let b = id[e.w]
    let w = g.edge(e).weight
    c.outE[a].add (b, w)
    c.inE[b].add (a, w)
    if b notin c.succ[a]: c.succ[a].add b
  (c, names)

proc cgAdd(cg: CG, a, b: int) =
  let k = int64(a) shl 32 or int64(b)
  if k notin cg.seen:
    cg.seen.incl k
    cg.edges.add (a, b)

# ------------------------------------------------------------ cross count
proc crossCount(c: Ctx, layering: seq[seq[int]]): float =
  var posArr = newSeq[int](c.n)
  for li in 1 ..< layering.len:
    let north = layering[li - 1]
    let south = layering[li]
    for i, v in south:
      if v >= 0: posArr[v] = i
    type SE = tuple[pos: int, weight: float]
    var entries: seq[SE]
    var es: seq[SE]
    for v in north:
      if v < 0: continue
      es.setLen(0)
      for (w, wt) in c.outE[v]: es.add (posArr[w], wt)
      if es.len > 1: es.sort(proc(a, b: SE): int = cmp(a.pos, b.pos))
      entries.add es
    var first = 1
    while first < south.len: first = first shl 1
    let treeSize = 2 * first - 1
    dec first
    var tree = newSeq[float](treeSize)
    for en in entries:
      var index = en.pos + first
      tree[index] += en.weight
      var ws = 0.0
      while index > 0:
        if index mod 2 == 1: ws += tree[index + 1]
        index = (index - 1) shr 1
        tree[index] += en.weight
      result += en.weight * ws

proc buildLayering(c: Ctx): seq[seq[int]] =
  var mr = 0
  for r in c.rank:
    if r != NoVal and r > mr: mr = r
  result = newSeq[seq[int]](mr + 1)
  for m in 0 ..< c.n:
    let r = c.rank[m]
    let o = c.ord[m]
    if r != NoVal and o != NoVal:
      while result[r].len <= o: result[r].add -1
      result[r][o] = m

# ------------------------------------------------------------ init order
proc initOrder(c: Ctx, old: OldNodes): seq[seq[int]] =
  var simple: seq[int]
  var mr = 0
  for m in 0 ..< c.n:
    if not c.hasKids[m]:
      simple.add m
      mr = max(mr, c.rank[m])
  var layers = newSeq[seq[int]](mr + 1)
  simple.sort(proc(a, b: int): int = cmp(c.rank[a], c.rank[b]))
  var visited = newSeq[bool](c.n)
  var stackV, stackI: seq[int]
  var succLists = initTable[int, seq[int]]()
  proc succOf(v: int): seq[int] =
    if old.isNil: return c.succ[v]
    var sl = c.succ[v]
    sl.sort(proc(a, b: int): int = compareByOldOrder(old, c.lab[a], c.lab[b]))
    sl
  for root in simple:
    if visited[root]: continue
    visited[root] = true
    layers[c.rank[root]].add root
    var sl = @[succOf(root)]
    stackV.setLen(0); stackI.setLen(0)
    stackV.add root; stackI.add 0
    while stackV.len > 0:
      let v = stackV[^1]
      let i = stackI[^1]
      let lst = sl[^1]
      if i < lst.len:
        stackI[^1] = i + 1
        let w = lst[i]
        if not visited[w]:
          visited[w] = true
          layers[c.rank[w]].add w
          stackV.add w; stackI.add 0
          sl.add succOf(w)
      else:
        stackV.setLen(stackV.len - 1); stackI.setLen(stackI.len - 1)
        sl.setLen(sl.len - 1)
  layers

proc assignOrder(c: Ctx, layering: seq[seq[int]]) =
  for layer in layering:
    for i, v in layer:
      if v >= 0: c.ord[v] = i

# ------------------------------------------------------------ layer graphs
proc buildLayerGraphs(c: Ctx, ranks: seq[int], inRel: bool): seq[LG] =
  var byRank = initTable[int, seq[int]]()
  for m in 0 ..< c.n:
    if c.rank[m] != NoVal: byRank.mgetOrPut(c.rank[m], @[]).add m
    if c.minRank[m] != NoVal and c.maxRank[m] != NoVal:
      for r in c.minRank[m] .. c.maxRank[m]:
        if r != c.rank[m]: byRank.mgetOrPut(r, @[]).add m
  var scratch = newSeq[int](c.n)
  for r in ranks:
    let lg = LG()
    var nodes: seq[int]
    for m in byRank.getOrDefault(r):
      if c.rank[m] == r or (c.minRank[m] != NoVal and c.minRank[m] <= r and r <= c.maxRank[m]): nodes.add m
    let L = nodes.len
    lg.nodes = nodes
    lg.kids = newSeq[seq[int]](L + 1)
    lg.par = newSeq[int](L + 1)
    lg.blL = newSeq[int](L + 1); lg.brL = newSeq[int](L + 1)
    lg.inList = newSeq[seq[(int, float)]](L)
    lg.par[L] = -1; lg.blL[L] = -1; lg.brL[L] = -1
    for i, m in nodes: scratch[m] = i
    for i, m in nodes:
      # parent: main parent if it is in this layer graph, else the layer root
      let p = c.parentOf[m]
      var lp = L
      if p >= 0:
        lp = L
        # the parent is always part of the layer graph when the child is (it spans the rank)
        lp = scratch[p]
      lg.par[i] = lp
      lg.kids[lp].add i
      lg.blL[i] = -1; lg.brL[i] = -1
      if c.minRank[m] != NoVal:
        lg.blL[i] = c.bl[m][r]; lg.brL[i] = c.br[m][r]
      let rel = if inRel: addr c.inE[m] else: addr c.outE[m]
      for (u, w) in rel[]:
        var found = false
        for k in 0 ..< lg.inList[i].len:
          if lg.inList[i][k][0] == u:
            lg.inList[i][k][1] += w
            found = true
            break
        if not found: lg.inList[i].add (u, w)
    result.add lg

# ------------------------------------------------------------ sort pieces
proc mergeEntries(target, source: MEntry) =
  var sum, weight = 0.0
  if truthy(target.weight):
    sum += target.bc * target.weight; weight += target.weight
  if truthy(source.weight):
    sum += source.bc * source.weight; weight += source.weight
  target.vs = source.vs & target.vs
  target.bc = sum / weight
  target.weight = weight
  target.hasBc = true
  target.i = min(source.i, target.i)
  source.merged = true

proc resolveConflicts(c: Ctx, entries: seq[BCEntry], cg: CG): seq[REntry] =
  var ms: seq[MEntry]
  for i, en in entries:
    let m = MEntry(vs: @[en.v], i: i)
    if en.hasBc: m.bc = en.bc; m.weight = en.weight; m.hasBc = true
    c.mapArr[en.v] = m
    ms.add m
  for (a, b) in cg.edges:
    if not c.mapArr[a].isNil and not c.mapArr[b].isNil:
      inc c.mapArr[b].indegree
      c.mapArr[a].outl.add c.mapArr[b]
  for en in entries: discard
  var sourceSet: seq[MEntry]
  for m in ms:
    if m.indegree == 0: sourceSet.add m
  var done: seq[MEntry]
  while sourceSet.len > 0:
    let entry = sourceSet.pop()
    done.add entry
    entry.inl.reverse()
    for u in entry.inl:
      if u.merged: continue
      if not u.hasBc or not entry.hasBc or u.bc >= entry.bc: mergeEntries(entry, u)
    for w in entry.outl:
      w.inl.add entry
      dec w.indegree
      if w.indegree == 0: sourceSet.add w
  for en in entries: c.mapArr[en.v] = nil
  for m in done:
    if not m.merged:
      result.add REntry(vs: m.vs, i: m.i, bc: m.bc, weight: m.weight, hasBc: m.hasBc)

proc sortEntries(c: Ctx, old: OldNodes, entries: seq[REntry], rp: seq[(int, REntry)], biasRight: bool): SubResult =
  var sortable, unsortable: seq[REntry]
  for e in entries:
    if e.hasBc: sortable.add e else: unsortable.add e
  unsortable.sort(proc(a, b: REntry): int = cmp(b.i, a.i))
  sortable.sort(proc(a, b: REntry): int =
    if a.bc < b.bc: return -1
    if a.bc > b.bc: return 1
    if not old.isNil:
      let cc = compareByOldOrder(old, c.lab[a.vs[0]], c.lab[b.vs[0]])
      if cc != 0: return cc
    if not biasRight: cmp(a.i, b.i) else: cmp(b.i, a.i))
  for (key, value) in rp:
    var k = -1
    for j, e in sortable:
      if e.vs[0] == key: k = j; break
    sortable.insert(value, k + 1)
  var vs: seq[seq[int]]
  var sum, weight = 0.0
  var idx = 0
  proc consume(idx: int): int =
    var i = idx
    while unsortable.len > 0 and unsortable[^1].i <= i:
      vs.add unsortable.pop().vs
      inc i
    i
  idx = consume(idx)
  for e in sortable:
    idx += e.vs.len
    vs.add e.vs
    sum += e.bc * e.weight
    weight += e.weight
    idx = consume(idx)
  for x in vs: result.vs.add x
  if truthy(weight):
    result.bc = sum / weight
    result.weight = weight
    result.hasBc = true

proc sortSubgraph(c: Ctx, lg: LG, lv: int, cg: CG, old: OldNodes, biasRight: bool): SubResult =
  let L = lg.nodes.len
  let bl = if lv < L: lg.blL[lv] else: -1
  let br = if lv < L: lg.brL[lv] else: -1
  var bcs: seq[BCEntry]
  for li in lg.kids[lv]:
    let m = lg.nodes[li]
    if bl >= 0 and (m == bl or m == br): continue
    let ins = lg.inList[li]
    if ins.len == 0:
      bcs.add BCEntry(v: m)
    else:
      var sum, weight = 0.0
      for (u, w) in ins:
        sum += w * float(c.ord[u])
        weight += w
      bcs.add BCEntry(v: m, bc: sum / weight, weight: weight, hasBc: true)
  var subgraphs = initTable[int, SubResult]()
  for en in bcs.mitems:
    let l2 = c.loc[en.v]
    if lg.kids[l2].len > 0:
      let sr = sortSubgraph(c, lg, l2, cg, old, biasRight)
      subgraphs[en.v] = sr
      if sr.hasBc:
        if en.hasBc:
          en.bc = (en.bc * en.weight + sr.bc * sr.weight) / (en.weight + sr.weight)
          en.weight += sr.weight
        else:
          en.bc = sr.bc; en.weight = sr.weight; en.hasBc = true
  var entries = resolveConflicts(c, bcs, cg)
  if subgraphs.len > 0:
    for en in entries.mitems:
      var nvs: seq[int]
      for x in en.vs:
        if x in subgraphs: nvs.add subgraphs[x].vs else: nvs.add x
      en.vs = nvs
  var rp: seq[(int, REntry)]
  var usedBias = false
  var i = 0
  while i < entries.len and not c.legacy:
    var j = i + 1
    while j < entries.len:
      if not (i < entries.len and j < entries.len) or not truthy(entries[i].bc) or not truthy(entries[j].bc):
        inc j; continue
      if entries[i].bc == entries[j].bc:
        let nameI = entries[i].vs[0]
        let nameJ = entries[j].vs[0]
        if c.isEdgeDummy[nameI] and c.isEdgeDummy[nameJ] and c.eoV[nameI] != -1 and c.eoV[nameJ] != -1 and
           c.eoV[nameI] == c.eoV[nameJ] and c.eoW[nameI] == c.eoW[nameJ]:
          if c.edgeRev[nameI]:
            rp.add (nameJ, entries[i])
            entries.delete(i)
            dec i
            break
          else:
            var has = false
            for (k, _) in rp:
              if k == nameI: has = true
            if not has:
              rp.add (nameI, entries[j])
              entries.delete(j)
              dec j
        else:
          usedBias = true
      inc j
    inc i
  result = sortEntries(c, old, entries, rp, biasRight)
  if bl >= 0 and br >= 0:
    result.vs = @[bl] & result.vs & @[br]
    let blPreds = lg.inList[c.loc[bl]]
    if blPreds.len > 0:
      let blPred = blPreds[0][0]
      let brPred = lg.inList[c.loc[br]][0][0]
      if not result.hasBc:
        result.bc = 0; result.weight = 0; result.hasBc = true
      result.bc = (result.bc * result.weight + float(c.ord[blPred]) + float(c.ord[brPred])) / (result.weight + 2)
      result.weight += 2
  result.usedBias = usedBias

proc addSubgraphConstraints(c: Ctx, lg: LG, cg: CG, vs: seq[int]) =
  let L = lg.nodes.len
  var prev = initTable[int, int]()
  var rootPrev = -1
  for v in vs:
    var child = lg.par[c.loc[v]]
    while child != -1:
      let parent = lg.par[child]
      var prevChild: int
      if parent != -1:
        prevChild = prev.getOrDefault(parent, -1)
        prev[parent] = child
      else:
        prevChild = rootPrev
        rootPrev = child
      if prevChild != -1 and prevChild != child:
        cgAdd(cg, lg.nodes[prevChild], lg.nodes[child])
        break
      child = parent

proc order*(g: Graph, opts: LayoutOptions = LayoutOptions(), old: OldNodes = nil) =
  if not opts.customOrder.isNil:
    opts.customOrder(g, proc(g2: Graph, o2: LayoutOptions, old2: OldNodes) = order(g2, o2, old2))
    return
  let (c, names) = buildCtx(g)
  c.legacy = opts.legacyOrder
  let old = if opts.legacyOrder: nil else: old
  var idOf = initTable[string, int]()
  for i, v in names: idOf[v] = i
  var maxR = 0
  for r in c.rank:
    if r != NoVal and r > maxR: maxR = r
  let down = buildLayerGraphs(c, rangeSeq(1, maxR + 1), true)
  let up = buildLayerGraphs(c, rangeSeq(maxR - 1, -1, -1), false)
  var cons: seq[(int, int)]
  for (l, r) in opts.constraints:
    cons.add (idOf.getOrDefault(l, -1), idOf.getOrDefault(r, -1))   # unknown names are ignored below
  proc sweep(lgs: seq[LG], switchBias: bool) =
    var biasRight = if c.legacy: switchBias else: true
    let cg = CG()
    for lg in lgs:
      for (a, b) in cons:
        if a >= 0 and b >= 0: cgAdd(cg, a, b)
      for i, m in lg.nodes: c.loc[m] = i
      let L = lg.nodes.len
      let sorted = sortSubgraph(c, lg, L, cg, old, biasRight)
      if switchBias and sorted.usedBias and not c.legacy: biasRight = not biasRight
      for i, v in sorted.vs: c.ord[v] = i
      addSubgraphConstraints(c, lg, cg, sorted.vs)
  var layering = initOrder(c, old)
  assignOrder(c, layering)
  if not opts.disableOptimalOrderHeuristic:
    var bestCC = Inf
    var best: seq[seq[int]]
    var i = 0
    var lastBest = 0
    while lastBest < 4:
      sweep((if i mod 2 == 1: down else: up), i mod 4 >= 2)
      layering = buildLayering(c)
      let cc = crossCount(c, layering)
      if cc < bestCC:
        lastBest = 0
        best = layering
        bestCC = cc
      elif cc == bestCC and not c.legacy:
        best = layering
      inc i; inc lastBest
    assignOrder(c, best)
  for m in 0 ..< c.n:
    if c.rank[m] != NoVal and c.ord[m] != NoVal: c.lab[m].order = c.ord[m]
