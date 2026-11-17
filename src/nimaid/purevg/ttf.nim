## TrueType (glyf) reader: cmap 4/12, loca/glyf (simple+composite), hmtx, hhea, legacy 'kern' kerning.
import std/[tables, unicode]
import core

type
  Glyph* = object
    segs*: seq[Seg]      ## font units, y-DOWN (already flipped)
    advance*: float
    gid*: int
  Font* = ref object
    data: string
    unitsPerEm*: int
    ascent*, descent*, lineGap*: int
    numGlyphs, numHM, locaFmt: int
    locaOff, glyfOff, hmtxOff: int
    cmap12, cmap4, kernOff: int
    kernCache: Table[int, float]
    cache: Table[int, Glyph]

proc u8(d: string, o: int): int = (if o < 0 or o >= d.len: 0 else: ord(d[o]))
proc u16(d: string, o: int): int = (u8(d, o) shl 8) or u8(d, o + 1)
proc i16(d: string, o: int): int = (let v = u16(d, o); if v >= 0x8000: v - 0x10000 else: v)
proc u32(d: string, o: int): int = (u16(d, o) shl 16) or u16(d, o + 2)
proc i8(d: string, o: int): int = (let v = u8(d, o); if v >= 128: v - 256 else: v)

proc parseFont*(data: string): Font =
  if data.len < 12: return nil
  let tag = data[0..3]
  if tag != "\0\1\0\0" and tag != "true": return nil   # CFF/OTTO and TTC unsupported
  result = Font(data: data, cmap12: -1, cmap4: -1, kernOff: -1)
  var tabs: Table[string, int]
  for i in 0..<u16(data, 4): tabs[data[12 + 16 * i ..< 16 + 16 * i]] = u32(data, 20 + 16 * i)
  for need in ["head", "hhea", "maxp", "hmtx", "loca", "glyf", "cmap"]:
    if need notin tabs: return nil
  let head = tabs["head"]; let hhea = tabs["hhea"]
  result.unitsPerEm = max(1, u16(data, head + 18))
  result.locaFmt = i16(data, head + 50)
  result.ascent = i16(data, hhea + 4); result.descent = i16(data, hhea + 6); result.lineGap = i16(data, hhea + 8)
  result.numHM = max(1, u16(data, hhea + 34))
  result.numGlyphs = u16(data, tabs["maxp"] + 4)
  result.locaOff = tabs["loca"]; result.glyfOff = tabs["glyf"]; result.hmtxOff = tabs["hmtx"]
  if "kern" in tabs: result.kernOff = tabs["kern"]
  let cm = tabs["cmap"]
  for i in 0..<u16(data, cm + 2):
    let sub = cm + u32(data, cm + 8 + 8 * i)
    let fmt = u16(data, sub)
    if fmt == 12 and result.cmap12 < 0: result.cmap12 = sub
    elif fmt == 4 and result.cmap4 < 0: result.cmap4 = sub

proc lineAdvance*(f: Font): float = float(f.ascent - f.descent + f.lineGap)

proc gidOf*(f: Font, code: int): int =
  let d = f.data
  if f.cmap12 >= 0:
    let s = f.cmap12
    for g in 0..<u32(d, s + 12):
      let o = s + 16 + 12 * g
      if code >= u32(d, o) and code <= u32(d, o + 4): return u32(d, o + 8) + code - u32(d, o)
  if f.cmap4 >= 0 and code < 0x10000:
    let s = f.cmap4; let sc = u16(d, s + 6) div 2
    for i in 0..<sc:
      if code <= u16(d, s + 14 + 2 * i):
        let st = u16(d, s + 16 + 2 * sc + 2 * i)
        if code < st: return 0
        let delta = u16(d, s + 16 + 4 * sc + 2 * i)
        let roPos = s + 16 + 6 * sc + 2 * i
        let ro = u16(d, roPos)
        if ro == 0: return (code + delta) and 0xFFFF
        let g = u16(d, roPos + ro + 2 * (code - st))
        return if g == 0: 0 else: (g + delta) and 0xFFFF
  0

proc locaAt(f: Font, g: int): int =
  if f.locaFmt == 0: u16(f.data, f.locaOff + 2 * g) * 2 else: u32(f.data, f.locaOff + 4 * g)

type RP = tuple[x, y: float, on: bool]

proc contour(pts: seq[RP], segs: var seq[Seg]) =
  if pts.len < 2: return
  var L: seq[RP]
  var k = -1
  for i, p in pts:
    if p.on: k = i; break
  if k >= 0:
    for i in 0..<pts.len: L.add pts[(k + i) mod pts.len]
  else:
    L.add (x: (pts[0].x + pts[^1].x) / 2, y: (pts[0].y + pts[^1].y) / 2, on: true)
    L.add pts
  var cur = L[0]; var ctrl: RP; var has = false
  segs.add Seg(op: 'M', v: [cur.x, cur.y, 0, 0, 0, 0])
  proc quad(segs: var seq[Seg], a, c, b: RP) =
    segs.add Seg(op: 'Q', v: [c.x, c.y, b.x, b.y, 0, 0])
  for i in 1..L.len:
    let p = L[i mod L.len]
    if p.on:
      if has: segs.quad(cur, ctrl, p); has = false
      else: segs.add Seg(op: 'L', v: [p.x, p.y, 0, 0, 0, 0])
      cur = p
    else:
      if has:
        let mid: RP = (x: (ctrl.x + p.x) / 2, y: (ctrl.y + p.y) / 2, on: true)
        segs.quad(cur, ctrl, mid); cur = mid
      ctrl = p; has = true
  segs.add Seg(op: 'Z')

proc loadRaw(f: Font, gid, depth: int): seq[Seg] =
  if gid < 0 or gid >= f.numGlyphs or depth > 6: return
  let o0 = f.locaAt(gid); let o1 = f.locaAt(gid + 1)
  if o1 <= o0: return
  let d = f.data; let g = f.glyfOff + o0
  let nc = i16(d, g)
  var p = g + 10
  if nc >= 0:
    var ends = newSeq[int](nc)
    for i in 0..<nc: ends[i] = u16(d, p + 2 * i)
    p += 2 * nc
    p += 2 + u16(d, p)
    let np = if nc > 0: ends[^1] + 1 else: 0
    var flags = newSeq[int](np); var i = 0
    while i < np:
      let fl = u8(d, p); inc p; flags[i] = fl; inc i
      if (fl and 8) != 0:
        var r = u8(d, p); inc p
        while r > 0 and i < np: flags[i] = fl; inc i; dec r
    var xs = newSeq[int](np); var ys = newSeq[int](np); var v = 0
    for i in 0..<np:
      let fl = flags[i]
      if (fl and 2) != 0: (let dx = u8(d, p); inc p; v += (if (fl and 16) != 0: dx else: -dx))
      elif (fl and 16) == 0: (v += i16(d, p); p += 2)
      xs[i] = v
    v = 0
    for i in 0..<np:
      let fl = flags[i]
      if (fl and 4) != 0: (let dy = u8(d, p); inc p; v += (if (fl and 32) != 0: dy else: -dy))
      elif (fl and 32) == 0: (v += i16(d, p); p += 2)
      ys[i] = v
    var s = 0
    for c in 0..<nc:
      var pts: seq[RP]
      for j in s..ends[c]: pts.add (x: xs[j].float, y: ys[j].float, on: (flags[j] and 1) != 0)
      contour(pts, result)
      s = ends[c] + 1
  else:
    while true:
      let fl = u16(d, p); let gi = u16(d, p + 2); p += 4
      var dx, dy = 0
      if (fl and 1) != 0: (dx = i16(d, p); dy = i16(d, p + 2); p += 4)
      else: (dx = i8(d, p); dy = i8(d, p + 1); p += 2)
      if (fl and 2) == 0: dx = 0; dy = 0
      var a, b, c, e = 0.0
      a = 1; e = 1
      if (fl and 8) != 0: (a = i16(d, p) / 16384; e = a; p += 2)
      elif (fl and 0x40) != 0: (a = i16(d, p) / 16384; e = i16(d, p + 2) / 16384; p += 4)
      elif (fl and 0x80) != 0:
        a = i16(d, p) / 16384; b = i16(d, p + 2) / 16384; c = i16(d, p + 4) / 16384; e = i16(d, p + 6) / 16384; p += 8
      for sg in f.loadRaw(gi, depth + 1):
        var t = sg
        for k in 0..<npts(sg.op):
          let x = sg.v[2 * k]; let y = sg.v[2 * k + 1]
          t.v[2 * k] = a * x + c * y + dx.float
          t.v[2 * k + 1] = b * x + e * y + dy.float
        result.add t
      if (fl and 0x20) == 0: break

proc glyph*(f: Font, code: int): Glyph =
  if code in f.cache: return f.cache[code]
  let gid = f.gidOf(code)
  var g = Glyph()
  g.segs = f.loadRaw(gid, 0)
  for s in g.segs.mitems:
    for k in 0..<3: s.v[2 * k + 1] = -s.v[2 * k + 1]       # y-up -> y-down
  let hm = if gid < f.numHM: gid else: f.numHM - 1
  g.advance = float(u16(f.data, f.hmtxOff + 4 * hm))
  g.gid = gid
  f.cache[code] = g
  g

proc codepoints*(s: string): seq[int] =
  for r in s.runes: result.add int(r)

proc kernPair*(f: Font, l, r: int): float =
  ## Horizontal kerning from the legacy 'kern' table (horizontal, format 0; both Microsoft and Apple layouts).
  if f.kernOff < 0: return 0
  let key = (l shl 16) or r
  if key in f.kernCache: return f.kernCache[key]
  let d = f.data
  var k = f.kernOff
  let apple = u16(d, k) != 0
  var cnt = if apple: u32(d, k + 4) else: u16(d, k + 2)
  k += (if apple: 8 else: 4)
  var res = 0.0
  while cnt > 0:
    dec cnt
    let hs = if apple: 8 else: 6
    let length = if apple: u32(d, k) else: u16(d, k + 2)
    if length < hs: break
    let nxt = k + length
    let cov = u16(d, k + 4)
    let fmt = if apple: cov and 0xff else: cov shr 8
    let horiz = if apple: (cov and 0x8000) == 0 else: (cov and 1) != 0
    let unsup = if apple: (cov and 0x2000) != 0 else: (cov and 2) != 0
    let cross = if apple: (cov and 0x4000) != 0 else: (cov and 4) != 0
    k += hs
    if fmt == 0 and horiz and not unsup and not cross:
      let n = u16(d, k); let base = k + 8
      var lo = 0; var hi = n - 1
      while lo <= hi:
        let mid = (lo + hi) div 2
        let kk = u32(d, base + 6 * mid)
        if kk == key:
          let v = i16(d, base + 6 * mid + 4).float
          res = if not apple and (cov and 8) != 0: v else: res + v
          break
        elif kk < key: lo = mid + 1
        else: hi = mid - 1
    k = nxt
  f.kernCache[key] = res
  res
