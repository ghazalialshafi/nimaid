## Static GIF89a writer (global palette, LZW).
import quant

proc lzw(indices: openArray[byte], minCode: int): seq[byte] =
  let clear = 1 shl minCode
  let eoi = clear + 1
  var o: seq[byte]
  var acc: uint32
  var nb = 0
  var codeSize = minCode + 1
  proc emit(code: int) =
    acc = acc or (uint32(code) shl nb)
    nb += codeSize
    while nb >= 8:
      o.add byte(acc and 0xFF)
      acc = acc shr 8
      nb -= 8
  var dict = newSeq[int32](1 shl 20)       # key = (prefix shl 8) or byte  (prefix < 4096) -> code
  var next = eoi + 1
  var dictGen = newSeq[uint16](1 shl 20)
  var gen = 1'u16
  proc reset() =
    inc gen
    if gen == 0:
      for i in 0 ..< dictGen.len: dictGen[i] = 0
      gen = 1
    next = eoi + 1
    codeSize = minCode + 1
  emit(clear)
  if indices.len == 0:
    emit(eoi)
  else:
    var prefix = int(indices[0])
    for i in 1 ..< indices.len:
      let c = int(indices[i])
      let key = (prefix shl 8) or c
      if dictGen[key] == gen:
        prefix = int(dict[key])
      else:
        emit(prefix)
        if next < 4096:
          dict[key] = int32(next)
          dictGen[key] = gen
          if next == (1 shl codeSize) and codeSize < 12: inc codeSize
          inc next
        else:
          emit(clear)
          reset()
        prefix = c
    emit(prefix)
    emit(eoi)
  if nb > 0: o.add byte(acc and 0xFF)
  o

proc encodeGif*(rgba: openArray[byte], w, h: int, colors = 256): seq[byte] =
  let q = quantize(rgba, w, h, colors)
  var bits = 1
  while (1 shl bits) < q.colors.len: inc bits
  let size = 1 shl bits
  var o: seq[byte]
  for c in "GIF89a": o.add byte(c)
  o.add [byte(w and 255), byte(w shr 8), byte(h and 255), byte(h shr 8), byte(0x80 or ((bits - 1) shl 4) or (bits - 1)), 0, 0]
  for i in 0 ..< size:
    if i < q.colors.len: o.add q.colors[i]
    else: o.add [0'u8, 0, 0]
  if q.hasAlpha:   # graphic control extension: transparent index 0
    o.add [0x21'u8, 0xF9, 4, 1, 0, 0, 0, 0]
  o.add [0x2C'u8, 0, 0, 0, 0, byte(w and 255), byte(w shr 8), byte(h and 255), byte(h shr 8), 0]
  let minCode = max(2, bits)
  o.add byte(minCode)
  let data = lzw(q.indices, minCode)
  var p = 0
  while p < data.len:
    let n = min(255, data.len - p)
    o.add byte(n)
    for k in 0 ..< n: o.add data[p + k]
    p += n
  o.add 0'u8
  o.add 0x3B'u8
  o

proc writeGif*(path: string, rgba: openArray[byte], w, h: int, colors = 256) =
  let d = encodeGif(rgba, w, h, colors)
  let f = open(path, fmWrite)
  defer: f.close()
  if d.len > 0: discard f.writeBuffer(unsafeAddr d[0], d.len)
