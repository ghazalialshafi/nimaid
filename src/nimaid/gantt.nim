## Gantt charts: parser + layout + painting (Mermaid default look: section bands, bars, grid, axis).
import std/[strutils, math, options, tables, algorithm]
import gfx, theme, label, textmetrics, painter, drawkit

type
  GTask = object
    name, id: string
    section: int
    crit, done, active, milestone: bool
    startD, endD: float

  GanttError* = object of CatchableError

proc daysFromCivil(y0, m, d: int): int =
  let y = if m <= 2: y0 - 1 else: y0
  let era = (if y >= 0: y else: y - 399) div 400
  let yoe = y - era * 400
  let doy = (153 * (m + (if m > 2: -3 else: 9)) + 2) div 5 + d - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  era * 146097 + doe - 719468

proc civilFromDays(z0: int): (int, int, int) =
  let z = z0 + 719468
  let era = (if z >= 0: z else: z - 146096) div 146097
  let doe = z - era * 146097
  let yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let d = doy - (153 * mp + 2) div 5 + 1
  let m = if mp < 10: mp + 3 else: mp - 9
  ((if m <= 2: y + 1 else: y), m, d)

proc parseDate(s: string, d: var float): bool =
  let t = s.strip().replace('/', '-')
  let p = t.split({'-', ' ', 'T'})
  if p.len >= 3 and p[0].len == 4 and p[0].allCharsInSet(Digits) and p[1].allCharsInSet(Digits) and p[2].allCharsInSet(Digits):
    d = float(daysFromCivil(parseInt(p[0]), parseInt(p[1]), parseInt(p[2])))
    return true
  false

proc parseDuration(s: string, d: var float): bool =
  let t = s.strip()
  if t.len < 2: return false
  let unit = t[^1]
  let num = t[0 ..< t.len - 1]
  if not num.allCharsInSet(Digits + {'.'}): return false
  let v = parseFloat(num)
  case unit
  of 'd': d = v
  of 'w': d = v * 7
  of 'h': d = v / 24
  of 'm': d = v / 1440
  of 's': d = v / 86400
  else: return false
  true

const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

proc fmtDate(fmt: string, day: float): string =
  let (y, m, d) = civilFromDays(int(floor(day)))
  let dow = ((int(floor(day)) mod 7) + 11) mod 7      # 1970-01-01 was a Thursday
  var i = 0
  while i < fmt.len:
    if fmt[i] == '%' and i + 1 < fmt.len:
      case fmt[i + 1]
      of 'Y': result.add $y
      of 'y': result.add align($(y mod 100), 2, '0')
      of 'm': result.add align($m, 2, '0')
      of 'd': result.add align($d, 2, '0')
      of 'e': result.add align($d, 2, ' ')
      of 'b': result.add monthNames[m - 1][0 .. 2]
      of 'B': result.add monthNames[m - 1]
      of 'a': result.add dayNames[dow mod 7]
      of 'H', 'M', 'S': result.add "00"
      else: result.add fmt[i .. i + 1]
      i += 2
    else:
      result.add fmt[i]
      inc i

proc ganttScene*(text: string, th: FlowTheme): (Pvg_Paint, DiagramBounds) =
  var title = ""
  var axisFmt = "%Y-%m-%d"
  var sections: seq[string]
  var tasks: seq[GTask]
  var ids = initTable[string, int]()
  var started = false
  for raw in text.replace("\r\n", "\n").split('\n'):
    var l = raw
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    l = l.strip()
    if l.len == 0: continue
    let low = l.toLowerAscii
    if not started:
      if low.startsWith("gantt"): started = true; continue
      raise newException(GanttError, "Parse error: expecting 'gantt'")
    if low.startsWith("title"): title = l[5 .. ^1].strip(chars = {' ', ':'}); continue
    if low.startsWith("axisformat"): axisFmt = l[10 .. ^1].strip(); continue
    if low.startsWith("section"):
      sections.add l[7 .. ^1].strip(chars = {' ', ':'})
      continue
    for kw in ["dateformat", "tickinterval", "excludes", "includes", "todaymarker", "weekday", "weekend", "inclusiveenddates", "topaxis", "accdescr", "acctitle", "click", "vert"]:
      if low.startsWith(kw): break
    if low.startsWith("dateformat") or low.startsWith("tickinterval") or low.startsWith("excludes") or low.startsWith("includes") or
       low.startsWith("todaymarker") or low.startsWith("weekday") or low.startsWith("weekend") or low.startsWith("inclusiveenddates") or
       low.startsWith("topaxis") or low.startsWith("acc") or low.startsWith("click"): continue
    let ci = l.find(':')
    if ci < 0: continue
    if sections.len == 0: sections.add ""
    var t = GTask(name: l[0 ..< ci].strip(), section: sections.len - 1)
    var toks: seq[string]
    for p in l[ci + 1 .. ^1].split(','): toks.add p.strip()
    var k = 0
    while k < toks.len and toks[k] in ["crit", "done", "active", "milestone"]:
      case toks[k]
      of "crit": t.crit = true
      of "done": t.done = true
      of "active": t.active = true
      else: t.milestone = true
      inc k
    var rest = toks[k .. ^1]
    var tmp = 0.0
    if rest.len >= 2 or (rest.len == 1 and not (rest[0].toLowerAscii.startsWith("after ") or parseDate(rest[0], tmp) or parseDuration(rest[0], tmp))):
      if not (rest[0].toLowerAscii.startsWith("after ") or parseDate(rest[0], tmp) or parseDuration(rest[0], tmp)):
        t.id = rest[0]
        rest = rest[1 .. ^1]
    let prevEnd = if tasks.len > 0: tasks[^1].endD else: float(daysFromCivil(2020, 1, 1))
    var startD = prevEnd
    var endTok = ""
    if rest.len >= 2:
      let s0 = rest[0]
      if s0.toLowerAscii.startsWith("after "):
        var mx = -1e18
        for idn in s0[6 .. ^1].splitWhitespace():
          if idn in ids: mx = max(mx, tasks[ids[idn]].endD)
        if mx > -1e17: startD = mx
      else:
        discard parseDate(s0, startD)
      endTok = rest[1]
    elif rest.len == 1:
      if rest[0].toLowerAscii.startsWith("after "):
        var mx = -1e18
        for idn in rest[0][6 .. ^1].splitWhitespace():
          if idn in ids: mx = max(mx, tasks[ids[idn]].endD)
        if mx > -1e17: startD = mx
        endTok = "1d"
      elif parseDate(rest[0], tmp): startD = tmp; endTok = "1d"
      else: endTok = rest[0]
    else: endTok = "1d"
    t.startD = startD
    var dur = 1.0
    var ed = 0.0
    if parseDate(endTok, ed): t.endD = ed
    elif parseDuration(endTok, dur): t.endD = startD + dur
    else: t.endD = startD + 1
    if t.milestone: t.endD = t.startD
    if t.id.len > 0: ids[t.id] = tasks.len
    tasks.add t
  if not started: raise newException(GanttError, "Parse error: expecting 'gantt'")
  if tasks.len == 0:
    tasks.add GTask(name: "", section: 0, startD: float(daysFromCivil(2020, 1, 1)), endD: float(daysFromCivil(2020, 1, 2)))
    if sections.len == 0: sections.add ""

  var minT = 1e18
  var maxT = -1e18
  for t in tasks:
    minT = min(minT, t.startD)
    maxT = max(maxT, t.endD)
  if maxT - minT < 1: maxT = minT + 1
  let barH = 20.0
  let rowH = 24.0
  let topPad = 50.0
  var leftPad = 75.0
  for s in sections: leftPad = max(leftPad, float(measureLabel(s, 12).w) + 20)
  let rightPad = 75.0
  let chartW = 810.0
  let W = leftPad + chartW + rightPad
  proc xOf(d: float): float = leftPad + (d - minT) / (maxT - minT) * chartW

  let sc = pvg_scene_new()
  let secBand = [rgba(102, 102, 255, 125), rgba(255, 255, 255, 255)]
  let nrows = tasks.len
  let bottom = topPad + float(nrows) * rowH
  # section bands per row
  for i, t in tasks:
    kRect(sc, 0, topPad + float(i) * rowH, W, rowH, some(secBand[t.section mod 2]), none(Color))
  # grid + axis
  var step = 1.0
  for s in [1.0, 2.0, 7.0, 14.0, 30.0, 60.0, 90.0, 180.0, 365.0]:
    step = s
    if (maxT - minT) / s <= 12: break
  var tick = ceil(minT / step) * step
  if step == 7: tick = ceil((minT + 3) / 7) * 7 - 3     # weeks start on Monday
  while tick <= maxT + 1e-9:
    let x = xOf(tick)
    kLine(sc, x, 35, x, bottom, rgba(211, 211, 211), 1.0)
    drawLabel(sc, fmtDate(axisFmt, tick), x, bottom + 16, 10, th.textColor)
    tick += step
  # tasks
  for i, t in tasks:
    let y = topPad + float(i) * rowH + (rowH - barH) / 2
    var fill = rgba(138, 144, 221)
    var stroke = rgba(83, 79, 188)
    if t.active: fill = rgba(191, 199, 255)
    if t.done: fill = rgba(211, 211, 211); stroke = rgba(128, 128, 128)
    if t.crit: stroke = rgba(255, 136, 136); (if not t.done: fill = rgba(255, 0, 0))
    let x1 = xOf(t.startD)
    let x2 = xOf(t.endD)
    let label = decodeEntities(t.name)
    let tw = float(measureLabel(label, 11).w)
    if t.milestone:
      let cx = x1
      let cy = y + barH / 2
      kPoly(sc, [(cx, cy - 11), (cx + 11, cy), (cx, cy + 11), (cx - 11, cy)], some(fill), some(stroke), 2.0)
      drawLabel(sc, label, cx + 16 + tw / 2, cy, 11, th.textColor)
    else:
      kRect(sc, x1, y, max(x2 - x1, 2.0), barH, some(fill), some(stroke), 2.0, 3.0)
      if tw + 10 <= x2 - x1:
        drawLabel(sc, label, (x1 + x2) / 2, y + barH / 2, 11, (if t.done or t.active: rgba(0, 0, 0) else: rgba(255, 255, 255)))
      else:
        drawLabel(sc, label, x2 + 6 + tw / 2, y + barH / 2, 11, th.textColor)
  # section titles
  var rowI = 0
  var si = 0
  while rowI < nrows:
    var j = rowI
    while j < nrows and tasks[j].section == tasks[rowI].section: inc j
    let name = sections[tasks[rowI].section]
    drawLabel(sc, name, 8 + float(measureLabel(name, 12).w) / 2, topPad + (float(rowI + j) / 2) * rowH, 12, th.textColor)
    rowI = j
    inc si
  if title.len > 0: drawLabel(sc, title, W / 2, 20, 18, th.titleColor)
  (sc, (0.0, 0.0, W, bottom + 36.0))
