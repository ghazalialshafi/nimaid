## Git graphs: commit / branch / checkout / merge / cherry-pick, left-to-right lanes (Mermaid-style thick lines).
import std/[strutils, options, tables, math]
import gfx, theme, label, textmetrics, painter, drawkit

type
  Commit = object
    id, tag: string
    branch: int
    kind: int                 ## 0 normal, 1 reverse, 2 highlight, 3 merge
    parents: seq[int]
    mergeFrom: int            ## branch index of the merged-in side (merge commits)

  GitError* = object of CatchableError

proc attrOf(s, key: string): string =
  let k = s.find(key & ":")
  if k < 0: return ""
  var r = s[k + key.len + 1 .. ^1].strip()
  if r.startsWith("\""):
    let e = r.find('"', 1)
    return r[1 ..< (if e < 0: r.len else: e)]
  r.splitWhitespace()[0]

proc gitScene*(text: string, th: FlowTheme): (Pvg_Paint, DiagramBounds) =
  var branches = @["main"]
  var orders = @[0]
  var commits: seq[Commit]
  var head: seq[int] = @[-1]          # last commit index per branch
  var cur = 0
  var started = false
  var title = ""
  proc branchIdx(n: string): int =
    for i, b in branches:
      if b == n: return i
    -1
  proc newCommit(id, tag: string, kind: int, parents: seq[int], mergeFrom = -1) =
    let n = commits.len
    commits.add Commit(id: (if id.len > 0: id else: $n & "-" & toHex((n + 1) * 2654435761 mod 268435456, 7).toLowerAscii),
                       tag: tag, branch: cur, kind: kind, parents: parents, mergeFrom: mergeFrom)
    head[cur] = n
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    l = l.strip()
    if l.len == 0: continue
    let low = l.toLowerAscii
    if not started:
      if low.startsWith("gitgraph"): started = true; continue
      raise newException(GitError, "Parse error: expecting 'gitGraph'")
    if low.startsWith("title "): title = l[6 .. ^1].strip(); continue
    let word = low.split({' ', '\t'})[0]
    let rest = if l.len > word.len: l[word.len .. ^1].strip() else: ""
    case word
    of "commit":
      var kind = 0
      case attrOf(rest, "type").toUpperAscii
      of "REVERSE": kind = 1
      of "HIGHLIGHT": kind = 2
      else: discard
      var par: seq[int]
      if head[cur] >= 0: par.add head[cur]
      newCommit(attrOf(rest, "id"), attrOf(rest, "tag"), kind, par)
    of "branch":
      let name = rest.splitWhitespace()[0]
      if branchIdx(name) >= 0: raise newException(GitError, "branch '" & name & "' already exists")
      branches.add name
      let o = attrOf(rest, "order")
      orders.add (if o.len > 0: parseInt(o) else: branches.len - 1)
      head.add head[cur]              # new branch starts at the current commit
      cur = branches.len - 1
    of "checkout", "switch":
      let b = branchIdx(rest.splitWhitespace()[0])
      if b < 0: raise newException(GitError, "unknown branch '" & rest & "'")
      cur = b
    of "merge":
      let b = branchIdx(rest.splitWhitespace()[0])
      if b < 0: raise newException(GitError, "unknown branch '" & rest & "'")
      var par: seq[int]
      if head[cur] >= 0: par.add head[cur]
      if head[b] >= 0: par.add head[b]
      newCommit(attrOf(rest, "id"), attrOf(rest, "tag"), 3, par, b)
    of "cherry-pick":
      let src = attrOf(rest, "id")
      var si = -1
      for i, c in commits:
        if c.id == src: si = i
      if si < 0: raise newException(GitError, "cherry-pick: unknown commit '" & src & "'")
      var par: seq[int]
      if head[cur] >= 0: par.add head[cur]
      par.add si
      newCommit("", "cherry-pick", 0, par)
      commits[^1].id = commits[^1].id & "|" & src
    else: discard
  if not started: raise newException(GitError, "Parse error: expecting 'gitGraph'")

  # lane order
  var laneOf = newSeq[int](branches.len)
  var order: seq[int]
  for i in 0 ..< branches.len: order.add i
  for a in 0 ..< order.len:
    for b in a + 1 ..< order.len:
      if orders[order[b]] < orders[order[a]]: swap(order[a], order[b])
  for ln, bi in order: laneOf[bi] = ln
  var maxLabel = 40.0
  for c in commits:
    let lid = c.id.split('|')[0]
    maxLabel = max(maxLabel, float(measureLabel(lid, 12).w))
  let step = max(70.0, maxLabel + 24)
  let laneGap = 70.0
  var labelW = 0.0
  for b in branches: labelW = max(labelW, float(measureLabel(b, 14).w))
  let x0 = 24.0
  let palette = [hsl(240, 1.0, 0.4627), hsl(60, 1.0, 0.4353), hsl(80, 1.0, 0.4627), hsl(210, 1.0, 0.4627),
                 hsl(180, 1.0, 0.4627), hsl(150, 1.0, 0.4627), hsl(300, 1.0, 0.4627), hsl(0, 1.0, 0.4627)]
  proc col(bi: int): Color = palette[laneOf[bi] mod 8]
  proc px(i: int): float = x0 + float(i) * step
  proc py(bi: int): float = float(laneOf[bi]) * laneGap + 30
  let sc = pvg_scene_new()
  let endX = px(max(commits.len - 1, 0)) + 40
  # lanes + branch labels
  for bi in 0 ..< branches.len:
    let y = py(bi)
    kLine(sc, -10, y, endX, y, rgba(160, 160, 160), 1.0, @[2.0, 2.0])
    let w = float(measureLabel(branches[bi], 14).w) + 20
    kRect(sc, -10 - w - 12, y - 14, w, 28, some(col(bi)), none(Color), 0, 4.0)
    drawLabel(sc, branches[bi], -10 - w / 2 - 12, y, 14, rgba(255, 255, 255))
  # connections (drawn first so commits sit on top)
  for i, c in commits:
    for k, p in c.parents:
      let x1 = px(p)
      let y1 = py(commits[p].branch)
      let x2 = px(i)
      let y2 = py(c.branch)
      let src = if k == 0 and c.kind != 3: c.branch else: (if c.kind == 3: c.mergeFrom else: commits[p].branch)
      let colr = if k == 0 and commits[p].branch == c.branch: col(c.branch) else: col(if c.kind == 3 and k == 1: c.mergeFrom else: c.branch)
      if abs(y1 - y2) < 1: kLine(sc, x1, y1, x2, y2, colr, 8.0, @[], true)
      else:
        let mx = (x1 + x2) / 2
        kCurve(sc, x1, y1, mx, y1, mx, y2, x2, y2, colr, 8.0)
  for i, c in commits:
    let x = px(i)
    let y = py(c.branch)
    let cc = col(c.branch)
    let light = rgba(236, 236, 255)
    case c.kind
    of 1:
      kCircle(sc, x, y, 10, some(light), some(cc), 3.0)
      kLine(sc, x - 5, y - 5, x + 5, y + 5, cc, 3.0)
      kLine(sc, x - 5, y + 5, x + 5, y - 5, cc, 3.0)
    of 2:
      kRect(sc, x - 10, y - 10, 20, 20, some(light), some(cc), 3.0)
      kRect(sc, x - 5, y - 5, 10, 10, some(cc), none(Color))
    of 3:
      kCircle(sc, x, y, 9, some(cc), some(cc), 2.0)
      kCircle(sc, x, y, 5, some(light), some(light), 1.0)
    else:
      kCircle(sc, x, y, 10, some(light), some(cc), 3.0)
    let lid = c.id.split('|')[0]
    drawLabel(sc, lid, x, y + 28, 12, th.textColor)
    if c.tag.len > 0:
      let tw = float(measureLabel(c.tag, 11).w) + 14
      kRect(sc, x - tw / 2, y - 40, tw, 20, some(rgba(236, 236, 255)), some(rgba(147, 112, 219)), 1.0, 4.0)
      drawLabel(sc, c.tag, x, y - 30, 11, th.textColor)
  let h = float(branches.len - 1) * laneGap + 90
  if title.len > 0: drawLabel(sc, title, (endX - labelW) / 2, -14, 18, th.titleColor)
  (sc, (-(labelW + 46), (if title.len > 0: -30.0 else: -20.0), endX + 10, h))
