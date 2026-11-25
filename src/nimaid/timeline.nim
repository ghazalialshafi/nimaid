## Timeline diagrams (Mermaid `timeline`): grammar from timeline.jison, layout from timelineRenderer.ts + svgDraw.js.
## Horizontal (LR) layout. `timeline TD` is accepted and drawn as LR.
import std/[strutils, math, options, sequtils]
import gfx, theme, painter, textmetrics, drawkit, chartheme, chartkit

type
  Period = object
    section: string
    text: string
    events: seq[string]

const NodeW = 150.0
const Pad = 20.0
const FontPx = 16.0

proc normBr(s: string): string =
  s.replace("<br/>", "<br>").replace("<br />", "<br>").replace("<BR>", "<br>")

proc wrapLines(text: string, width: float): seq[string] =
  ## svgDraw.wrap: greedy word wrap at `width`, `<br>` forces a break.
  var line: seq[string]
  for word in normBr(text).split({' ', '\t'}):
    if word.len == 0: continue
    var pieces: seq[string] = @[word]
    if "<br>" in word: pieces = word.replace("<br>", " <br> ").split(' ')
    for piece in pieces:
      if piece.len == 0: continue
      if piece == "<br>":
        result.add line.join(" "); line = @[]; continue
      line.add piece
      if textW(line.join(" "), FontPx) > width and line.len > 1:
        line.setLen(line.len - 1)
        result.add line.join(" ")
        line = @[piece]
  result.add line.join(" ")

proc blockHeight(lines: seq[string]): float = FontPx * 1.164 + float(lines.len - 1) * FontPx * 1.1

proc virtualHeight(text: string): float = blockHeight(wrapLines(text, NodeW)) + FontPx * 1.1 * 0.5 + Pad

proc parseTimeline(text, fmTitle: string): (string, seq[string], seq[Period]) =
  var title = fmTitle
  var sections: seq[string]
  var periods: seq[Period]
  var started = false
  var cur = ""
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    if l.strip().startsWith("#"): continue
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    let t = l.strip()
    if t.len == 0: continue
    if not started:
      if not t.toLowerAscii.startsWith("timeline"): raise newException(ChartError, "Parse error: expecting 'timeline'")
      started = true; continue
    let low = t.toLowerAscii
    if low.startsWith("title ") or low == "title": title = t[5 .. ^1].strip(); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    if low.startsWith("section "):
      cur = t[8 .. ^1].strip(); sections.add cur; continue
    var rest = t
    var periodText = ""
    if not t.startsWith(":"):
      let ci = t.find(':')
      if ci < 0: periodText = t; rest = ""
      else: periodText = t[0 ..< ci].strip(); rest = t[ci .. ^1]
      periods.add Period(section: cur, text: periodText)
    elif periods.len == 0:
      raise newException(ChartError, "Parse error: an event needs a period before it")
    # events: ':' followed by whitespace (or any ':' at the start) opens one
    var i = 0
    while i < rest.len:
      if rest[i] == ':':
        var j = i + 1
        while j < rest.len and not (rest[j] == ':' and (j + 1 >= rest.len or rest[j + 1] in {' ', '\t'})): inc j
        let ev = rest[i + 1 ..< j].strip()
        if ev.len > 0: periods[^1].events.add ev
        i = j
      else: inc i
  (title, sections, periods)

proc timelineScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let (title, sections, periods) = parseTimeline(text, fmTitle)
  let root = pvg_scene_new()
  var minX, minY = Inf
  var maxX, maxY = -Inf
  proc grow(x0, y0, x1, y1: float) =
    minX = min(minX, x0); minY = min(minY, y0); maxX = max(maxX, x1); maxY = max(maxY, y1)

  proc fillOf(i: int): Color = cv.color("cScale" & $(i mod 12))
  proc labelOf(i: int): Color = cv.color("cScaleLabel" & $(i mod 12))
  proc invOf(i: int): Color = cv.color("cScaleInv" & $(i mod 12))
  let lineColor = cv.color("cScaleLabel11")

  # ---- measuring pass
  var maxSectionHeight, maxTaskHeight, maxEventLineLength = 0.0
  for s in sections: maxSectionHeight = max(maxSectionHeight, virtualHeight(s) + 20)
  for p in periods:
    maxTaskHeight = max(maxTaskHeight, virtualHeight(p.text) + 20)
    var sum = 0.0
    for e in p.events: sum += virtualHeight(e)
    if p.events.len > 0: sum += float(p.events.len - 1) * 10
    maxEventLineLength = max(maxEventLineLength, sum)

  proc drawNode(x, y: float, txt: string, width, minH: float, colorIdx: int, bright: bool): float =
    ## draws one timeline node at (x, y); returns its height
    let lines = wrapLines(txt, NodeW)
    let h = max(blockHeight(lines) + FontPx * 1.1 * 0.5 + Pad, minH)
    let w = width + 2 * Pad
    let k = if bright: 1.2 else: 1.0
    let fill = brighten(fillOf(colorIdx), k)
    # 'M0 h-5 v-(h-5) q0,-5,5,-5 h(w-10) q5,0,5,5 v(h-5) H0 Z' : square bottom, 5px rounded top corners
    let sh = pvg_shape_new()
    let r = 5.0
    discard pvg_shape_move_to(sh, cfloat(x), cfloat(y + h))
    discard pvg_shape_line_to(sh, cfloat(x), cfloat(y + r))
    discard pvg_shape_cubic_to(sh, cfloat(x), cfloat(y + r * 0.4477), cfloat(x + r * 0.4477), cfloat(y), cfloat(x + r), cfloat(y))
    discard pvg_shape_line_to(sh, cfloat(x + w - r), cfloat(y))
    discard pvg_shape_cubic_to(sh, cfloat(x + w - r * 0.4477), cfloat(y), cfloat(x + w), cfloat(y + r * 0.4477), cfloat(x + w), cfloat(y + r))
    discard pvg_shape_line_to(sh, cfloat(x + w), cfloat(y + h))
    discard pvg_shape_close(sh)
    styleShape(sh, some(fill), none(Color))
    discard pvg_scene_add(root, sh)
    kPath(root, [(x, y + h), (x + w, y + h)], false, none(Color), some(brighten(invOf(colorIdx), k)), 3)
    var ty = y + Pad / 2 + FontPx
    for ln in lines:
      drawT(root, ln, x + w / 2, ty, FontPx, brighten(labelOf(colorIdx), k), vMiddle, aMiddle)
      ty += FontPx * 1.1
    grow(x, y, x + w, y + h)
    h

  let hasSections = sections.len > 0
  var masterX = 100.0
  var sectionNumber = 0
  proc drawTasks(ts: seq[Period], colorStart: int, x0, y0: float, noSections: bool) =
    var x = x0
    var color = colorStart
    var maxTH = maxTaskHeight
    for p in ts:
      let th = drawNode(x, y0, p.text, NodeW, maxTaskHeight, color, false)
      maxTH = max(maxTH, th)
      if p.events.len > 0:
        # the connector's group is created before the events in Mermaid, so it is painted underneath them
        let lx = x + 190 / 2
        let y1 = y0 + maxTH
        let y2 = y0 + maxTH + 100 + maxEventLineLength + 100
        kPath(root, [(lx, y1), (lx, y2)], false, none(Color), some(lineColor), 2, @[5.0, 5.0])
        arrowHead(root, lx, y2, 0, 1, 2, cv.color("textColor"))
        grow(lx - 1, y1, lx + 1, y2 + 2)
        var ey = y0 + 200
        for e in p.events:
          let eh = drawNode(x, ey, e, NodeW, 50, color, true)
          ey += 10 + eh
      x += 200
      if noSections: inc color

  if hasSections:
    var masterY = 50.0
    for s in sections:
      let ts = periods.filterIt(it.section == s)
      let w = 200.0 * float(max(ts.len, 1)) - 50
      discard drawNode(masterX, 50, s, w, maxSectionHeight, sectionNumber, false)
      masterY = 50 + maxSectionHeight + 50
      if ts.len > 0: drawTasks(ts, sectionNumber, masterX, masterY, false)
      masterX += 200.0 * float(max(ts.len, 1))
      inc sectionNumber
  else:
    drawTasks(periods, 0, masterX, 50, true)

  if not (minX < Inf): raise newException(ChartError, "Timeline has no periods")
  let bw = maxX - minX
  let depthY = if hasSections: maxSectionHeight + maxTaskHeight + 150 else: maxTaskHeight + 100
  let axisX2 = bw + 150
  kPath(root, [(50.0, depthY), (axisX2, depthY)], false, none(Color), some(lineColor), 4)
  arrowHead(root, axisX2, depthY, 1, 0, 4, cv.color("textColor"))
  grow(50, depthY - 2, axisX2 + 4, depthY + 2)
  if title.len > 0:
    let tpx = 4 * 0.52 * FontPx     # 4ex
    drawTextPx(root, title, bw / 2 - 50, 20, tpx, cv.color("textColor"), aStart)
    grow(bw / 2 - 50, 20 - tpx, bw / 2 - 50 + textW(title, tpx), 20 + tpx * 0.25)
  # viewBox = content bbox + 50 padding (setupGraphViewbox)
  (root, (minX: minX, minY: minY, maxX: maxX, maxY: maxY))
