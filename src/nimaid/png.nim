## Dependency-free PNG writer: adaptive filters + DEFLATE (real compression), optional palette mode.
import deflate, quant

proc crcTable(): array[256, uint32] =
  for n in 0 .. 255:
    var c = uint32(n)
    for _ in 0 .. 7:
      c = if (c and 1'u32) != 0: 0xEDB88320'u32 xor (c shr 1) else: c shr 1
    result[n] = c

const crcT = crcTable()

proc crc32(data: openArray[byte], init: uint32 = 0): uint32 =
  var c = init xor 0xFFFFFFFF'u32
  for b in data:
    c = crcT[int((c xor uint32(b)) and 0xFF)] xor (c shr 8)
  c xor 0xFFFFFFFF'u32

proc be32(v: uint32): array[4, byte] =
  [byte(v shr 24), byte(v shr 16), byte(v shr 8), byte(v)]

proc addChunk(o: var seq[byte], kind: string, data: openArray[byte]) =
  o.add be32(uint32(data.len))
  var body = newSeq[byte](4 + data.len)
  for i in 0 .. 3: body[i] = byte(kind[i])
  for i in 0 ..< data.len: body[4 + i] = data[i]
  o.add body
  o.add be32(crc32(body))

proc encodePng*(rgba: openArray[byte], width, height: int, colors = 0): seq[byte] =
  ## Truecolour RGBA (colors = 0) or palette (colors = 2..256) PNG with adaptive filtering + DEFLATE.
  doAssert rgba.len == width * height * 4
  result = @[137'u8, 80, 78, 71, 13, 10, 26, 10]
  var bpp = 4
  var rows: seq[byte]
  var ihdr: seq[byte]
  ihdr.add be32(uint32(width)); ihdr.add be32(uint32(height))
  var pal: Palette
  if colors >= 2:
    pal = quantize(rgba, width, height, colors)
    bpp = 1
    ihdr.add [8'u8, 3, 0, 0, 0]
    rows = pal.indices
  else:
    ihdr.add [8'u8, 6, 0, 0, 0]
    rows = @rgba
  result.addChunk("IHDR", ihdr)
  if colors >= 2:
    var plte: seq[byte]
    for c in pal.colors: plte.add [c[0], c[1], c[2]]
    result.addChunk("PLTE", plte)
    if pal.hasAlpha: result.addChunk("tRNS", [0'u8])
  let stride = width * bpp
  var raw = newSeq[byte](height * (stride + 1))
  var cand: array[5, seq[byte]]
  for k in 0 .. 4: cand[k] = newSeq[byte](stride)
  for y in 0 ..< height:
    var bestK = 0
    var bestScore = high(int)
    for k in 0 .. 4:
      var score = 0
      for x in 0 ..< stride:
        let cur = int(rows[y * stride + x])
        let a = if x >= bpp: int(rows[y * stride + x - bpp]) else: 0
        let b = if y > 0: int(rows[(y - 1) * stride + x]) else: 0
        let c = if x >= bpp and y > 0: int(rows[(y - 1) * stride + x - bpp]) else: 0
        var pred = 0
        case k
        of 1: pred = a
        of 2: pred = b
        of 3: pred = (a + b) div 2
        of 4:
          let p = a + b - c
          let pa = abs(p - a)
          let pb = abs(p - b)
          let pc = abs(p - c)
          pred = if pa <= pb and pa <= pc: a elif pb <= pc: b else: c
        else: discard
        let v = byte((cur - pred) and 255)
        cand[k][x] = v
        let sv = if v < 128: int(v) else: 256 - int(v)
        score += sv
      if score < bestScore:
        bestScore = score
        bestK = k
    raw[y * (stride + 1)] = byte(bestK)
    copyMem(addr raw[y * (stride + 1) + 1], addr cand[bestK][0], stride)
  result.addChunk("IDAT", zlibCompress(raw))
  result.addChunk("IEND", newSeq[byte]())

proc writePng*(path: string, rgba: openArray[byte], width, height: int, colors = 0) =
  let data = encodePng(rgba, width, height, colors)
  let f = open(path, fmWrite)
  defer: f.close()
  if data.len > 0: discard f.writeBuffer(unsafeAddr data[0], data.len)
