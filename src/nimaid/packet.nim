## Packet diagrams (Mermaid `packet` / `packet-beta`): packet.langium + parser.ts (row splitting) + renderer.ts.
import std/[strutils, math, options, json]
import gfx, theme, painter, textmetrics, drawkit, config, chartheme, chartkit

type
  Block = object
    start, stop: int
    label: string
  Raw = object
    hasStart, hasEnd: bool
    start, stop, bits: int
    label: string

proc parsePacket(text, fmTitle: string, bitsPerRow: int): (string, seq[seq[Block]]) =
  var title = fmTitle
  var raws: seq[Raw]
  var started = false
  for rawLine in text.replace("\r\n", "\n").split('\n'):
    var l = rawLine
    let pc = l.find("%%")
    if pc >= 0: l = l[0 ..< pc]
    let t = l.strip()
    if t.len == 0: continue
    let low = t.toLowerAscii
    if not started:
      if not low.startsWith("packet"): raise newException(ChartError, "Parse error: expecting 'packet'")
      started = true; continue
    if low.startsWith("title"): title = t[5 .. ^1].strip(); continue
    if low.startsWith("acctitle") or low.startsWith("accdescr"): continue
    let ci = t.find(':')
    if ci <= 0: raise newException(ChartError, "Parse error: a field is '0-15: \"Label\"', '106: \"Flag\"' or '+8: \"Label\"', got '" & t & "'")
    let spec = t[0 ..< ci].strip()
    let label = unquote(t[ci + 1 .. ^1])
    var r = Raw(label: label)
    try:
      if spec.startsWith("+"): r.bits = parseInt(spec[1 .. ^1].strip())
      elif '-' in spec:
        let parts = spec.split('-')
        r.hasStart = true; r.hasEnd = true; r.start = parseInt(parts[0].strip()); r.stop = parseInt(parts[1].strip())
      else: r.hasStart = true; r.start = parseInt(spec)
    except ValueError: raise newException(ChartError, "Parse error: bad bit range '" & spec & "'")
    raws.add r
  # parser.ts populate(): contiguity checks and splitting across rows
  var words: seq[seq[Block]]
  var word: seq[Block]
  var lastBit = -1
  var row = 1
  for r in raws:
    var start = r.start
    var stop = r.stop
    if r.hasStart and r.hasEnd and stop < start:
      raise newException(ChartError, "Packet block " & $start & " - " & $stop & " is invalid. End must be greater than start.")
    if not r.hasStart: start = lastBit + 1
    if start != lastBit + 1:
      raise newException(ChartError, "Packet block " & $start & " - " & $(if r.hasEnd: stop else: start) &
                         " is not contiguous. It should start from " & $(lastBit + 1) & ".")
    if not r.hasStart and r.bits == 0:
      raise newException(ChartError, "Packet block " & $start & " is invalid. Cannot have a zero bit field.")
    if not r.hasEnd: stop = start + max(r.bits, 1) - 1
    lastBit = stop
    # split the field across 32-bit rows
    var cur = Block(start: start, stop: stop, label: r.label)
    while true:
      let rowEnd = row * bitsPerRow - 1
      if cur.stop <= rowEnd:
        word.add cur
        if cur.stop == rowEnd: words.add word; word = @[]; inc row
        break
      word.add Block(start: cur.start, stop: rowEnd, label: cur.label)
      words.add word; word = @[]; inc row
      cur.start = rowEnd + 1
  if word.len > 0: words.add word
  (title, words)

proc packetScene*(text: string, cv: ChartVars, fmTitle = ""): (Pvg_Paint, DiagramBounds) =
  let pc = cv.cfg.cfgSub("packet")
  let rowH = pc.cfgFloat("rowHeight", 32)
  let bitW = pc.cfgFloat("bitWidth", 32)
  let bitsPerRow = int(pc.cfgFloat("bitsPerRow", 32))
  let showBits = pc.cfgBool("showBits", true)
  let descending = pc.cfgStr("bitOrder", "ascending") == "descending"
  let padX = pc.cfgFloat("paddingX", 5)
  var padY = pc.cfgFloat("paddingY", 5)
  if showBits: padY += 10
  let (title, words) = parsePacket(text, fmTitle, bitsPerRow)
  if words.len == 0: raise newException(ChartError, "Packet has no fields")
  let blockFill = cv.color("packet.blockFillColor", rgba(0xEF, 0xEF, 0xEF))
  let blockStroke = cv.color("packet.blockStrokeColor", rgba(0, 0, 0))
  let strokeW = cv.num("packet.blockStrokeWidth", 1)
  let labelColor = cv.color("packet.labelColor", rgba(0, 0, 0))
  let startColor = cv.color("packet.startByteColor", rgba(0, 0, 0))
  let endColor = cv.color("packet.endByteColor", rgba(0, 0, 0))
  let titleColor = cv.color("packet.titleColor", rgba(0, 0, 0))
  let labelPx = cv.num("packet.labelFontSize", 12)
  let bytePx = cv.num("packet.byteFontSize", 10)
  let titlePx = cv.num("packet.titleFontSize", 14)
  let totalRowH = rowH + padY
  let svgH = totalRowH * float(words.len + 1) - (if title.len > 0: 0.0 else: rowH)
  let svgW = bitW * float(bitsPerRow) + 2
  let root = pvg_scene_new()
  for wi, w in words:
    let wy = float(wi) * totalRowH + padY
    for b in w:
      let bits = b.stop - b.start + 1
      let firstCol = b.start mod bitsPerRow
      let col = if descending: bitsPerRow - firstCol - bits else: firstCol
      let bx = float(col) * bitW + 1
      let width = float(bits) * bitW - padX
      kRect(root, bx, wy, width, rowH, some(blockFill), some(blockStroke), strokeW)
      drawT(root, b.label, bx + width / 2, wy + rowH / 2, labelPx, labelColor, vMiddle, aMiddle)
      if not showBits: continue
      let (lead, trail) = if descending: (b.stop, b.start) else: (b.start, b.stop)
      let single = bits == 1
      drawTextPx(root, $lead, bx + (if single: width / 2 else: 0.0), wy - 2, bytePx, startColor, (if single: aMiddle else: aStart))
      if not single: drawTextPx(root, $trail, bx + width, wy - 2, bytePx, endColor, aEnd)
  drawT(root, title, svgW / 2, svgH - totalRowH / 2, titlePx, titleColor, vMiddle, aMiddle)
  (root, (minX: 0.0, minY: 0.0, maxX: svgW, maxY: svgH))
