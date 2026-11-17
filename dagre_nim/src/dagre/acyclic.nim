import std/[sets, tables, math]
import graphlib, util

proc dfsFAS(g: Graph, oldGraph: Graph, legacy = false): seq[Edge] =
  var fas: seq[Edge]
  var stack, visited: HashSet[string]
  var srcSet: HashSet[string]
  let srcs = g.sources
  if not oldGraph.isNil:
    for v in srcs: srcSet.incl v
  proc reached(node: string, ignore: Edge): bool =
    var local: HashSet[string]
    proc rev(v: string): bool =
      if v in srcSet: return true
      local.incl v
      for e in g.inEdges(v):
        if not (e.v == ignore.v and e.w == ignore.w) and e.v notin local:
          if rev(e.v): return true
      false
    rev(node)
  proc oldRank(v: string): int =
    let n = oldGraph.node(v)
    if n.isNil: NoVal else: n.rank
  proc dfs(v: string) =
    if v in visited: return
    visited.incl v
    stack.incl v
    for e in g.outEdges(v):
      var back = e.w in stack
      if not back and not oldGraph.isNil:
        let a = oldRank(v)
        let b = oldRank(e.w)
        if a != NoVal and b != NoVal and a > b and reached(e.w, e): back = true
      if back: fas.add e
      else: dfs(e.w)
    stack.excl v
  if not legacy:
    for v in srcs: dfs(v)
  for v in g.nodes: dfs(v)
  fas

proc greedyFAS(g: Graph): seq[Edge] =
  if g.nodeCount <= 1: return
  let names = g.nodes
  var id = initTable[string, int]()
  for i, v in names: id[v] = i
  let n = names.len
  type FE = object
    a, b: int
    w: int
  var fe: seq[FE]
  var fidx = initTable[(int, int), int]()
  var inD = newSeq[int](n)
  var outD = newSeq[int](n)
  var inL = newSeq[seq[int]](n)
  var outL = newSeq[seq[int]](n)
  var maxIn, maxOut = 0
  for e in g.edges:
    let a = id[e.v]
    let b = id[e.w]
    let w = int(g.edge(e).weight)
    if (a, b) in fidx: fe[fidx[(a, b)]].w += w
    else:
      fidx[(a, b)] = fe.len
      outL[a].add fe.len
      inL[b].add fe.len
      fe.add FE(a: a, b: b, w: w)
    outD[a] += w; inD[b] += w
    maxOut = max(maxOut, outD[a]); maxIn = max(maxIn, inD[b])
  let nb = maxOut + maxIn + 3
  let zeroIdx = maxIn + 1
  # linked-list buckets: node ids 0..n-1, sentinels n..n+nb-1
  var nxt = newSeq[int](n + nb)
  var prv = newSeq[int](n + nb)
  for b in 0 ..< nb: nxt[n + b] = n + b; prv[n + b] = n + b
  for i in 0 ..< n: prv[i] = -1; nxt[i] = -1
  proc unlink(e: int) =
    nxt[prv[e]] = nxt[e]; prv[nxt[e]] = prv[e]
    prv[e] = -1; nxt[e] = -1
  proc enqueue(b, e: int) =
    if prv[e] != -1 and nxt[e] != -1: unlink e
    let s = n + b
    nxt[e] = nxt[s]; prv[nxt[s]] = e; nxt[s] = e; prv[e] = s
  proc dequeue(b: int): int =
    let s = n + b
    let e = prv[s]
    if e == s: return -1
    unlink e
    e
  proc assign(e: int) =
    if outD[e] == 0: enqueue(0, e)
    elif inD[e] == 0: enqueue(nb - 1, e)
    else: enqueue(outD[e] - inD[e] + zeroIdx, e)
  var dead = newSeq[bool](n)
  var remaining = n
  for i in 0 ..< n: assign i
  proc removeNode(v: int, collect: bool, res: var seq[(int, int)]) =
    for ei in inL[v]:
      let u = fe[ei].a
      if dead[u]: continue
      if collect: res.add (u, v)
      outD[u] -= fe[ei].w
      assign u
    for ei in outL[v]:
      let w = fe[ei].b
      if dead[w]: continue
      inD[w] -= fe[ei].w
      assign w
    dead[v] = true
    dec remaining
  var results: seq[(int, int)]
  var dummy: seq[(int, int)]
  while remaining > 0:
    var e = dequeue(0)
    while e >= 0:
      removeNode(e, false, dummy); e = dequeue(0)
    e = dequeue(nb - 1)
    while e >= 0:
      removeNode(e, false, dummy); e = dequeue(nb - 1)
    if remaining > 0:
      for i in countdown(nb - 2, 1):
        let x = dequeue(i)
        if x >= 0:
          removeNode(x, true, results)
          break
  for (a, b) in results:
    result.add g.outEdges(names[a], names[b])

proc run*(g: Graph, oldGraph: Graph = nil, legacy = false) =
  let fas = if g.label.acyclicer == "greedy": greedyFAS(g) else: dfsFAS(g, oldGraph, legacy)
  for e in fas:
    let label = g.edge(e)
    g.removeEdge(e)
    label.forwardName = e.name
    label.reversed = true
    g.setEdge(e.w, e.v, label, uniqueId("rev"))

proc undo*(g: Graph) =
  for e in g.edges:
    let label = g.edge(e)
    if label.reversed:
      g.removeEdge(e)
      let fn = label.forwardName
      label.reversed = false
      label.forwardName = ""
      g.setEdge(e.w, e.v, label, fn)
