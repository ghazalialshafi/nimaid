## Ranking: longest-path, tight-tree and network simplex.
## Implemented on flat integer arrays (no hashing / allocation in the pivot loop);
## the pivoting and tie-breaking rules are identical to dagre's.
import std/tables
import graphlib

type NS = ref object
  n: int
  rank: seq[int]
  tail, head, minlen: seq[int]
  weight: seq[float]
  adj: seq[seq[int]]          ## nodeEdges order: in-edges then out-edges
  inCount: seq[int]
  outAdj: seq[seq[int]]

proc build(g: Graph): (NS, seq[string]) =
  let names = g.nodes
  var id = initTable[string, int]()
  for i, v in names: id[v] = i
  var s = NS(n: names.len)
  s.rank = newSeq[int](s.n)
  s.adj = newSeq[seq[int]](s.n)
  s.outAdj = newSeq[seq[int]](s.n)
  s.inCount = newSeq[int](s.n)
  var inAdj = newSeq[seq[int]](s.n)
  var emap = initTable[(int, int), int]()
  for e in g.edges:
    let a = id[e.v]
    let b = id[e.w]
    let l = g.edge(e)
    let k = (a, b)
    if k in emap:
      let i = emap[k]
      s.minlen[i] = max(s.minlen[i], l.minlen)
      s.weight[i] += l.weight
    else:
      let i = s.tail.len
      emap[k] = i
      s.tail.add a; s.head.add b; s.minlen.add l.minlen; s.weight.add l.weight
      inAdj[b].add i
      s.outAdj[a].add i
  for v in 0 ..< s.n:
    s.adj[v] = inAdj[v] & s.outAdj[v]
    s.inCount[v] = inAdj[v].len
  (s, names)

proc slack(s: NS, e: int): int = s.rank[s.head[e]] - s.rank[s.tail[e]] - s.minlen[e]

proc longestPath(s: NS) =
  var visited = newSeq[bool](s.n)
  # iterative post-order DFS from every source
  var stackV, stackI: seq[int]
  for root in 0 ..< s.n:
    if s.inCount[root] != 0 or visited[root]: continue
    visited[root] = true
    stackV.add root; stackI.add 0
    while stackV.len > 0:
      let v = stackV[^1]
      let i = stackI[^1]
      if i < s.outAdj[v].len:
        stackI[^1] = i + 1
        let w = s.head[s.outAdj[v][i]]
        if not visited[w]:
          visited[w] = true
          stackV.add w; stackI.add 0
      else:
        var r = high(int)
        for e in s.outAdj[v]: r = min(r, s.rank[s.head[e]] - s.minlen[e])
        s.rank[v] = if r == high(int): 0 else: r
        stackV.setLen(stackV.len - 1); stackI.setLen(stackI.len - 1)

type Tree = object
  inTree: seq[bool]
  nodes: seq[int]
  edges: seq[int]             ## graph edge ids in tree-insertion order
  isTree: seq[bool]
  tadj: seq[seq[int]]

proc other(s: NS, e, v: int): int = (if s.tail[e] == v: s.head[e] else: s.tail[e])

proc tightTree(s: NS, t: var Tree): int =
  let snap = t.nodes.len
  var stackV, stackI: seq[int]
  for k in 0 ..< snap:
    stackV.add t.nodes[k]; stackI.add 0
    while stackV.len > 0:
      let v = stackV[^1]
      let i = stackI[^1]
      if i < s.adj[v].len:
        stackI[^1] = i + 1
        let e = s.adj[v][i]
        let w = s.other(e, v)
        if not t.inTree[w] and s.slack(e) == 0:
          t.inTree[w] = true
          t.nodes.add w
          t.edges.add e
          t.isTree[e] = true
          t.tadj[v].add e
          t.tadj[w].add e
          stackV.add w; stackI.add 0
      else:
        stackV.setLen(stackV.len - 1); stackI.setLen(stackI.len - 1)
  t.nodes.len

proc feasibleTree(s: NS): Tree =
  var t = Tree(inTree: newSeq[bool](s.n), isTree: newSeq[bool](s.tail.len), tadj: newSeq[seq[int]](s.n))
  if s.n == 0: return t
  t.inTree[0] = true
  t.nodes.add 0
  while tightTree(s, t) < s.n:
    var best = high(int)
    var be = -1
    for e in 0 ..< s.tail.len:
      if t.inTree[s.tail[e]] != t.inTree[s.head[e]]:
        let sl = s.slack(e)
        if sl < best: best = sl; be = e
    if be < 0: break
    let delta = if t.inTree[s.tail[be]]: best else: -best
    for v in t.nodes: s.rank[v] += delta
  t

proc networkSimplex(s: NS) =
  longestPath(s)
  var t = feasibleTree(s)
  let n = s.n
  var low = newSeq[int](n)
  var lim = newSeq[int](n)
  var par = newSeq[int](n)
  var parEdge = newSeq[int](n)
  var seen = newSeq[bool](n)
  var pre, post: seq[int]
  var cut = newSeq[float](s.tail.len)
  var stamp = newSeq[int](n)
  var curStamp = 0
  var stackV, stackI: seq[int]
  proc initLowLim() =
    for i in 0 ..< n: seen[i] = false
    pre.setLen(0); post.setLen(0)
    var next = 1
    let root = t.nodes[0]
    seen[root] = true; par[root] = -1; parEdge[root] = -1; low[root] = next
    pre.add root
    stackV.setLen(0); stackI.setLen(0)
    stackV.add root; stackI.add 0
    while stackV.len > 0:
      let v = stackV[^1]
      let i = stackI[^1]
      if i < t.tadj[v].len:
        stackI[^1] = i + 1
        let e = t.tadj[v][i]
        let w = s.other(e, v)
        if not seen[w]:
          seen[w] = true; par[w] = v; parEdge[w] = e; low[w] = next
          pre.add w
          stackV.add w; stackI.add 0
      else:
        lim[v] = next; inc next
        post.add v
        stackV.setLen(stackV.len - 1); stackI.setLen(stackI.len - 1)
  proc initCutValues() =
    for k in 0 ..< post.len - 1:
      let child = post[k]
      let p = par[child]
      let pe = parEdge[child]
      let childIsTail = s.tail[pe] == child
      var c = s.weight[pe]
      for e in s.adj[child]:
        let isOut = s.tail[e] == child
        let o = if isOut: s.head[e] else: s.tail[e]
        if o != p:
          let toHead = isOut == childIsTail
          let ow = s.weight[e]
          c += (if toHead: ow else: -ow)
          if t.isTree[e]:
            c += (if toHead: -cut[e] else: cut[e])
      cut[pe] = c
  proc renumber(r: int) =
    ## re-number low/lim and recompute ranks for the subtree rooted at r (the lca of the pivot cycle)
    inc curStamp
    let p = par[r]
    if p >= 0: stamp[p] = curStamp
    stamp[r] = curStamp
    var next = low[r]
    stackV.setLen(0); stackI.setLen(0)
    stackV.add r; stackI.add 0
    while stackV.len > 0:
      let v = stackV[^1]
      let i = stackI[^1]
      if i < t.tadj[v].len:
        stackI[^1] = i + 1
        let e = t.tadj[v][i]
        let w = s.other(e, v)
        if stamp[w] != curStamp:
          stamp[w] = curStamp
          par[w] = v; parEdge[w] = e; low[w] = next
          s.rank[w] = s.rank[v] + (if s.tail[e] == w: -s.minlen[e] else: s.minlen[e])
          stackV.add w; stackI.add 0
      else:
        lim[v] = next
        post[next - 1] = v
        inc next
        stackV.setLen(stackV.len - 1); stackI.setLen(stackI.len - 1)
  proc updateRanks() =
    for k in 1 ..< pre.len:
      let v = pre[k]
      let pe = parEdge[v]
      s.rank[v] = s.rank[par[v]] + (if s.tail[pe] == v: -s.minlen[pe] else: s.minlen[pe])
  if n == 0: return
  initLowLim()
  initCutValues()
  while true:
    var li = -1
    for k, e in t.edges:
      if cut[e] < 0: li = k; break
    if li < 0: break
    let e = t.edges[li]
    # enterEdge
    var tailNode = s.tail[e]
    var flip = false
    if lim[s.tail[e]] > lim[s.head[e]]:
      tailNode = s.head[e]
      flip = true
    let tl = low[tailNode]
    let tm = lim[tailNode]
    var best = high(int)
    var f = -1
    let subSize = tm - tl + 1
    proc consider(x: int) =
      let lt = lim[s.tail[x]]
      let lh = lim[s.head[x]]
      if flip == (tl <= lt and lt <= tm) and flip != (tl <= lh and lh <= tm):
        let sl = s.slack(x)
        if sl < best or (sl == best and x < f): best = sl; f = x
    if subSize * 2 <= n:
      for k in tl - 1 .. tm - 1:           # nodes of the subtree = post[low-1 .. lim-1]
        for x in s.adj[post[k]]: consider(x)
    else:
      for k in 0 ..< tl - 1:
        for x in s.adj[post[k]]: consider(x)
      for k in tm ..< n:
        for x in s.adj[post[k]]: consider(x)
    if f < 0: break
    # incremental cut-value update: only tree edges on the cycle closed by f change
    var left, right: seq[int]            # child nodes whose parent-edge is on the path
    var a = s.head[f]
    var b = s.tail[f]
    while a != b:
      if lim[a] < lim[b]: left.add a; a = par[a]
      else: right.add b; b = par[b]
    let lca = a
    var fwdE = false
    for c in left:
      if parEdge[c] == e: fwdE = s.tail[e] == c
    for c in right:
      if parEdge[c] == e: fwdE = s.tail[e] != c
    let ce = cut[e]
    for c in left:
      let te = parEdge[c]
      if te != e:
        let fwd = s.tail[te] == c
        cut[te] += (if fwd == fwdE: -ce else: ce)
    for c in right:
      let te = parEdge[c]
      if te != e:
        let fwd = s.tail[te] != c
        cut[te] += (if fwd == fwdE: -ce else: ce)
    cut[f] = -ce
    # exchange
    t.edges.delete(li)
    t.edges.add f
    t.isTree[e] = false
    t.isTree[f] = true
    for v in [s.tail[e], s.head[e]]:
      let k = t.tadj[v].find(e)
      t.tadj[v].delete(k)
    t.tadj[s.tail[f]].add f
    t.tadj[s.head[f]].add f
    renumber(lca)
    when defined(dagreVerifyNS):
      let saved = cut
      initCutValues()
      for x in t.edges:
        if abs(saved[x] - cut[x]) > 1e-9: raise newException(ValueError, "incremental cut value mismatch")

proc rank*(g: Graph) =
  ## Assigns `rank` to every node of the (non-compound, acyclic) graph `g`.
  if g.label.ranker == "none": return
  var (s, names) = build(g)
  case g.label.ranker
  of "tight-tree":
    longestPath(s); discard feasibleTree(s)
  of "longest-path": longestPath(s)
  else: networkSimplex(s)
  for i, v in names: g.node(v).rank = s.rank[i]
