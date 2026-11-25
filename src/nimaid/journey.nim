## User journey diagrams (Mermaid `journey`). Drawing primitives from svgDraw.js (drawFace/drawTask/drawSection/legend),
## layout constants from the journey config defaults; colours from the theme (fillType0..6, textColor).
import std/[strutils, math, options, tables, json]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  Task = object
    section, name: string
    score: float
    people: seq[string]

const ClassicActorColours = ["#8FBC8F", "#7CFC00", "#00FFFF", "#20B2AA", "#B0E0E6", "#FFFFE0"]
const ActorColours = ["#2f6fdb", "#e8590c", "#2b9348", "#9c36b5", "#c92a2a", "#0c8599"]
const SectionColours = ["#5470c6", "#ee8c3a", "#4aa366", "#a65fb5", "#d9534f", "#2fa6b3", "#c9a227"]
const FontPx = 16.0

proc parseJourney(text, fmTitle: string): (string, seq[Task], seq[string]) =
  var title = fmTitle
  var tasks: seq[Task]
  var actors: seq[string]
  var cur = ""
  var started = false
  for raw in text.replace("\r\n", "\n").split({'\n', ';'}):
    var l = raw
    if l.strip().startsWith("#"): continue
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    let t = l.strip()
    if t.len == 0: continue
    let low = t.toLowerAscii
    if not started:
      if not low.startsWith("journey"): raise newException(ChartError, "Parse error: expecting 'journey'")
      started = true; continue
    if low.startsWith("title"): title = t[5 .. ^1].strip(); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    if low.startsWith("section"): cur = t[7 .. ^1].strip(); continue
    let parts = t.split(':')
    if parts.len < 2: raise newException(ChartError, "Parse error: a task is 'Name: score: Actor, Actor'")
    var score: float
    try: score = parseFloat(parts[1].strip())
    except ValueError: raise newException(ChartError, "Parse error: the score of '" & parts[0].strip() & "' must be a number")
    var people: seq[string]
    if parts.len >= 3:
      for p in parts[2 .. ^1].join(":").split(','):
        let a = p.strip()
        if a.len > 0:
          people.add a
          if a notin actors: actors.add a
    tasks.add Task(section: cur, name: parts[0].strip(), score: score, people: people)
  (title, tasks, actors)

proc wrapText(text: string, width: float, px: float): seq[string] =
  var line = ""
  for word in text.replace("<br/>", " ").replace("<br>", " ").split({' ', '\t'}):
    if word.len == 0: continue
    let trial = if line.len == 0: word else: line & " " & word
    if line.len > 0 and textW(trial, px) > width: result.add line; line = word
    else: line = trial
  if line.len > 0: result.add line

proc wrapLegend(name: string, maxW: float): seq[string] =
  ## drawActorLegend: greedy word wrap at maxLabelWidth; over-long words are hyphen-broken character by character.
  if textW(name, FontPx) <= maxW: return @[name]
  var cur = ""
  for word in name.split(' '):
    let trial = if cur.len > 0: cur & " " & word else: word
    if textW(trial, FontPx) > maxW:
      if cur.len > 0: result.add cur
      cur = word
      if textW(word, FontPx) > maxW:
        var broken = ""
        for ch in word:
          broken.add ch
          if textW(broken & "-", FontPx) > maxW:
            result.add broken[0 ..< broken.len - 1] & "-"
            broken = $ch
        cur = broken
    else: cur = trial
  if cur.len > 0: result.add cur

proc moodColor(score: float): Color =
  ## 1 (unhappy) .. 5 (happy): soft red -> amber -> green
  let stops = [rgba(0xF5, 0xA9, 0xA6), rgba(0xF8, 0xC8, 0x9B), rgba(0xFB, 0xE6, 0x9C), rgba(0xCF, 0xE8, 0x9F), rgba(0xA3, 0xDD, 0x9E)]
  let t = clamp(score, 1.0, 5.0) - 1.0
  let i = min(3, int(floor(t)))
  mixColor(stops[i], stops[i + 1], t - float(i))

proc drawFace(sc: Pvg_Paint, cx, cy: float, score: float, classic: bool) =
  let r = 15.0
  let faceFill = if classic: rgba(0xFF, 0xF8, 0xDC) else: moodColor(score)
  let rim = if classic: rgba(0x99, 0x99, 0x99) else: mixColor(faceFill, rgba(0, 0, 0), 0.38)
  let eye = if classic: rgba(0x66, 0x66, 0x66) else: rgba(0x4a, 0x4a, 0x4a)
  kCircle(sc, cx, cy, r, some(faceFill), some(rim), 2)
  kCircle(sc, cx - r / 3, cy - r / 3, 1.6, some(eye), some(eye), 1.6)
  kCircle(sc, cx + r / 3, cy - r / 3, 1.6, some(eye), some(eye), 1.6)
  proc crescent(ox, oy, a0, a1: float) =
    let ri = r / 2.2
    let ro = r / 2
    let sh = pvg_shape_new()
    let (x0, y0) = polar(ox, oy, ro, a0)
    discard pvg_shape_move_to(sh, cfloat(x0), cfloat(y0))
    arcTo(sh, ox, oy, ro, a0, a1)
    let (x1, y1) = polar(ox, oy, ri, a1)
    discard pvg_shape_line_to(sh, cfloat(x1), cfloat(y1))
    arcTo(sh, ox, oy, ri, a1, a0)
    discard pvg_shape_close(sh)
    styleShape(sh, some(if classic: rgba(0, 0, 0) else: eye), some(eye), 1)
    discard pvg_scene_add(sc, sh)
  if score > 3: crescent(cx, cy + 2, PI / 2, 3 * PI / 2)          # smile
  elif score < 3: crescent(cx, cy + 7, 3 * PI / 2, 5 * PI / 2)    # sad
  else: kPath(sc, [(cx - 5, cy + 7), (cx + 5, cy + 7)], false, none(Color), some(eye), 1.4)

proc journeyScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let (title, tasks, actors) = parseJourney(text, fmTitle)
  if tasks.len == 0: raise newException(ChartError, "Journey has no tasks")
  let jc = cv.cfg.cfgSub("journey")
  let classic = jc.cfgBool("classicColors", false)
  let diagMarginX = jc.cfgFloat("diagramMarginX", 50)
  let diagMarginY = jc.cfgFloat("diagramMarginY", 10)
  let confLeft = jc.cfgFloat("leftMargin", 150)
  let maxLabelW = jc.cfgFloat("maxLabelWidth", 360)
  let taskW = jc.cfgFloat("width", 150)
  let taskH = jc.cfgFloat("height", 50)
  let taskMargin = jc.cfgFloat("taskMargin", 50)
  var actorColours: seq[Color]
  if jc.hasKey("actorColours") and jc["actorColours"].kind == JArray:
    for n in jc["actorColours"]:
      let c = parseCssColor(n.getStr())
      if c.isSome: actorColours.add c.get
  if actorColours.len == 0:
    for c in (if classic: @ClassicActorColours else: @ActorColours): actorColours.add parseCssColor(c).get
  let root = pvg_scene_new()
  let textColor = cv.color("textColor")
  let grey = rgba(0x66, 0x66, 0x66)         # rect strokes / eyes (#666 in svgDraw)
  let bgColor = cv.color("background", rgba(255, 255, 255))
  let darkMode = isDarkColor(bgColor)
  var sectionPal: seq[Color]
  for c in SectionColours: sectionPal.add parseCssColor(c).get
  var actorColor = initTable[string, Color]()
  for i, a in actors: actorColor[a] = actorColours[i mod actorColours.len]

  # ---- actor legend (drawActorLegend): circle + wrapped label, 20 px per line, 16 px text (class "legend")
  var maxWidth = 0.0
  var yPos = 60.0
  for a in actors:
    kCircle(root, 20, yPos, 7, some(actorColor[a]), some(if classic: rgba(0, 0, 0) else: mixColor(actorColor[a], rgba(0, 0, 0), 0.3)), 1)
    let lines = wrapLegend(a, maxLabelW)
    for i, ln in lines:
      drawTextPx(root, ln, 50, yPos + 7 + float(i) * 20, FontPx, textColor, aStart)
      let lw = textW(ln, FontPx)
      if lw > maxWidth and lw > confLeft - lw: maxWidth = lw
    yPos += max(20.0, float(lines.len) * 20)
  let leftMargin = confLeft + maxWidth

  # ---- sections + tasks
  var lastSection = ""
  var sectionNumber = 0
  var fillNum = 0
  let sectionFillCount = 7
  var stopY = float(actors.len) * 50
  var faces: seq[(float, float, float)]
  for i, t in tasks:
    if t.section != lastSection:
      fillNum = sectionNumber mod sectionFillCount
      var cnt = 0
      for j in i ..< tasks.len:
        if tasks[j].section == t.section: inc cnt else: break
      let sx = float(i) * taskMargin + float(i) * taskW + leftMargin
      let w = taskW * float(cnt) + diagMarginX * float(cnt - 1)
      if classic:
        kRect(root, sx, 50, w, taskH, some(cv.color("fillType" & $fillNum)), some(grey), 1, 3)
      else:
        let sc0 = sectionPal[fillNum]
        kShadow(root, sx, 50, w, taskH, 6, 0.08, 0, 2)
        kRect(root, sx, 50, w, taskH, some(sc0), none(Color), 0, 6)
      let lines = wrapText(t.section, w, FontPx)
      var ty = 50 + taskH / 2 - float(lines.len - 1) * FontPx * 1.15 / 2
      for ln in lines:
        drawT(root, ln, sx + w / 2, ty, FontPx, (if classic: textColor else: rgba(255, 255, 255)), vMiddle, aMiddle); ty += FontPx * 1.15
      lastSection = t.section
      inc sectionNumber
    let x = float(i) * taskMargin + float(i) * taskW + leftMargin
    let y = taskH * 2 + diagMarginY             # taskPos = verticalPos + sectionVHeight
    let center = x + taskW / 2
    let accent = if classic: grey else: sectionPal[fillNum]
    let taskFill = if classic: cv.color("fillType" & $fillNum) else: mixColor(accent, bgColor, (if darkMode: 0.72 else: 0.86))
    # "line { stroke: textColor }" in the journey stylesheet colours the score lines
    kPath(root, [(center, y + taskH), (center, 300.0 + 5 * 30)], false, none(Color),
          some(if classic: textColor else: withAlpha(textColor, 0.35)), 1, @[4.0, 3.0])
    faces.add (center, 300 + (5 - t.score) * 30, t.score)
    if not classic: kShadow(root, x, y, taskW, taskH, 6, 0.08, 0, 2)
    kRect(root, x, y, taskW, taskH, some(taskFill), some(if classic: grey else: accent), (if classic: 1.0 else: 1.3), 6)
    var xPos = x + 14
    for p in t.people:                          # actor dots along the top edge of the task box
      if p in actorColor: kCircle(root, xPos, y, 7, some(actorColor[p]), some(if classic: rgba(0, 0, 0) else: bgColor), (if classic: 1.0 else: 1.8))
      xPos += 10
    let lines = wrapText(t.name, taskW, FontPx)
    var ty = y + taskH / 2 - float(lines.len - 1) * FontPx * 1.15 / 2
    for ln in lines:
      drawT(root, ln, center, ty, FontPx, textColor, vMiddle, aMiddle); ty += FontPx * 1.15
    stopY = max(stopY, 300.0 + 5 * 30)

  # ---- score guides, emotion curve and faces (drawn after the loop so they sit above the dashed lines)
  let nT = tasks.len
  let gEnd = leftMargin + float(nT - 1) * (taskMargin + taskW) + taskW + 20
  if not classic:
    for sc0 in 1 .. 5:
      let gy = 300.0 + float(5 - sc0) * 30
      kPath(root, [(leftMargin - 4, gy), (gEnd, gy)], false, none(Color), some(withAlpha(textColor, 0.09)), 1)
      drawT(root, $sc0, leftMargin - 16, gy, 11, withAlpha(textColor, 0.45), vMiddle, aEnd)
    if faces.len >= 2:                                 # smooth emotion curve (Catmull-Rom -> Bezier)
      let sh = pvg_shape_new()
      discard pvg_shape_move_to(sh, cfloat(faces[0][0]), cfloat(faces[0][1]))
      for i in 0 ..< faces.len - 1:
        let p0 = faces[max(i - 1, 0)]
        let p1 = faces[i]
        let p2 = faces[i + 1]
        let p3 = faces[min(i + 2, faces.len - 1)]
        discard pvg_shape_cubic_to(sh, cfloat(p1[0] + (p2[0] - p0[0]) / 6), cfloat(p1[1] + (p2[1] - p0[1]) / 6),
                                   cfloat(p2[0] - (p3[0] - p1[0]) / 6), cfloat(p2[1] - (p3[1] - p1[1]) / 6), cfloat(p2[0]), cfloat(p2[1]))
      styleShape(sh, none(Color), some(withAlpha(textColor, 0.38)), 3, @[], PVG_STROKE_JOIN_ROUND, PVG_STROKE_CAP_ROUND)
      discard pvg_scene_add(root, sh)
  for f in faces: drawFace(root, f[0], f[1], f[2], classic)

  # ---- bounds (bounds.insert for every task), title and the journey axis
  let n = tasks.len
  let lastX = float(n - 1) * taskMargin + float(n - 1) * taskW + leftMargin
  let stopX = lastX + diagMarginX + taskMargin          # task.x + task.width(=diagramMarginX) + taskMargin
  let width = leftMargin + stopX + 2 * diagMarginX
  let height = stopY + 2 * diagMarginY
  let titleExtra = if title.len > 0: 70.0 else: 0.0
  if title.len > 0:
    let tc = parseCssColor(jc.cfgStr("titleColor", ""))
    drawTextPx(root, title, leftMargin, 25, 4 * 0.52 * FontPx, tc.get(textColor), aStart)   # fill="" is invalid -> inherits the root fill (textColor)
  let axisY = taskH * 4
  let ax2 = width - leftMargin - 4
  kPath(root, [(leftMargin, axisY), (ax2, axisY)], false, none(Color), some(textColor), 4)
  arrowHead(root, ax2, axisY, 1, 0, 4, textColor)
  (root, (minX: 0.0, minY: -25.0, maxX: width, maxY: -25.0 + height + titleExtra))
