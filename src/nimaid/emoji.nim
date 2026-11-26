## Colour emoji from Noto Color Emoji (OpenType-SVG): cmap + GSUB ligatures -> per-glyph standalone SVG.
import std/[tables, strutils, unicode, algorithm]
import inflate

type
  Lig = object
    comps: seq[int]
    glyph: int

  EmojiFont = ref object
    d: string
    cmapGroups: seq[(int, int, int)]       ## startChar, endChar, startGid
    svgEntries: seq[(int, int, int, int)]  ## startGid, endGid, offset, length (absolute)
    ligs: Table[int, seq[Lig]]
    docCache: Table[int, string]           ## entry index -> decompressed svg doc
    svgCache: Table[int, string]

var gFont: EmojiFont = nil
let noSvg = ""

proc u16(d: string, o: int): int = (int(d[o]) shl 8) or int(d[o + 1])
proc u32(d: string, o: int): int = (u16(d, o) shl 16) or u16(d, o + 2)

proc coverage(d: string, o: int): seq[int] =
  ## glyph ids in coverage-index order
  let fmt = u16(d, o)
  let n = u16(d, o + 2)
  if fmt == 1:
    for i in 0 ..< n: result.add u16(d, o + 4 + 2 * i)
  else:
    for i in 0 ..< n:
      let s = u16(d, o + 4 + 6 * i)
      let e = u16(d, o + 6 + 6 * i)
      for g in s .. e: result.add g

proc parseLigSubtable(f: EmojiFont, o: int) =
  let d = f.d
  let cov = coverage(d, o + u16(d, o + 2))
  let setCount = u16(d, o + 4)
  for si in 0 ..< setCount:
    let setOff = o + u16(d, o + 6 + 2 * si)
    let first = cov[si]
    let ligCount = u16(d, setOff)
    for li in 0 ..< ligCount:
      let lo = setOff + u16(d, setOff + 2 + 2 * li)
      let lg = u16(d, lo)
      let cc = u16(d, lo + 2)
      var comps = @[first]
      for k in 0 ..< cc - 1: comps.add u16(d, lo + 4 + 2 * k)
      f.ligs.mgetOrPut(first, @[]).add Lig(comps: comps, glyph: lg)

proc unloadEmojiFont*() = gFont = nil   ## disable colour emoji again

proc loadEmojiFontData*(d: string): bool =
  let f = EmojiFont(d: d)
  var tables = initTable[string, (int, int)]()
  for i in 0 ..< u16(d, 4):
    let r = 12 + 16 * i
    tables[d.substr(r, r + 3)] = (u32(d, r + 8), u32(d, r + 12))
  if "cmap" notin tables or "SVG " notin tables: return false
  # cmap: prefer format 12
  let (co, _) = tables["cmap"]
  for i in 0 ..< u16(d, co + 2):
    let r = co + 4 + 8 * i
    let so = co + u32(d, r + 4)
    if u16(d, so) == 12:
      for g in 0 ..< u32(d, so + 12):
        let q = so + 16 + 12 * g
        f.cmapGroups.add (u32(d, q), u32(d, q + 4), u32(d, q + 8))
      break
  # SVG table
  let (so, _) = tables["SVG "]
  let listOff = so + u32(d, so + 2)
  for i in 0 ..< u16(d, listOff):
    let r = listOff + 2 + 12 * i
    f.svgEntries.add (u16(d, r), u16(d, r + 2), listOff + u32(d, r + 4), u32(d, r + 8))
  # GSUB ligatures
  if "GSUB" in tables:
    let (go, _) = tables["GSUB"]
    let lookupList = go + u16(d, go + 8)
    for li in 0 ..< u16(d, lookupList):
      let lo = lookupList + u16(d, lookupList + 2 + 2 * li)
      let typ = u16(d, lo)
      for si in 0 ..< u16(d, lo + 4):
        let sub = lo + u16(d, lo + 6 + 2 * si)
        if typ == 4: f.parseLigSubtable(sub)
        elif typ == 7 and u16(d, sub + 2) == 4: f.parseLigSubtable(sub + u32(d, sub + 4))
  gFont = f
  true

proc loadEmojiFont*(path: string): bool =
  var d: string
  try: d = readFile(path) except IOError: return false
  loadEmojiFontData(d)

proc emojiReady*(): bool = not gFont.isNil

proc gidOf(f: EmojiFont, cp: int): int =
  var lo = 0
  var hi = f.cmapGroups.len - 1
  while lo <= hi:
    let m = (lo + hi) div 2
    let (s, e, g) = f.cmapGroups[m]
    if cp < s: hi = m - 1
    elif cp > e: lo = m + 1
    else: return g + (cp - s)
  0

const bmpEmojiPresentation = [0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3, 0x25FD, 0x25FE,
  0x2614, 0x2615, 0x267F, 0x2693, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26D4,
  0x26EA, 0x26F2, 0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A, 0x270B, 0x2728, 0x274C, 0x274E, 0x2753,
  0x2754, 0x2755, 0x2757, 0x2795, 0x2796, 0x2797, 0x27B0, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55]

proc isEmojiBase(f: EmojiFont, cp: int, vs16: bool): bool =
  if cp < 0xA9 or f.gidOf(cp) == 0: return false
  if cp >= 0x1F000: return true
  if cp in 0x2648 .. 0x2653: return true
  if cp in bmpEmojiPresentation: return true
  vs16 and cp >= 0x203C

proc runeAt(s: string, i: int): (int, int) =
  var r: Rune
  fastRuneAt(s, i, r, false)
  var n = 1
  let b = ord(s[i])
  if b >= 0xF0: n = 4 elif b >= 0xE0: n = 3 elif b >= 0xC0: n = 2
  (int(r), n)

proc clusterAt*(text: string, i: int): int =
  ## Byte length of the emoji cluster starting at i, or 0.
  if gFont.isNil or i >= text.len: return 0
  let f = gFont
  var (cp, n) = runeAt(text, i)
  var j = i + n
  let nextIsVs = j < text.len and runeAt(text, j)[0] == 0xFE0F
  if cp < 0x80:
    # keycap: [0-9#*] FE0F? 20E3
    if cp in {int('0') .. int('9'), int('#'), int('*')}:
      var k = j
      if k < text.len and runeAt(text, k)[0] == 0xFE0F: k += 3
      if k < text.len and runeAt(text, k)[0] == 0x20E3: return k + 3 - i
    return 0
  if cp in 0x1F1E6 .. 0x1F1FF:
    if j < text.len and runeAt(text, j)[0] in 0x1F1E6 .. 0x1F1FF: return j + 4 - i
    return 0
  if not f.isEmojiBase(cp, nextIsVs): return 0
  while true:
    if j < text.len:
      let (c2, n2) = runeAt(text, j)
      if c2 == 0xFE0F or c2 in 0x1F3FB .. 0x1F3FF or c2 in 0xE0020 .. 0xE007F:
        j += n2
        continue
      if c2 == 0x200D and j + n2 < text.len:
        let (c3, n3) = runeAt(text, j + n2)
        if f.gidOf(c3) != 0 and c3 >= 0x203C:
          j += n2 + n3
          continue
    break
  j - i

proc docFor(f: EmojiFont, gid: int): (int, string) =
  for idx, e in f.svgEntries:
    if gid >= e[0] and gid <= e[1]:
      if idx notin f.docCache:
        var raw = newSeq[byte](e[3])
        for k in 0 ..< e[3]: raw[k] = byte(f.d[e[2] + k])
        try: f.docCache[idx] = (if e[3] > 2 and raw[0] == 0x1f: cast[string](gunzip(raw)) else: cast[string](raw))
        except ValueError: f.docCache[idx] = ""
      return (idx, f.docCache[idx])
  (-1, "")

proc findElementEnd(doc: string, start: int): int =
  ## start points at '<' of an element; returns index just past its end (handles nesting & self-closing)
  var i = start
  var depth = 0
  while i < doc.len:
    let lt = doc.find('<', i)
    if lt < 0: return doc.len
    let gt = doc.find('>', lt)
    if gt < 0: return doc.len
    if doc[lt + 1] == '/':
      dec depth
      if depth <= 0: return gt + 1
    elif doc[gt - 1] == '/':
      if depth == 0: return gt + 1
    else: inc depth
    i = gt + 1
  doc.len

proc elementById(doc, id: string): string =
  let key = "id=\"" & id & "\""
  var p = doc.find(key)
  if p < 0: return ""
  let lt = doc.rfind('<', 0, p)
  doc.substr(lt, findElementEnd(doc, lt) - 1)

proc collectRefs(doc, body: string, defs: var OrderedTable[string, string]) =
  var i = 0
  while i < body.len:
    let h = body.find('#', i)
    if h < 0: break
    var e = h + 1
    while e < body.len and (body[e].isAlphaNumeric or body[e] in {'.', '-', '_'}): inc e
    let id = body.substr(h + 1, e - 1)
    if id.len > 0 and id notin defs:
      let el = elementById(doc, id)
      if el.len > 0:
        defs[id] = el
        collectRefs(doc, el, defs)
    i = e

proc glyphSvg(f: EmojiFont, gid: int): string =
  if gid in f.svgCache: return f.svgCache[gid]
  let (idx, doc) = f.docFor(gid)
  var res = ""
  if idx >= 0 and doc.len > 0:
    var g = elementById(doc, "glyph" & $gid)
    if g.len == 0 and f.svgEntries[idx][0] == f.svgEntries[idx][1]:
      let a = doc.find("<g")
      g = if a >= 0: doc.substr(a, findElementEnd(doc, a) - 1) else: ""
    if g.len > 0:
      var defs = initOrderedTable[string, string]()
      collectRefs(doc, g, defs)
      var body = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" version=\"1.1\" viewBox=\"0 -1000 1275 1275\" width=\"1275\" height=\"1275\"><defs>"
      for _, v in defs: body.add v
      body.add "</defs>" & g & "</svg>"
      res = body
  f.svgCache[gid] = res
  res

proc clusterGlyph(f: EmojiFont, cluster: string): int =
  var gids: seq[int]
  var i = 0
  while i < cluster.len:
    let (cp, n) = runeAt(cluster, i)
    i += n
    if cp == 0xFE0F: continue
    gids.add f.gidOf(cp)
  if gids.len == 0: return 0
  # greedy ligature substitution, longest match first
  var outg: seq[int]
  var k = 0
  while k < gids.len:
    var matched = false
    if gids[k] in f.ligs:
      var cands = f.ligs[gids[k]]
      cands.sort(proc(a, b: Lig): int = cmp(b.comps.len, a.comps.len))
      for c in cands:
        if k + c.comps.len <= gids.len and gids[k ..< k + c.comps.len] == c.comps:
          outg.add c.glyph
          k += c.comps.len
          matched = true
          break
    if not matched:
      outg.add gids[k]
      inc k
  outg[0]

proc emojiSvg*(cluster: string): string =
  ## Standalone SVG (viewBox 1275x1275, baseline at y=0) for the emoji cluster, "" if unavailable.
  if gFont.isNil: return noSvg
  let g = gFont.clusterGlyph(cluster)
  if g == 0: return noSvg
  gFont.glyphSvg(g)

const emojiAdvanceEm* = 1.25
const emojiHeightEm* = 1.2
