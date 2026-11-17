## Mermaid sequence diagrams: parser + DB (from sequenceDiagram.jison / sequenceDb.ts) and
## layout + painting following sequenceRenderer.ts / svgDraw.js with Mermaid's default config.
import std/[strutils, tables, math, options]
import gfx, theme, label, textmetrics, painter, styles, preprocess

type
  LT* = enum
    ltSolid, ltDotted, ltSolidCross, ltDottedCross, ltSolidOpen, ltDottedOpen, ltSolidPoint, ltDottedPoint,
    ltBidirSolid, ltBidirDotted, ltNote,
    ltLoopStart, ltLoopEnd, ltAltStart, ltAltElse, ltAltEnd, ltOptStart, ltOptEnd,
    ltParStart, ltParAnd, ltParEnd, ltRectStart, ltRectEnd, ltCritStart, ltCritOption, ltCritEnd,
    ltBreakStart, ltBreakEnd, ltActiveStart, ltActiveEnd, ltAutonumber

  Placement* = enum plLeft, plRight, plOver

  SeqActor* = ref object
    id*, desc*, draw*: string
    x*, y*, width*, height*, margin*: float
    prev*, next*: string
    box*: int

  SeqMsg* = object
    kind*: LT
    frm*, to*, text*: string
    placement*: Placement
    numStart*, numStep*: int
    numVisible*: bool

  SeqBox* = object
    name*: string
    color*: string
    hasColor*: bool
    actors*: seq[string]

  SeqDoc* = ref object
    title*: string
    actors*: OrderedTable[string, SeqActor]
    msgs*: seq[SeqMsg]
    boxes*: seq[SeqBox]
    curBox*: int

  SeqParseError* = object of CatchableError

proc seqFail(m: string) {.noreturn.} = raise newException(SeqParseError, m)

# ---------------------------------------------------------------------------
# parser / DB
# ---------------------------------------------------------------------------
proc addActor(d: SeqDoc, id: string, desc = "", draw = "") =
  let id = id.strip()
  if id.len == 0: seqFail("Parse error: empty participant name")
  if id in d.actors:
    let a = d.actors[id]
    if desc.len > 0: a.desc = desc
    if draw.len > 0: a.draw = draw
    return
  var prevId = ""
  for k in d.actors.keys: prevId = k
  let a = SeqActor(id: id, desc: (if desc.len > 0: desc else: id), draw: (if draw.len > 0: draw else: "participant"),
                   prev: prevId, box: -1)
  if prevId.len > 0: d.actors[prevId].next = id
  if d.curBox >= 0:
    a.box = d.curBox
    d.boxes[d.curBox].actors.add id
  d.actors[id] = a

const arrowTokens = [("<<-->>", ltBidirDotted), ("<<->>", ltBidirSolid), ("-->>", ltDotted), ("->>", ltSolid),
                     ("--x", ltDottedCross), ("-x", ltSolidCross), ("--)", ltDottedPoint), ("-)", ltSolidPoint),
                     ("-->", ltDottedOpen), ("->", ltSolidOpen)]

proc cleanText(s: string): string =
  var t = s.strip()
  for pre in [":wrap:", ":nowrap:", "wrap:", "nowrap:"]:
    if t.startsWith(pre):
      t = t[pre.len .. ^1].strip()
      break
  t.replace("\x01", "#").replace("\x02", ";")

proc parseSequence*(textIn: string): SeqDoc =
  var text = textIn.replace("\r\n", "\n").replace('\r', '\n')
  # protect #entity; so '#' (comment) and ';' (separator) inside them survive
  var prot = ""
  var i = 0
  while i < text.len:
    if text[i] == '#':
      var j = i + 1
      while j < text.len and (text[j].isAlphaNumeric): inc j
      if j > i + 1 and j < text.len and text[j] == ';':
        prot.add "\x01" & text[i + 1 ..< j] & "\x02"
        i = j + 1
        continue
    prot.add text[i]
    inc i
  result = SeqDoc(actors: initOrderedTable[string, SeqActor](), curBox: -1)
  let d = result
  var stack: seq[string]
  var started = false
  var pendingLines: seq[string]
  for rawLine in prot.split('\n'):
    for stmt in rawLine.split(';'):
      var s = stmt
      let hash = s.find('#')
      if hash >= 0: s = s[0 ..< hash]
      let pc = s.find("%%")
      if pc >= 0: s = s[0 ..< pc]
      s = s.strip()
      if s.len == 0: continue
      pendingLines.add s
  var autonumberTitle = ""
  for s in pendingLines:
    let lower = s.toLowerAscii
    let word = lower.split({' ', '\t'})[0]
    let rest = if s.len > word.len: s[word.len .. ^1].strip() else: ""
    if not started:
      if word == "sequencediagram": started = true; continue
      seqFail("Parse error: expecting 'sequenceDiagram'")
    case word
    of "title", "title:":
      d.title = cleanText(rest)
    of "acctitle:", "accdescr:", "acctitle", "accdescr": discard
    of "autonumber":
      var m = SeqMsg(kind: ltAutonumber, numVisible: true, numStep: 1)
      let parts = rest.splitWhitespace()
      if parts.len >= 1 and parts[0].toLowerAscii == "off": m.numVisible = false
      elif parts.len >= 1:
        try:
          m.numStart = parseInt(parts[0])
          if parts.len >= 2: m.numStep = parseInt(parts[1])
        except ValueError: seqFail("Parse error: bad autonumber")
      d.msgs.add m
    of "participant", "actor":
      var name = rest
      var desc = ""
      let ai = name.toLowerAscii.find(" as ")
      if ai >= 0:
        desc = cleanText(name[ai + 4 .. ^1])
        name = name[0 ..< ai]
      let atp = name.find("@{")
      if atp >= 0: name = name[0 ..< atp]
      d.addActor(name.strip(), desc, word)
    of "create":
      let parts = rest.splitWhitespace(maxsplit = 1)
      if parts.len < 2: seqFail("Parse error: create needs participant|actor")
      var name = parts[1]
      var desc = ""
      let ai = name.toLowerAscii.find(" as ")
      if ai >= 0:
        desc = cleanText(name[ai + 4 .. ^1])
        name = name[0 ..< ai]
      d.addActor(name.strip(), desc, parts[0].toLowerAscii)
    of "destroy": discard
    of "box":
      var b = SeqBox(name: rest)
      let rl = rest.toLowerAscii
      var colorPart = ""
      if rl.startsWith("rgb") or rl.startsWith("hsl"):
        let cp = rest.find(')')
        if cp > 0:
          colorPart = rest[0 .. cp]
          b.name = rest[cp + 1 .. ^1].strip()
      else:
        let w0 = rest.splitWhitespace()
        if w0.len > 0:
          var c: Color
          if w0[0].toLowerAscii == "transparent" or tryParseColor(w0[0], c):
            colorPart = w0[0]
            b.name = rest[w0[0].len .. ^1].strip()
      if colorPart.len > 0: b.color = colorPart; b.hasColor = true
      d.boxes.add b
      d.curBox = d.boxes.len - 1
      stack.add "box"
    of "loop", "opt", "alt", "par", "par_over", "critical", "break", "rect":
      let k = case word
        of "loop": ltLoopStart
        of "opt": ltOptStart
        of "alt": ltAltStart
        of "critical": ltCritStart
        of "break": ltBreakStart
        of "rect": ltRectStart
        else: ltParStart
      d.msgs.add SeqMsg(kind: k, text: cleanText(rest))
      stack.add word
    of "else": d.msgs.add SeqMsg(kind: ltAltElse, text: cleanText(rest))
    of "and": d.msgs.add SeqMsg(kind: ltParAnd, text: cleanText(rest))
    of "option": d.msgs.add SeqMsg(kind: ltCritOption, text: cleanText(rest))
    of "end":
      if stack.len == 0: seqFail("Parse error: unexpected 'end'")
      let k = stack.pop()
      case k
      of "box": d.curBox = -1
      of "loop": d.msgs.add SeqMsg(kind: ltLoopEnd)
      of "opt": d.msgs.add SeqMsg(kind: ltOptEnd)
      of "alt": d.msgs.add SeqMsg(kind: ltAltEnd)
      of "critical": d.msgs.add SeqMsg(kind: ltCritEnd)
      of "break": d.msgs.add SeqMsg(kind: ltBreakEnd)
      of "rect": d.msgs.add SeqMsg(kind: ltRectEnd)
      else: d.msgs.add SeqMsg(kind: ltParEnd)
    of "activate", "deactivate":
      d.addActor(rest)
      d.msgs.add SeqMsg(kind: (if word == "activate": ltActiveStart else: ltActiveEnd), frm: rest.strip())
    of "links", "link", "properties", "details": discard
    of "note":
      var r = rest
      let rl = r.toLowerAscii
      var pl = plOver
      if rl.startsWith("left of "): pl = plLeft; r = r[8 .. ^1]
      elif rl.startsWith("right of "): pl = plRight; r = r[9 .. ^1]
      elif rl.startsWith("over "): pl = plOver; r = r[5 .. ^1]
      else: seqFail("Parse error: note needs 'left of', 'right of' or 'over'")
      let ci = r.find(':')
      if ci < 0: seqFail("Parse error: note needs ': text'")
      let actors = r[0 ..< ci].split(',')
      let ntext = cleanText(r[ci + 1 .. ^1])
      for a in actors: d.addActor(a.strip())
      d.msgs.add SeqMsg(kind: ltNote, frm: actors[0].strip(), to: actors[^1].strip(), placement: pl, text: ntext)
    else:
      # signal:  A <arrow> [+|-] B : text
      let ci = s.find(':')
      let head = if ci >= 0: s[0 ..< ci] else: s
      let mtext = if ci >= 0: cleanText(s[ci + 1 .. ^1]) else: ""
      var found = false
      var p = 0
      while p < head.len and not found:
        for (tok, lt) in arrowTokens:
          if head.continuesWith(tok, p):
            let frm = head[0 ..< p].strip()
            var after = head[p + tok.len .. ^1].strip()
            var act = false
            var deact = false
            if after.startsWith("+"):
              act = true
              after = after[1 .. ^1].strip()
            elif after.startsWith("-"):
              deact = true
              after = after[1 .. ^1].strip()
            if frm.len == 0 or after.len == 0: seqFail("Parse error: bad message '" & s & "'")
            d.addActor(frm)
            d.addActor(after)
            d.msgs.add SeqMsg(kind: lt, frm: frm, to: after, text: mtext)
            if act: d.msgs.add SeqMsg(kind: ltActiveStart, frm: after)
            if deact: d.msgs.add SeqMsg(kind: ltActiveEnd, frm: frm)
            found = true
            break
        inc p
      if not found: seqFail("Parse error: unrecognised statement '" & s & "'")
  if not started: seqFail("Parse error: expecting 'sequenceDiagram'")
  if stack.len > 0: seqFail("Parse error: missing 'end'")
  # assign boxes to actors (boxes list holds start entries and \0end markers; actors declared inside belong to box)
  # (kept simple: box membership by declaration order)
  var bi = -1
  discard bi

# ---------------------------------------------------------------------------
# layout + paint
# ---------------------------------------------------------------------------
const
  diagramMarginX = 50.0
  diagramMarginY = 10.0
  actorMargin = 50.0
  confWidth = 150.0
  confHeight = 65.0
  boxMargin = 10.0
  boxTextMargin = 5.0
  noteMargin = 10.0
  messageMargin = 35.0
  wrapPadding = 10.0
  labelBoxWidth = 50.0
  labelBoxHeight = 20.0
  activationWidth = 10.0
  actorFontSize = 14.0
  noteFontSize = 14.0
  messageFontSize = 16.0
  bottomMarginAdj = 1.0
  lineHeightFactor = 1.0625

var
  cActorBkg, cActorBorder, cSignal, cNoteBkg, cNoteBorder, cActBkg, cActBorder, cLifeline, cText: Color
  cNoteText, cSignalText, cLoopText, cLabelBoxBkg, cLabelBoxBorder, cSeqNo: Color

proc splitBreaks(s: string): seq[string] = labelText(s).split('\n')

proc dims(text: string, size: float): (float, float) =
  let lines = splitBreaks(decodeEntities(text))
  var w = 0.0
  for l in lines: w = max(w, float(measureLabel(l, float32(size)).w))
  (w, float(lines.len) * size * lineHeightFactor)

type
  Loop = ref object
    startx, starty, stopx, stopy: float
    title: string
    sections: seq[float]
    sectionTitles: seq[string]
    fill: string
    hasFill: bool

  Activation = object
    startx, starty, stopx: float
    actor: string

  Bounds = object
    sx, sy, ex, ey: float
    vpos: float
    items: seq[Loop]
    acts: seq[Activation]

proc newBounds(): Bounds = Bounds(sx: NaN, sy: NaN, ex: NaN, ey: NaN)

proc umin(c: var float, v: float) = (if c.isNaN or v < c: c = v)
proc umax(c: var float, v: float) = (if c.isNaN or v > c: c = v)

proc updateBounds(b: var Bounds, sx, sy, ex, ey: float) =
  var cnt = 0
  for it in b.items:
    inc cnt
    let n = float(b.items.len - cnt + 1)
    it.starty = (if it.starty.isNaN: sy - n * boxMargin else: min(it.starty, sy - n * boxMargin))
    it.stopy = (if it.stopy.isNaN: ey + n * boxMargin else: max(it.stopy, ey + n * boxMargin))
    umin(b.sx, sx - n * boxMargin)
    umax(b.ex, ex + n * boxMargin)
    it.startx = (if it.startx.isNaN: sx - n * boxMargin else: min(it.startx, sx - n * boxMargin))
    it.stopx = (if it.stopx.isNaN: ex + n * boxMargin else: max(it.stopx, ex + n * boxMargin))
    umin(b.sy, sy - n * boxMargin)
    umax(b.ey, ey + n * boxMargin)
  for _ in b.acts:
    inc cnt
    let n = float(b.items.len - cnt + 1)
    umin(b.sx, sx - n * boxMargin)
    umax(b.ex, ex + n * boxMargin)

proc insert(b: var Bounds, x1, y1, x2, y2: float) =
  let sx = min(x1, x2)
  let ex = max(x1, x2)
  let sy = min(y1, y2)
  let ey = max(y1, y2)
  umin(b.sx, sx)
  umin(b.sy, sy)
  umax(b.ex, ex)
  umax(b.ey, ey)
  b.updateBounds(sx, sy, ex, ey)

proc bump(b: var Bounds, v: float) =
  b.vpos += v
  umax(b.ey, b.vpos)

# --- tiny drawing helpers --------------------------------------------------
proc shapeFill(sh: Pvg_Paint, c: Color) = discard pvg_shape_set_fill_color(sh, c.r, c.g, c.b, c.a)
proc shapeStroke(sh: Pvg_Paint, c: Color, w: float, dash: seq[float] = @[]) =
  discard pvg_shape_set_stroke_width(sh, cfloat(w))
  discard pvg_shape_set_stroke_color(sh, c.r, c.g, c.b, c.a)
  if dash.len > 0:
    var d = newSeq[cfloat](dash.len)
    for i, v in dash: d[i] = cfloat(v)
    discard pvg_shape_set_stroke_dash(sh, addr d[0], uint32(d.len), 0.0)

proc dRect(sc: Pvg_Paint, x, y, w, h: float, fill: Option[Color], stroke: Option[Color], sw = 1.0, r = 0.0) =
  let sh = pvg_shape_new()
  discard pvg_shape_append_rect(sh, cfloat(x), cfloat(y), cfloat(w), cfloat(h), cfloat(r), cfloat(r), true)
  if fill.isSome: sh.shapeFill(fill.get)
  if stroke.isSome: sh.shapeStroke(stroke.get, sw)
  discard pvg_scene_add(sc, sh)

proc dLine(sc: Pvg_Paint, x1, y1, x2, y2: float, c: Color, w: float, dash: seq[float] = @[]) =
  let sh = pvg_shape_new()
  discard pvg_shape_move_to(sh, cfloat(x1), cfloat(y1))
  discard pvg_shape_line_to(sh, cfloat(x2), cfloat(y2))
  sh.shapeStroke(c, w, dash)
  discard pvg_scene_add(sc, sh)

proc dPoly(sc: Pvg_Paint, pts: openArray[(float, float)], fill: Option[Color], stroke: Option[Color], sw = 1.0) =
  let sh = pvg_shape_new()
  for i, p in pts:
    if i == 0: discard pvg_shape_move_to(sh, cfloat(p[0]), cfloat(p[1]))
    else: discard pvg_shape_line_to(sh, cfloat(p[0]), cfloat(p[1]))
  discard pvg_shape_close(sh)
  if fill.isSome: sh.shapeFill(fill.get)
  if stroke.isSome: sh.shapeStroke(stroke.get, sw)
  discard pvg_scene_add(sc, sh)

proc dCircle(sc: Pvg_Paint, cx, cy, r: float, fill: Option[Color], stroke: Option[Color], sw = 1.0) =
  let sh = pvg_shape_new()
  discard pvg_shape_append_circle(sh, cfloat(cx), cfloat(cy), cfloat(r), cfloat(r), true)
  if fill.isSome: sh.shapeFill(fill.get)
  if stroke.isSome: sh.shapeStroke(stroke.get, sw)
  discard pvg_scene_add(sc, sh)

proc textLines(sc: Pvg_Paint, text: string, cx, top, size: float, color: Color) =
  ## centred multi-line text whose first line box starts at `top`, pitch = size * 1.0625
  let lh = size * lineHeightFactor
  for i, l in splitBreaks(decodeEntities(text)):
    drawLabel(sc, l, cx, top + (float(i) + 0.5) * lh, size, color)

proc arrowHead(sc: Pvg_Paint, x, y, dir: float, kind: LT) =
  ## tip at (x, y); dir = +1 pointing right, -1 pointing left
  case kind
  of ltSolid, ltDotted, ltBidirSolid, ltBidirDotted:
    dPoly(sc, [(x, y), (x - dir * 12, y - 5), (x - dir * 12, y + 5)], some(cSignal), some(cSignal), 1.0)
  of ltSolidCross, ltDottedCross:
    let cx = x - dir * 5
    dLine(sc, cx - 4.5, y - 4.5, cx + 4.5, y + 4.5, cSignal, 1.5)
    dLine(sc, cx - 4.5, y + 4.5, cx + 4.5, y - 4.5, cSignal, 1.5)
  of ltSolidPoint, ltDottedPoint:
    dPoly(sc, [(x, y), (x - dir * 8, y - 6), (x - dir * 5, y), (x - dir * 8, y + 6)], some(cSignal), some(cSignal), 1.0)
  else: discard

proc drawActorBox(sc: Pvg_Paint, a: SeqActor, y: float) =
  if a.draw == "actor":
    let cx = a.x + a.width / 2
    dCircle(sc, cx, y + 14, 12, some(cActorBkg), some(cActorBorder), 1.0)
    dLine(sc, cx, y + 26, cx, y + 42, cActorBorder, 1.5)
    dLine(sc, cx - 17, y + 33, cx + 17, y + 33, cActorBorder, 1.5)
    dLine(sc, cx, y + 42, cx - 13, y + 54, cActorBorder, 1.5)
    dLine(sc, cx, y + 42, cx + 13, y + 54, cActorBorder, 1.5)
    textLines(sc, a.desc, cx, y + a.height - 11, actorFontSize, cText)
  else:
    dRect(sc, a.x, y, a.width, a.height, some(cActorBkg), some(cActorBorder), 1.0, 3.0)
    let (_, th) = dims(a.desc, actorFontSize)
    textLines(sc, a.desc, a.x + a.width / 2, y + (a.height - th) / 2, actorFontSize, cText)

proc layoutAndPaint*(doc: SeqDoc, th: FlowTheme): (Pvg_Paint, painter.DiagramBounds) =
  cActorBkg = th.actorBkg; cActorBorder = th.actorBorder; cSignal = th.signal
  cNoteBkg = th.noteBkg; cNoteBorder = th.noteBorder; cActBkg = th.activationBkg
  cActBorder = th.activationBorder; cLifeline = th.actorLine; cText = th.actorText
  cNoteText = th.noteText; cSignalText = th.signalText; cLoopText = th.loopText
  cLabelBoxBkg = th.labelBoxBkg; cLabelBoxBorder = th.labelBoxBorder; cSeqNo = th.seqNumber
  let root = pvg_scene_new()
  let bgLayer = pvg_scene_new()
  let lifeLayer = pvg_scene_new()
  let topLayer = pvg_scene_new()
  let midLayer = pvg_scene_new()
  let msgLayer = pvg_scene_new()
  let botLayer = pvg_scene_new()
  for l in [bgLayer, lifeLayer, topLayer, midLayer, msgLayer, botLayer]: discard pvg_scene_add(root, l)

  var actors = doc.actors
  var keys: seq[string]
  for k in actors.keys: keys.add k

  # --- actor sizes + margins -------------------------------------------------
  var maxH = 0.0
  for k in keys:
    let a = actors[k]
    let (tw, _) = dims(a.desc, actorFontSize)
    a.width = max(confWidth, tw + 2 * wrapPadding)
    a.height = confHeight
    a.margin = actorMargin
    maxH = max(maxH, a.height)
  var maxMsgW = initTable[string, float]()
  proc setMax(k: string, v: float) = maxMsgW[k] = max(maxMsgW.getOrDefault(k), v)
  for m in doc.msgs:
    if m.kind in {ltSolid .. ltBidirDotted} or m.kind == ltNote:
      if m.frm notin actors or m.to notin actors: continue
      let toA = actors[m.to]
      let isNote = m.kind == ltNote
      if isNote and m.placement == plLeft and toA.prev.len == 0: continue
      if isNote and m.placement == plRight and toA.next.len == 0: continue
      let (tw, _) = dims(m.text, if isNote: noteFontSize else: messageFontSize)
      let mw = tw + 2 * wrapPadding
      if not isNote and m.frm == toA.next: setMax(m.to, mw)
      elif not isNote and m.frm == toA.prev: setMax(m.frm, mw)
      elif not isNote and m.frm == m.to:
        setMax(m.frm, mw / 2)
        setMax(m.to, mw / 2)
      elif isNote and m.placement == plRight: setMax(m.frm, mw)
      elif isNote and m.placement == plLeft: setMax(toA.prev, mw)
      elif isNote and m.placement == plOver:
        if m.frm == m.to:
          setMax(m.frm, mw / 2)
          if toA.prev.len > 0: setMax(toA.prev, mw / 2)
        else:
          setMax(m.frm, mw / 2)
  for k, mw in maxMsgW:
    if k notin actors: continue
    let a = actors[k]
    if a.next.len > 0:
      a.margin = max(mw + actorMargin - a.width / 2 - actors[a.next].width / 2, actorMargin)
    else:
      a.margin = max(mw + actorMargin - a.width / 2, actorMargin)

  # --- boxes (only whole-diagram box title room is reserved) --------------------
  var b = newBounds()
  var hasBoxes = false
  hasBoxes = doc.boxes.len > 0
  var topY = 0.0
  if hasBoxes: topY = boxMargin + 20
  var px = 0.0
  for k in keys:
    let a = actors[k]
    a.x = px
    a.y = topY
    px += a.width + a.margin
    b.insert(a.x, a.y, a.x + a.width, a.y + a.height)
  b.vpos = topY + maxH

  # --- main loop ---------------------------------------------------------------------
  type MsgDraw = object
    kind: LT
    startx, stopx, lineY: float
    text: string
    starty: float
    seqNo: int
    showNo: bool
    frm: string
  var toDraw: seq[MsgDraw]
  var seqIndex = 1
  var seqStep = 1
  var seqVisible = false
  var backgrounds: seq[(Loop, string)]
  let mf = messageFontSize

  proc actBounds(id: string): (float, float) =
    let a = actors[id]
    let c = a.x + a.width / 2
    var l = Inf
    var r = -Inf
    for ac in b.acts:
      if ac.actor == id:
        l = min(l, ac.startx)
        r = max(r, ac.stopx)
    if l == Inf: (c, c) else: (l, r)

  proc drawLoopFrame(lp: Loop, kind: string, sc: Pvg_Paint) =
    let dash = @[2.0, 2.0]
    let sx = lp.startx
    let ex = lp.stopx
    dLine(sc, sx, lp.starty, ex, lp.starty, cLabelBoxBorder, 2.0, dash)
    dLine(sc, ex, lp.starty, ex, lp.stopy, cLabelBoxBorder, 2.0, dash)
    dLine(sc, sx, lp.stopy, ex, lp.stopy, cLabelBoxBorder, 2.0, dash)
    dLine(sc, sx, lp.starty, sx, lp.stopy, cLabelBoxBorder, 2.0, dash)
    for sy in lp.sections: dLine(sc, sx, sy, ex, sy, cLabelBoxBorder, 2.0, dash)
    dPoly(sc, [(sx, lp.starty), (sx + labelBoxWidth, lp.starty), (sx + labelBoxWidth, lp.starty + labelBoxHeight - 7),
               (sx + labelBoxWidth - 8.4, lp.starty + labelBoxHeight), (sx, lp.starty + labelBoxHeight)],
          some(cLabelBoxBkg), some(cLabelBoxBorder), 1.0)
    drawLabel(sc, kind, sx + labelBoxWidth / 2, lp.starty + labelBoxHeight / 2, 14, cLoopText)
    let mid = (sx + ex) / 2 + labelBoxWidth / 2
    if lp.title.len > 0:
      drawLabel(sc, "[" & lp.title & "]", mid, lp.starty + labelBoxHeight / 2, 14, cLoopText)
    for i, sy in lp.sections:
      if i < lp.sectionTitles.len and lp.sectionTitles[i].len > 0:
        drawLabel(sc, "[" & lp.sectionTitles[i] & "]", (sx + ex) / 2, sy + 10, 14, cLoopText)

  proc openFrag(m: SeqMsg, pre, post: float) =
    b.bump(pre)
    var adj = post
    if m.text.len > 0:
      let (_, h) = dims("[" & m.text & "]", mf)
      adj = post + max(h, labelBoxHeight)
    b.items.add Loop(starty: b.vpos, startx: NaN, stopx: NaN, stopy: NaN, title: m.text)
    b.bump(adj)

  proc section(m: SeqMsg, pre, post: float) =
    b.bump(pre)
    var adj = post
    if m.text.len > 0:
      let (_, h) = dims("[" & m.text & "]", mf)
      adj = post + max(h, labelBoxHeight)
    let lp = b.items[^1]
    lp.sections.add b.vpos
    lp.sectionTitles.add m.text
    b.bump(adj)

  proc closeFrag(kind: string) =
    let lp = b.items.pop()
    if lp.startx.isNaN:
      lp.startx = actors[keys[0]].x
      lp.stopx = lp.startx + 100
    if lp.stopy.isNaN: lp.stopy = lp.starty + 40
    var need = 0.0
    if lp.title.len > 0: need = labelBoxWidth + dims("[" & lp.title & "]", 14)[0] + 20
    for st in lp.sectionTitles:
      if st.len > 0: need = max(need, dims("[" & st & "]", 14)[0] + 40)
    if lp.stopx - lp.startx < need:
      let grow = (need - (lp.stopx - lp.startx)) / 2
      lp.startx -= grow
      lp.stopx += grow
      umin(b.sx, lp.startx)
      umax(b.ex, lp.stopx)
    drawLoopFrame(lp, kind, midLayer)
    b.bump(lp.stopy - b.vpos)

  for m in doc.msgs:
    case m.kind
    of ltNote:
      let a = actors[m.frm]
      let (tw, thh) = dims(m.text, noteFontSize)
      var sx = a.x + a.width / 2
      var w = max(confWidth, tw + 2 * noteMargin)
      case m.placement
      of plRight: sx = sx + (a.width + actorMargin) / 2
      of plLeft: sx = sx - w + (a.width - actorMargin) / 2
      of plOver:
        if m.frm == m.to: sx = sx - w / 2
        else:
          let a2 = actors[m.to]
          let c2 = a2.x + a2.width / 2
          w = max(abs(sx - c2) + actorMargin, tw + 2 * noteMargin)
          sx = (sx + c2) / 2 - w / 2
      b.bump(boxMargin)
      let y0 = b.vpos
      let h = thh + 2 * noteMargin
      dRect(midLayer, sx, y0, w, h, some(cNoteBkg), some(cNoteBorder), 1.0)
      textLines(midLayer, m.text, sx + w / 2, y0 + noteMargin, noteFontSize, cNoteText)
      b.bump(h)
      b.insert(sx, y0, sx + w, y0 + h)
    of ltActiveStart:
      let a = actors[m.frm]
      var cnt = 0
      for ac in b.acts:
        if ac.actor == m.frm: inc cnt
      let x = a.x + a.width / 2 + (float(cnt) - 1) * activationWidth / 2
      b.acts.add Activation(startx: x, starty: b.vpos + 2, stopx: x + activationWidth, actor: m.frm)
    of ltActiveEnd:
      var idx = -1
      for i, ac in b.acts:
        if ac.actor == m.frm: idx = i
      if idx >= 0:
        var ac = b.acts[idx]
        b.acts.delete(idx)
        var v = b.vpos
        if ac.starty + 18 > v:
          ac.starty = v - 6
          v += 12
        dRect(midLayer, ac.startx, ac.starty, activationWidth, v - ac.starty, some(cActBkg), some(cActBorder), 1.0)
        b.insert(ac.startx, v - 10, ac.stopx, v)
    of ltLoopStart: openFrag(m, boxMargin, boxMargin + boxTextMargin)
    of ltLoopEnd: closeFrag("loop")
    of ltOptStart: openFrag(m, boxMargin, boxMargin + boxTextMargin)
    of ltOptEnd: closeFrag("opt")
    of ltAltStart: openFrag(m, boxMargin, boxMargin + boxTextMargin)
    of ltAltElse: section(m, boxMargin + boxTextMargin, boxMargin)
    of ltAltEnd: closeFrag("alt")
    of ltParStart: openFrag(m, boxMargin, boxMargin + boxTextMargin)
    of ltParAnd: section(m, boxMargin + boxTextMargin, boxMargin)
    of ltParEnd: closeFrag("par")
    of ltCritStart: openFrag(m, boxMargin, boxMargin + boxTextMargin)
    of ltCritOption: section(m, boxMargin + boxTextMargin, boxMargin)
    of ltCritEnd: closeFrag("critical")
    of ltBreakStart: openFrag(m, boxMargin, boxMargin + boxTextMargin)
    of ltBreakEnd: closeFrag("break")
    of ltRectStart:
      b.bump(boxMargin)
      b.items.add Loop(starty: b.vpos, startx: NaN, stopx: NaN, stopy: NaN, fill: m.text, hasFill: true)
      b.bump(boxMargin)
    of ltRectEnd:
      let lp = b.items.pop()
      if not lp.startx.isNaN:
        backgrounds.add (lp, lp.fill)
      b.bump(lp.stopy - b.vpos)
    of ltAutonumber:
      if m.numStart != 0: seqIndex = m.numStart
      if m.numStep != 0: seqStep = m.numStep
      seqVisible = m.numVisible
    else:
      # ordinary message
      if m.frm notin actors or m.to notin actors: continue
      let (fl, fr) = actBounds(m.frm)
      let (tl, tr) = actBounds(m.to)
      let toRight = fl <= tl
      var startx = if toRight: fr else: fl
      var stopx = if toRight: tl else: tr
      if m.frm == m.to:
        startx = fr
        stopx = fr
      let fromB = min(min(fl, fr), min(tl, tr))
      let toB = max(max(fl, fr), max(tl, tr))
      let starty = b.vpos
      b.bump(10)
      let (tw, thh) = dims(m.text, mf)
      let lines = max(1, splitBreaks(m.text).len)
      let lh = thh / float(lines)
      b.bump(lh)
      var height = lh
      var totalOffset = thh - 10
      var lineY: float
      if startx == stopx:
        totalOffset += boxMargin
        lineY = b.vpos + totalOffset
        totalOffset += 30
        let dx = max(tw / 2, confWidth / 2)
        b.insert(startx - dx, b.vpos - 10 + totalOffset, stopx + dx, b.vpos + 30 + totalOffset)
      else:
        totalOffset += boxMargin
        lineY = b.vpos + totalOffset
        b.insert(startx, lineY - 10, stopx, lineY)
      b.bump(totalOffset)
      height += totalOffset
      b.insert(fromB, starty, toB, starty + height)
      toDraw.add MsgDraw(kind: m.kind, startx: startx, stopx: stopx, lineY: lineY, text: m.text,
                         starty: starty, seqNo: seqIndex, showNo: seqVisible, frm: m.frm)
      seqIndex += seqStep

  # --- bottom actors + lifelines ---------------------------------------------------------------------------
  b.bump(boxMargin * 2)
  let bottomY = b.vpos
  for k in keys:
    let a = actors[k]
    drawActorBox(topLayer, a, a.y)
    drawActorBox(botLayer, a, bottomY)
    dLine(lifeLayer, a.x + a.width / 2, a.y + a.height, a.x + a.width / 2, bottomY, cLifeline, 0.5)
    b.insert(a.x, bottomY, a.x + a.width, bottomY + a.height)
  umax(b.ey, bottomY + maxH + bottomMarginAdj)

  # --- boxes (column groupings behind actors + lifelines) -----------------------------------------
  for bx in doc.boxes:
    if bx.actors.len == 0: continue
    let first = actors[bx.actors[0]]
    let last = actors[bx.actors[^1]]
    let x0 = first.x - boxMargin
    let x1 = last.x + last.width + boxMargin
    var fc = rgba(0, 0, 0, 0)
    if bx.hasColor:
      var c: Color
      if tryParseColor(bx.color, c): fc = c
    let y1 = bottomY + maxH + 5
    dRect(bgLayer, x0, 0, x1 - x0, y1, some(fc), some(rgba(0, 0, 0, 128)), 1.0)
    if bx.name.len > 0:
      drawLabel(bgLayer, bx.name, (x0 + x1) / 2, 14, 16, th.actorText)
    b.insert(x0, 0, x1, y1)

  # --- messages -------------------------------------------------------------------------------------------------------
  for md in toDraw:
    let sx = md.startx
    let ex = md.stopx
    let dash = if md.kind in {ltDotted, ltDottedCross, ltDottedOpen, ltDottedPoint, ltBidirDotted}: @[3.0, 3.0] else: @[]
    textLines(msgLayer, md.text, (min(sx, ex) + max(sx, ex)) / 2, md.starty + 10, mf, cSignalText)
    if sx == ex:
      let sh = pvg_shape_new()
      discard pvg_shape_move_to(sh, cfloat(sx), cfloat(md.lineY))
      discard pvg_shape_cubic_to(sh, cfloat(sx + 60), cfloat(md.lineY - 10), cfloat(sx + 60), cfloat(md.lineY + 30),
                                 cfloat(sx), cfloat(md.lineY + 20))
      sh.shapeStroke(cSignal, 1.5, dash)
      discard pvg_scene_add(msgLayer, sh)
      arrowHead(msgLayer, sx, md.lineY + 20, -1, md.kind)
    else:
      let dir = if ex > sx: 1.0 else: -1.0
      var x1 = sx
      if md.showNo: x1 = sx + dir * 6
      dLine(msgLayer, x1, md.lineY, ex, md.lineY, cSignal, 1.5, dash)
      arrowHead(msgLayer, ex, md.lineY, dir, md.kind)
      if md.kind in {ltBidirSolid, ltBidirDotted}: arrowHead(msgLayer, sx, md.lineY, -dir, md.kind)
    if md.showNo:
      dCircle(msgLayer, sx, md.lineY, 6, some(cSignal), none(Color))
      drawLabel(msgLayer, $md.seqNo, sx, md.lineY + 0.5, 11, cSeqNo)

  # rect backgrounds
  for (lp, fill) in backgrounds:
    var c: Color
    let fc = if tryParseColor(fill, c): c else: rgba(128, 128, 128, 128)
    dRect(bgLayer, lp.startx, lp.starty, lp.stopx - lp.startx, lp.stopy - lp.starty, some(fc), none(Color))

  # --- bounds + title -------------------------------------------------------------------------------------------------
  var bounds: painter.DiagramBounds = (b.sx - diagramMarginX, b.sy - diagramMarginY,
                                       b.ex + diagramMarginX, b.ey + diagramMarginY)
  if doc.title.len > 0:
    bounds.minY -= 40
    drawLabel(root, doc.title, (b.sx + b.ex) / 2, b.sy - 25 + 8, 18, th.titleColor)
  (root, bounds)

proc sequenceScene*(text: string, th: FlowTheme): (Pvg_Paint, painter.DiagramBounds) =
  let fm = extractFrontMatter(text)
  let doc = parseSequence(stripAnyComments(stripDirectives(fm.text)))
  if fm.title.len > 0: doc.title = fm.title
  layoutAndPaint(doc, th)

proc renderSequenceToImage*(text: string, th: FlowTheme = defaultTheme(), scale = 2.0): RenderedImage =
  let (scene, bounds) = sequenceScene(text, th)
  rasterizeScene(scene, bounds, th, 0.0, scale)
