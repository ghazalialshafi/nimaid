import std/[tables, sets, algorithm, math, strutils, sequtils]
import graphlib, util

type
  Conflicts = Table[int, HashSet[int]]

proc positionX*(g: Graph, core: seq[string] = @[]) =
  ## Brandes-Köpf horizontal placement on integer ids / flat arrays. Writes node.x.
  let layering = buildLayerMatrix(g)
  var names: seq[string]
  var idOf = initTable[string, int]()
  for layer in layering:
    for v in layer:
      if v != "" and v notin idOf:
        idOf[v] = names.len; names.add v
  let n = names.len
  if n == 0: return
  var labels = newSeq[NodeLabel](n)
  var order = newSeq[int](n)
  var isDummy = newSeq[bool](n)
  var isBorder = newSeq[bool](n)
  var width = newSeq[float](n)
  var lpos = newSeq[int](n)           # 0 none/other, 1 'l', 2 'r'
  var btype = newSeq[int](n)          # 1 borderLeft, 2 borderRight
  var inCore = newSeq[bool](n)
  var preds = newSeq[seq[int]](n)
  var succs = newSeq[seq[int]](n)
  var hasBorder = false
  for i, v in names:
    let nl = g.node(v)
    labels[i] = nl
    order[i] = nl.order
    isDummy[i] = nl.dummy != ""
    isBorder[i] = nl.dummy == "border"
    if isBorder[i]: hasBorder = true
    width[i] = nl.width
    if nl.labelpos != "":
      case nl.labelpos.toLowerAscii
      of "l": lpos[i] = 1
      of "r": lpos[i] = 2
      else: discard
    if nl.borderType == "borderLeft": btype[i] = 1
    elif nl.borderType == "borderRight": btype[i] = 2
    inCore[i] = core.len > 0 and v in core
    for u in g.predecessors(v): preds[i].add idOf[u]
    for w in g.successors(v): succs[i].add idOf[w]
  var sortedIdx = toSeq(0 ..< n)
  sortedIdx.sort(proc(a, b: int): int = cmp(names[a], names[b]))
  var nameRank = newSeq[int](n)
  for r, i in sortedIdx: nameRank[i] = r
  var lay: seq[seq[int]]
  for layer in layering:
    var l: seq[int]
    for v in layer:
      if v != "": l.add idOf[v]
    lay.add l

  proc addC(c: var Conflicts, v, w: int) =
    var a = v
    var b = w
    if nameRank[a] > nameRank[b]: swap(a, b)
    c.mgetOrPut(a, initHashSet[int]()).incl b
  proc hasC(c: Conflicts, v, w: int): bool =
    var a = v
    var b = w
    if nameRank[a] > nameRank[b]: swap(a, b)
    a in c and b in c[a]

  # ---- type 1 conflicts
  var conflicts: Conflicts
  for li in 1 ..< lay.len:
    let prevLen = lay[li - 1].len
    let layer = lay[li]
    if layer.len == 0: continue
    var k0, scanPos = 0
    let lastNode = layer[^1]
    for i, v in layer:
      var w = -1
      if isDummy[v]:
        for u in preds[v]:
          if isDummy[u]: w = u; break
      let k1 = if w >= 0: order[w] else: prevLen
      if w >= 0 or v == lastNode:
        for si in scanPos .. i:
          let sn = layer[si]
          for u in preds[sn]:
            if (order[u] < k0 or k1 < order[u]) and not (isDummy[u] and isDummy[sn]):
              addC(conflicts, u, sn)
        scanPos = i + 1
        k0 = k1
  # ---- type 2 conflicts
  if hasBorder:
    var c2: Conflicts
    proc scan(south: seq[int], sp, se, pn, nn: int) =
      for i in sp ..< se:
        let v = south[i]
        if isDummy[v]:
          for u in preds[v]:
            if isDummy[u] and (order[u] < pn or order[u] > nn): addC(c2, u, v)
    for li in 1 ..< lay.len:
      let north = lay[li - 1]
      let south = lay[li]
      var prevNorth = -1
      var nextNorth = -1
      var southPos = 0
      for la, v in south:
        if isBorder[v] and preds[v].len > 0:
          nextNorth = order[preds[v][0]]
          scan(south, southPos, la, prevNorth, nextNorth)
          southPos = la
          prevNorth = nextNorth
        scan(south, southPos, south.len, nextNorth, north.len)
    for k, st in c2: conflicts[k] = st            # Object.assign semantics

  proc isInCorePath(v: int): bool =
    if core.len == 0: return false
    let nl = labels[v]
    if not nl.hasEdgeObj or nl.edgeLabel.isNil or nl.edgeLabel.reversed: return false
    let si = core.find(nl.edgeObj.v)
    let ti = core.find(nl.edgeObj.w)
    (si != -1 and ti != -1 and si == (ti + 1) mod core.len) or si == (ti - 1) mod core.len

  let nodeSep = g.label.nodesep
  let edgeSep = g.label.edgesep
  proc sep(v, w: int, reverseSep: bool): float =
    var sum = width[v] / 2
    var delta = 0.0
    if lpos[v] == 1: delta = -width[v] / 2
    elif lpos[v] == 2: delta = width[v] / 2
    if delta != 0: sum += (if reverseSep: delta else: -delta)
    delta = 0
    sum += (if isDummy[v]: edgeSep else: nodeSep) / 2
    sum += (if isDummy[w]: edgeSep else: nodeSep) / 2
    sum += width[w] / 2
    if lpos[w] == 1: delta = width[w] / 2
    elif lpos[w] == 2: delta = -width[w] / 2
    if delta != 0: sum += (if reverseSep: delta else: -delta)
    sum

  var xss: array[4, seq[float]]
  var root = newSeq[int](n)
  var align = newSeq[int](n)
  var pos = newSeq[int](n)
  var blockIdx = newSeq[int](n)        # root -> index into block arrays (-1 none)
  for vert in 0 .. 1:
    var adj = lay
    if vert == 1: adj.reverse()
    for horiz in 0 .. 1:
      if horiz == 1:
        for k in 0 ..< adj.len: adj[k].reverse()
      # vertical alignment
      for layer in adj:
        for o, v in layer:
          root[v] = v; align[v] = v; pos[v] = o
      for layer in adj:
        var prevIdx = -1
        var alreadyAligned = -1
        var hasShifted = false
        var modified = layer
        if core.len > 0:
          var ci = -1
          for i, v in layer:
            if inCore[v] or isInCorePath(v): ci = i; break
          if ci > 0:
            modified = @[layer[ci]] & layer[0 ..< ci] & layer[ci + 1 .. ^1]
            hasShifted = true
        for v in modified:
          var ws = if vert == 0: preds[v] else: succs[v]
          if ws.len > 0:
            if core.len > 0 and inCore[v]: ws = ws.filterIt(isInCorePath(it))
            if ws.len > 1: ws.sort(proc(a, b: int): int = cmp(pos[a], pos[b]))
            let mp = (ws.len - 1) / 2
            for i in int(floor(mp)) .. int(ceil(mp)):
              if i < 0 or i >= ws.len: continue
              let w = ws[i]
              let pw = pos[w]
              if align[v] == v and prevIdx < pw and pw != alreadyAligned and not hasC(conflicts, v, w):
                align[w] = v
                root[v] = root[w]
                align[v] = root[w]
                prevIdx = pw
                if hasShifted:
                  prevIdx = -1
                  alreadyAligned = pw
                  hasShifted = false
      # horizontal compaction (block graph on flat arrays)
      let reverseSep = horiz == 1
      for i in 0 ..< n: blockIdx[i] = -1
      var bnodes: seq[int]
      var efrom, eto: seq[int]
      var ew: seq[float]
      var inA, outA: seq[seq[int]]
      var emap = initTable[int64, int]()
      for layer in adj:
        var u = -1
        for v in layer:
          let vr = root[v]
          if blockIdx[vr] < 0:
            blockIdx[vr] = bnodes.len; bnodes.add vr; inA.add @[]; outA.add @[]
          if u >= 0:
            let ur = root[u]
            let key = int64(ur) * int64(n) + int64(vr)
            let sp = sep(v, u, reverseSep)
            if key in emap:
              let ei = emap[key]
              ew[ei] = max(sp, ew[ei])
            else:
              let ei = efrom.len
              emap[key] = ei
              efrom.add ur; eto.add vr; ew.add sp
              outA[blockIdx[ur]].add ei
              inA[blockIdx[vr]].add ei
          u = v
      var xs = newSeq[float](n)
      let bt = if reverseSep: 1 else: 2
      for pass in 1 .. 2:
        var stack = bnodes
        var visited = newSeq[bool](n)
        while stack.len > 0:
          let elem = stack.pop()
          if visited[elem]:
            if pass == 1:
              var m = 0.0
              for ei in inA[blockIdx[elem]]: m = max(m, xs[efrom[ei]] + ew[ei])
              xs[elem] = m
            else:
              var mn = Inf
              for ei in outA[blockIdx[elem]]: mn = min(mn, xs[eto[ei]] - ew[ei])
              if mn != Inf and btype[elem] != bt: xs[elem] = max(xs[elem], mn)
          else:
            visited[elem] = true
            stack.add elem
            if pass == 1:
              for ei in inA[blockIdx[elem]]: stack.add efrom[ei]
            else:
              for ei in outA[blockIdx[elem]]: stack.add eto[ei]
      var res = newSeq[float](n)
      for v in 0 ..< n: res[v] = xs[root[v]]
      if horiz == 1:
        for v in 0 ..< n: res[v] = -res[v]
      xss[vert * 2 + horiz] = res
  # align to the smallest-width layout, then balance
  var small = 0
  var smallW = Inf
  for k in 0 .. 3:
    var mx = -Inf
    var mn = Inf
    for v in 0 ..< n:
      let hw = width[v] / 2
      mx = max(xss[k][v] + hw, mx); mn = min(xss[k][v] - hw, mn)
    if mx - mn < smallW: smallW = mx - mn; small = k
  var aMin = Inf
  var aMax = -Inf
  for x in xss[small]: aMin = min(aMin, x); aMax = max(aMax, x)
  for k in 0 .. 3:
    if k == small: continue
    var xmn = Inf
    var xmx = -Inf
    for x in xss[k]: xmn = min(xmn, x); xmx = max(xmx, x)
    let delta = if k mod 2 == 0: aMin - xmn else: aMax - xmx
    if delta != 0:
      for v in 0 ..< n: xss[k][v] += delta
  var alIdx = -1
  case g.label.align.toLowerAscii
  of "ul": alIdx = 0
  of "ur": alIdx = 1
  of "dl": alIdx = 2
  of "dr": alIdx = 3
  else: discard
  for v in 0 ..< n:
    if alIdx >= 0: labels[v].x = xss[alIdx][v]
    else:
      var vals = [xss[0][v], xss[1][v], xss[2][v], xss[3][v]]
      vals.sort()
      labels[v].x = (vals[1] + vals[2]) / 2

proc positionY*(g: Graph) =
  let layering = buildLayerMatrix(g)
  let ranksep = g.label.ranksep
  let ra = g.label.rankalign
  var prevY = 0.0
  for layer in layering:
    var maxH = 0.0
    for v in layer: maxH = max(maxH, g.node(v).height)
    for v in layer:
      let n = g.node(v)
      if ra == "top": n.y = prevY + n.height / 2
      elif ra == "bottom": n.y = prevY + maxH - n.height / 2
      else: n.y = prevY + maxH / 2
    prevY += maxH + ranksep

proc position*(g0: Graph, core: seq[string] = @[]) =
  let g = asNonCompoundGraph(g0)
  positionY(g)
  positionX(g, core)
