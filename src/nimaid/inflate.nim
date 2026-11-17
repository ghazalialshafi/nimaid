## Minimal DEFLATE/gzip decoder (port of the structure of zlib's puff.c). No dependencies.
type
  Huff = object
    count: array[16, int]
    symbol: seq[int]

  BitIn = object
    data: ptr UncheckedArray[byte]
    len, pos: int
    bitBuf, bitCnt: int

const
  lbase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
  lext = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
  dbase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
  dext = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

proc bits(s: var BitIn, need: int): int =
  var v = s.bitBuf
  while s.bitCnt < need:
    if s.pos >= s.len: raise newException(ValueError, "inflate: out of input")
    v = v or (int(s.data[s.pos]) shl s.bitCnt)
    inc s.pos
    s.bitCnt += 8
  s.bitBuf = v shr need
  s.bitCnt -= need
  v and ((1 shl need) - 1)

proc construct(h: var Huff, length: openArray[int]) =
  for i in 0 .. 15: h.count[i] = 0
  for l in length: inc h.count[l]
  h.symbol = newSeq[int](length.len)
  var offs: array[16, int]
  for i in 1 .. 14: offs[i + 1] = offs[i] + h.count[i]
  for sym, l in length:
    if l != 0:
      h.symbol[offs[l]] = sym
      inc offs[l]

proc decode(s: var BitIn, h: Huff): int =
  var code, first, index = 0
  for len in 1 .. 15:
    code = code or s.bits(1)
    let count = h.count[len]
    if code - count < first: return h.symbol[index + (code - first)]
    index += count
    first += count
    first = first shl 1
    code = code shl 1
  raise newException(ValueError, "inflate: bad code")

proc inflateRaw(s: var BitIn, o: var seq[byte]) =
  var fixedL, fixedD: Huff
  block:
    var l: array[288, int]
    for i in 0 .. 143: l[i] = 8
    for i in 144 .. 255: l[i] = 9
    for i in 256 .. 279: l[i] = 7
    for i in 280 .. 287: l[i] = 8
    fixedL.construct(l)
    var d: array[30, int]
    for i in 0 .. 29: d[i] = 5
    fixedD.construct(d)
  var last = 0
  while last == 0:
    last = s.bits(1)
    let typ = s.bits(2)
    if typ == 0:
      s.bitBuf = 0; s.bitCnt = 0
      let n = int(s.data[s.pos]) or (int(s.data[s.pos + 1]) shl 8)
      s.pos += 4
      for i in 0 ..< n: o.add s.data[s.pos + i]
      s.pos += n
    else:
      var lc, dc: Huff
      if typ == 1:
        lc = fixedL; dc = fixedD
      elif typ == 2:
        let nlen = s.bits(5) + 257
        let ndist = s.bits(5) + 1
        let ncode = s.bits(4) + 4
        const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var lengths: array[320, int]
        for i in 0 ..< ncode: lengths[order[i]] = s.bits(3)
        var cl: Huff
        cl.construct(lengths[0 ..< 19])
        var idx = 0
        var ll: array[320, int]
        while idx < nlen + ndist:
          var sym = s.decode(cl)
          if sym < 16:
            ll[idx] = sym; inc idx
          else:
            var prev = 0
            var rep = 0
            if sym == 16:
              prev = ll[idx - 1]; rep = 3 + s.bits(2)
            elif sym == 17: rep = 3 + s.bits(3)
            else: rep = 11 + s.bits(7)
            for _ in 0 ..< rep:
              ll[idx] = prev; inc idx
        lc.construct(ll[0 ..< nlen])
        dc.construct(ll[nlen ..< nlen + ndist])
      else: raise newException(ValueError, "inflate: bad block type")
      while true:
        var sym = s.decode(lc)
        if sym < 256: o.add byte(sym)
        elif sym == 256: break
        else:
          sym -= 257
          let len = lbase[sym] + s.bits(lext[sym])
          let ds = s.decode(dc)
          let dist = dbase[ds] + s.bits(dext[ds])
          let st = o.len - dist
          for i in 0 ..< len: o.add o[st + i]

proc gunzip*(data: openArray[byte]): seq[byte] =
  ## Accepts gzip (1f 8b) or raw deflate streams.
  if data.len == 0: return
  var start = 0
  if data.len > 10 and data[0] == 0x1f and data[1] == 0x8b:
    let flg = data[3]
    start = 10
    if (flg and 4) != 0: start += 2 + int(data[start]) + (int(data[start + 1]) shl 8)
    if (flg and 8) != 0:
      while data[start] != 0: inc start
      inc start
    if (flg and 16) != 0:
      while data[start] != 0: inc start
      inc start
    if (flg and 2) != 0: start += 2
  var s = BitIn(data: cast[ptr UncheckedArray[byte]](unsafeAddr data[0]), len: data.len, pos: start)
  inflateRaw(s, result)
