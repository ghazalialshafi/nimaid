## DEFLATE compressor (LZ77 hash chains + dynamic Huffman blocks) with zlib wrapper. No dependencies.
import std/algorithm

type
  BitW = object
    o: seq[byte]
    acc: uint64
    n: int

proc put(w: var BitW, v: uint32, bits: int) =
  w.acc = w.acc or (uint64(v) shl w.n)
  w.n += bits
  while w.n >= 8:
    w.o.add byte(w.acc and 0xFF)
    w.acc = w.acc shr 8
    w.n -= 8

proc flush(w: var BitW) =
  if w.n > 0:
    w.o.add byte(w.acc and 0xFF)
    w.acc = 0
    w.n = 0

proc rev(code: uint32, len: int): uint32 =
  var c = code
  for _ in 0 ..< len:
    result = (result shl 1) or (c and 1)
    c = c shr 1

const
  lenBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
  lenExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
  distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
  distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

proc lenCode(l: int): int =
  var i = 28
  while lenBase[i] > l: dec i
  i
proc distCode(d: int): int =
  var i = 29
  while distBase[i] > d: dec i
  i

type Tok = object
  lit: uint16        # literal byte, or length (3..258) when dist > 0
  dist: uint16

proc codeLengths(freqIn: openArray[int], limit: int): seq[int] =
  ## Length-limited Huffman code lengths (zlib-style overflow repair).
  let freq = @freqIn
  let n = freq.len
  result = newSeq[int](n)
  var syms: seq[int]
  for i in 0 ..< n:
    if freq[i] > 0: syms.add i
  if syms.len == 0: return
  if syms.len == 1:
    result[syms[0]] = 1
    return
  # build tree with two-queue method
  syms.sort(proc(a, b: int): int = cmp(freq[a], freq[b]))
  let m = syms.len
  var weight = newSeq[int](2 * m)
  var parent = newSeq[int](2 * m)
  for i in 0 ..< m: weight[i] = freq[syms[i]]
  var leaf = 0
  var node = m
  var intern = m
  for _ in 0 ..< m - 1:
    var pick: array[2, int]
    for k in 0 .. 1:
      if leaf < m and (intern >= node or weight[leaf] <= weight[intern]):
        pick[k] = leaf
        inc leaf
      else:
        pick[k] = intern
        inc intern
    weight[node] = weight[pick[0]] + weight[pick[1]]
    parent[pick[0]] = node
    parent[pick[1]] = node
    inc node
  var depth = newSeq[int](2 * m)
  depth[node - 1] = 0
  for i in countdown(node - 2, 0): depth[i] = depth[parent[i]] + 1
  var blCount = newSeq[int](limit + 2)
  var overflow = 0
  for i in 0 ..< m:
    var d = depth[i]
    if d > limit:
      d = limit
      inc overflow
    inc blCount[d]
  while overflow > 0:
    var bits = limit - 1
    while blCount[bits] == 0: dec bits
    dec blCount[bits]
    blCount[bits + 1] += 2
    dec blCount[limit]
    overflow -= 2
  # least frequent symbols get the longest codes (syms sorted ascending by freq)
  var idx = 0
  for bits in countdown(limit, 1):
    for _ in 0 ..< blCount[bits]:
      result[syms[idx]] = bits
      inc idx

proc canonCodes(lens: openArray[int]): seq[uint32] =
  result = newSeq[uint32](lens.len)
  var blCount: array[17, int]
  for l in lens: inc blCount[l]
  blCount[0] = 0
  var next: array[17, uint32]
  var code = 0'u32
  for b in 1 .. 15:
    code = (code + uint32(blCount[b - 1])) shl 1
    next[b] = code
  for i, l in lens:
    if l != 0:
      result[i] = rev(next[l], l)
      inc next[l]

proc writeBlock(w: var BitW, toks: openArray[Tok], final: bool) =
  var lf = newSeq[int](286)
  var df = newSeq[int](30)
  for t in toks:
    if t.dist == 0: inc lf[t.lit]
    else:
      inc lf[257 + lenCode(int(t.lit))]
      inc df[distCode(int(t.dist))]
  lf[256] = 1
  var dUsed = false
  for x in df:
    if x > 0: dUsed = true
  if not dUsed: df[0] = 1
  let ll = codeLengths(lf, 15)
  let dl = codeLengths(df, 15)
  var nl = 286
  while nl > 257 and ll[nl - 1] == 0: dec nl
  var nd = 30
  while nd > 1 and dl[nd - 1] == 0: dec nd
  # run-length encode code lengths
  var all: seq[int]
  for i in 0 ..< nl: all.add ll[i]
  for i in 0 ..< nd: all.add dl[i]
  var rle: seq[(int, int)]   # (symbol, extra)
  var i = 0
  while i < all.len:
    let v = all[i]
    var run = 1
    while i + run < all.len and all[i + run] == v: inc run
    if v == 0 and run >= 3:
      let r = min(run, 138)
      if r >= 11: rle.add (18, r - 11) else: rle.add (17, r - 3)
      i += r
    elif v != 0 and run >= 4:
      rle.add (v, 0)
      let r = min(run - 1, 6)
      rle.add (16, r - 3)
      i += 1 + r
    else:
      rle.add (v, 0)
      inc i
  var cf = newSeq[int](19)
  for (s, _) in rle: inc cf[s]
  let cl = codeLengths(cf, 7)
  let cc = canonCodes(cl)
  const order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
  var ncl = 19
  while ncl > 4 and cl[order[ncl - 1]] == 0: dec ncl
  w.put(if final: 1 else: 0, 1)
  w.put(2, 2)
  w.put(uint32(nl - 257), 5)
  w.put(uint32(nd - 1), 5)
  w.put(uint32(ncl - 4), 4)
  for k in 0 ..< ncl: w.put(uint32(cl[order[k]]), 3)
  for (s, e) in rle:
    w.put(cc[s], cl[s])
    if s == 16: w.put(uint32(e), 2)
    elif s == 17: w.put(uint32(e), 3)
    elif s == 18: w.put(uint32(e), 7)
  let lc = canonCodes(ll)
  let dc = canonCodes(dl)
  for t in toks:
    if t.dist == 0:
      w.put(lc[t.lit], ll[t.lit])
    else:
      let l = int(t.lit)
      let c = lenCode(l)
      w.put(lc[257 + c], ll[257 + c])
      if lenExtra[c] > 0: w.put(uint32(l - lenBase[c]), lenExtra[c])
      let d = int(t.dist)
      let dcode = distCode(d)
      w.put(dc[dcode], dl[dcode])
      if distExtra[dcode] > 0: w.put(uint32(d - distBase[dcode]), distExtra[dcode])
  w.put(lc[256], ll[256])

proc adler32(data: openArray[byte]): uint32 =
  var a = 1'u32
  var b = 0'u32
  var i = 0
  while i < data.len:
    let e = min(i + 5552, data.len)
    while i < e:
      a += uint32(data[i])
      b += a
      inc i
    a = a mod 65521
    b = b mod 65521
  (b shl 16) or a

proc zlibCompress*(data: openArray[byte], chain = 48): seq[byte] =
  var w = BitW()
  w.o = @[0x78'u8, 0x9C]
  const win = 32768
  const hbits = 16
  let n = data.len
  var head = newSeq[int32](1 shl hbits)
  for i in 0 ..< head.len: head[i] = -1
  var prev = newSeq[int32](win)
  var toks: seq[Tok]
  template hash(i: int): int =
    ((int(data[i]) shl 10) xor (int(data[i + 1]) shl 5) xor int(data[i + 2])) and ((1 shl hbits) - 1)
  var i = 0
  while i < n:
    var bestLen = 0
    var bestDist = 0
    if i + 2 < n:
      let h = hash(i)
      var cand = int(head[h])
      var tries = chain
      let maxLen = min(258, n - i)
      while cand >= 0 and i - cand <= win and tries > 0:
        var l = 0
        while l < maxLen and data[cand + l] == data[i + l]: inc l
        if l > bestLen:
          bestLen = l
          bestDist = i - cand
          if l == maxLen: break
        cand = int(prev[cand and (win - 1)])
        dec tries
      prev[i and (win - 1)] = head[h]
      head[h] = int32(i)
    if bestLen >= 3:
      toks.add Tok(lit: uint16(bestLen), dist: uint16(bestDist))
      # index skipped positions so later matches can find them
      for k in 1 ..< bestLen:
        let p = i + k
        if p + 2 < n:
          let h2 = hash(p)
          prev[p and (win - 1)] = head[h2]
          head[h2] = int32(p)
      i += bestLen
    else:
      toks.add Tok(lit: uint16(data[i]), dist: 0)
      inc i
    if toks.len >= 60000:
      w.writeBlock(toks, false)
      toks.setLen(0)
  w.writeBlock(toks, true)
  w.flush()
  let ad = adler32(data)
  w.o.add [byte(ad shr 24), byte(ad shr 16), byte(ad shr 8), byte(ad)]
  w.o
