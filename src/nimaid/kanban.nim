## Kanban boards (Mermaid `kanban`): indentation grammar (kanban.jison, mindmap-like), metadata `@{ticket, assigned, priority}`,
## layout from kanbanRenderer.ts + shapes/kanbanItem.ts + clusters.js (kanbanSection) + styles.ts.
import std/[strutils, math, options, json]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  Item = object
    text, ticket, assigned, priority: string
  Section = object
    title: string
    items: seq[Item]

const FontPx = 16.0
const LineH = 17.6

proc parseMeta(s: string): (string, string, string) =
  ## `ticket: MC-2037, assigned: 'knsv', priority: 'High'`
  var ticket, assigned, priority = ""
  for part in s.split(','):
    let ci = part.find(':')
    if ci <= 0: continue
    let k = part[0 ..< ci].strip().strip(chars = {'\'', '"'})
    let v = unquote(part[ci + 1 .. ^1])
    case k
    of "ticket": ticket = v
    of "assigned": assigned = v
    of "priority": priority = v
    else: discard
  (ticket, assigned, priority)

proc nodeText(t: string): string =
  ## `id[Text]`, `[Text]`, `id(Text)`, `id((Text))`, plain text
  var s = t.strip()
  let o = s.find({'[', '(', '{'})
  if o >= 0:
    var c = s.rfind({']', ')', '}'})
    if c > o:
      var inner = s[o + 1 ..< c].strip(chars = {'[', ']', '(', ')', '{', '}', '-'})
      return unquote(inner)
  unquote(s)

proc parseKanban(text: string): seq[Section] =
  var started = false
  var sectionIndent = -1
  for rawLine in text.replace("\r\n", "\n").split('\n'):
    var l = rawLine.replace("\t", "  ")
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    if l.strip().len == 0: continue
    let indent = l.len - l.strip(trailing = false).len
    var t = l.strip()
    if not started:
      if not t.toLowerAscii.startsWith("kanban"): raise newException(ChartError, "Parse error: expecting 'kanban'")
      started = true; continue
    if t.toLowerAscii.startsWith("title") and sectionIndent < 0: continue
    var meta = ("", "", "")
    let mi = t.find("@{")
    if mi >= 0:
      let me = t.find('}', mi)
      meta = parseMeta(t[mi + 2 ..< (if me < 0: t.len else: me)])
      t = t[0 ..< mi].strip()
    if t.len == 0: continue
    if sectionIndent < 0: sectionIndent = indent
    if indent <= sectionIndent:
      result.add Section(title: nodeText(t))
    else:
      if result.len == 0: raise newException(ChartError, "Items without section detected, found item (\"" & nodeText(t) & "\")")
      result[^1].items.add Item(text: nodeText(t), ticket: meta[0], assigned: meta[1], priority: meta[2])

proc priorityColor(p: string): Option[Color] =
  case p
  of "Very High": some(rgba(255, 0, 0))
  of "High": some(rgba(255, 165, 0))
  of "Low": some(rgba(0, 0, 255))
  of "Very Low": some(rgba(173, 216, 230))
  else: none(Color)

proc initials(name: string): string =
  let parts = name.replace(".", " ").splitWhitespace()
  if parts.len >= 2: (parts[0][0 .. 0] & parts[^1][0 .. 0]).toUpperAscii
  elif parts.len == 1 and parts[0].len >= 2: parts[0][0 .. 1].toUpperAscii
  elif parts.len == 1: parts[0].toUpperAscii
  else: "?"

proc ellipsize(text: string, maxW, px: float): string =
  if textW(text, px) <= maxW: return text
  var t = text
  while t.len > 1 and textW(t & "...", px) > maxW: t.setLen(t.len - 1)
  t & "..."

proc kanbanScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let sections = parseKanban(text)
  if sections.len == 0: raise newException(ChartError, "Kanban has no sections")
  let kc = cv.cfg.cfgSub("kanban")
  let W = kc.cfgFloat("sectionWidth", 200)
  let classic = kc.cfgBool("classicColors", false)
  let root = pvg_scene_new()
  let bg = cv.color("background", rgba(255, 255, 255))
  let darkMode = isDarkColor(bg)
  let textColor = cv.color("textColor")
  let muted = mixColor(textColor, bg, 0.42)
  const Gap = 14.0
  const ColPad = 10.0
  const HeaderH = 42.0
  const CardGap = 10.0
  const Pad = 12.0
  const LineH = 18.0
  const Px = 14.0
  const FootH = 26.0
  var minX, minY = Inf
  var maxX, maxY = -Inf
  proc grow(x0, y0, x1, y1: float) =
    minX = min(minX, x0); minY = min(minY, y0); maxX = max(maxX, x1); maxY = max(maxY, y1)
  let avatarPal = ["#4e79a7", "#f28e2c", "#e15759", "#76b7b2", "#59a14f", "#b07aa1", "#9c755f", "#edc949"]
  let cardFill = if darkMode: mixColor(bg, rgba(255, 255, 255), 0.07) else: bg
  let cardEdge = mixColor(cv.color("nodeBorder", rgba(150, 150, 150)), bg, if darkMode: 0.55 else: 0.62)
  var colBottom = 0.0
  type Card = tuple[y, h: float, lines: seq[string], item: Item]
  var plan: seq[(float, float, seq[Card])]     # per column: x, content bottom, cards
  # ---- pass 1: card sizes (columns share one height so the board reads as a grid)
  for ci, s in sections:
    let cx = float(ci) * (W + Gap)
    var y = HeaderH
    var cards: seq[Card]
    for it in s.items:
      let barW = if priorityColor(it.priority).isSome: 4.0 else: 0.0
      let lines = wrapWords(it.text, W - 2 * ColPad - 2 * Pad - barW, Px)
      let foot = it.ticket.len > 0 or it.assigned.len > 0
      let h = float(lines.len) * LineH + 2 * Pad - 4 + (if foot: FootH else: 0.0)
      cards.add (y: y, h: h, lines: lines, item: it)
      y += h + CardGap
    colBottom = max(colBottom, y + ColPad - CardGap)
    plan.add (cx, y, cards)
  colBottom = max(colBottom, HeaderH + 80)
  # ---- pass 2: draw
  for ci, s in sections:
    let (cx, _, cards) = plan[ci]
    let scale = cv.color("cScale" & $(ci + 2))
    let (hue, sat, _) = toHsl(scale)
    let colFill = if classic: (if darkMode: darken(scale, 10) else: lighten(scale, 10))
                  elif darkMode: hslToColor(hue, clamp(sat * 0.45, 0.15, 0.45), 0.20, 1.0)
                  else: hslToColor(hue, clamp(sat * 0.75, 0.30, 0.62), 0.93, 1.0)
    let accent = hslToColor(hue, clamp(sat * 0.85, 0.35, 0.70), if darkMode: 0.58 else: 0.52, 1.0)
    kShadow(root, cx, 0, W, colBottom, 12, 0.07, 0, 3)
    kRect(root, cx, 0, W, colBottom, some(colFill), none(Color), 0, 12)
    kRect(root, cx + 14, 0, W - 28, 4, some(accent), none(Color), 0, 2)           # accent bar on top of the column
    let bw = textW($s.items.len, 11) + 14
    drawT(root, ellipsize(s.title, W - 16 - (bw + 14 + 10), 15), cx + 16, HeaderH / 2 + 3, 15, textColor, vMiddle, aStart)
    kRect(root, cx + W - 14 - bw, HeaderH / 2 - 7, bw, 20, some(accent), none(Color), 0, 10)
    drawT(root, $s.items.len, cx + W - 14 - bw / 2, HeaderH / 2 + 3, 11, rgba(255, 255, 255), vMiddle, aMiddle)
    grow(cx, 0, cx + W, colBottom)
    for c in cards:
      let ix = cx + ColPad
      let iw = W - 2 * ColPad
      kShadow(root, ix, c.y, iw, c.h, 7, 0.10)
      kRect(root, ix, c.y, iw, c.h, some(cardFill), some(cardEdge), 1, 7)
      let pc = priorityColor(c.item.priority)
      var tx = ix + Pad
      if pc.isSome:
        kRect(root, ix + 5, c.y + 8, 4, c.h - 16, pc, none(Color), 0, 2)
        tx += 4
      var ty = c.y + Pad - 2 + LineH / 2
      for ln in c.lines:
        drawT(root, ln, tx, ty, Px, textColor, vMiddle, aStart); ty += LineH
      if c.item.ticket.len > 0 or c.item.assigned.len > 0:
        let fy = c.y + c.h - FootH / 2 - 2
        let right = ix + iw - Pad
        var tw = 0.0
        if c.item.ticket.len > 0: tw = min(textW(c.item.ticket, 11.5) + 14, (right - tx) * 0.55)
        if c.item.assigned.len > 0:
          var hash = 0
          for ch in c.item.assigned: hash = hash * 31 + int(ch)
          let ac = parseCssColor(avatarPal[abs(hash) mod avatarPal.len]).get
          let room = right - tx - (if tw > 0: tw + 10 else: 0.0) - 24
          let name = ellipsize(c.item.assigned, max(28.0, room), 12)
          let nw = textW(name, 12)
          drawT(root, name, right, fy, 12, muted, vMiddle, aEnd)
          let ax = right - nw - 12
          kCircle(root, ax, fy, 9, some(ac), none(Color), 0)
          drawT(root, initials(c.item.assigned), ax, fy, 9, rgba(255, 255, 255), vMiddle, aMiddle)
        if c.item.ticket.len > 0:
          let tt = ellipsize(c.item.ticket, tw - 14, 11.5)
          kRect(root, tx, fy - 9, tw, 18, some(mixColor(textColor, cardFill, 0.9)), some(mixColor(textColor, cardFill, 0.82)), 1, 9)
          drawT(root, tt, tx + 7, fy, 11.5, muted, vMiddle, aStart)
      grow(ix, c.y, ix + iw, c.y + c.h)
  (root, (minX: minX, minY: minY, maxX: maxX, maxY: maxY))
