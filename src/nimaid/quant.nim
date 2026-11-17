## Median-cut colour quantiser (diagram images have few distinct colours, so it works on unique colours).
import std/[tables, algorithm]

type
  Rgb = array[3, int]
  Palette* = object
    colors*: seq[array[3, uint8]]
    indices*: seq[byte]
    hasAlpha*: bool         ## index 0 reserved for transparent pixels when true

proc quantize*(rgba: openArray[byte], w, h: int, maxColors: int): Palette =
  let mc = max(2, min(256, maxColors))
  var counts = initTable[uint32, int]()
  var anyAlpha = false
  for p in 0 ..< w * h:
    let a = rgba[p * 4 + 3]
    if a < 128:
      anyAlpha = true
      continue
    let key = (uint32(rgba[p * 4]) shl 16) or (uint32(rgba[p * 4 + 1]) shl 8) or uint32(rgba[p * 4 + 2])
    counts.mgetOrPut(key, 0) += 1
  result.hasAlpha = anyAlpha
  let budget = if anyAlpha: mc - 1 else: mc
  type Box = object
    cols: seq[(uint32, int)]
  var boxes: seq[Box]
  var all: seq[(uint32, int)]
  for k, v in counts: all.add (k, v)
  boxes.add Box(cols: all)
  proc chan(c: uint32, ch: int): int = int((c shr (16 - 8 * ch)) and 0xFF)
  while boxes.len < budget:
    # split the box with the widest channel range among boxes with > 1 colour
    var bi = -1
    var bestRange = 0
    var bestCh = 0
    for i, b in boxes:
      if b.cols.len < 2: continue
      for ch in 0 .. 2:
        var lo = 255
        var hi = 0
        for (c, _) in b.cols:
          lo = min(lo, chan(c, ch))
          hi = max(hi, chan(c, ch))
        let r = (hi - lo)
        if r > bestRange:
          bestRange = r
          bi = i
          bestCh = ch
    if bi < 0: break
    var cols = boxes[bi].cols
    cols.sort(proc(a, b: (uint32, int)): int = cmp(chan(a[0], bestCh), chan(b[0], bestCh)))
    var total = 0
    for (_, n) in cols: total += n
    var acc = 0
    var cut = 1
    for i, (_, n) in cols:
      acc += n
      if acc * 2 >= total:
        cut = max(1, min(cols.len - 1, i + 1))
        break
    boxes[bi] = Box(cols: cols[0 ..< cut])
    boxes.add Box(cols: cols[cut .. ^1])
  if anyAlpha: result.colors.add [0'u8, 0, 0]
  var lookup = initTable[uint32, byte]()
  for bi, b in boxes:
    var sr, sg, sb, tot = 0
    for (c, n) in b.cols:
      sr += chan(c, 0) * n
      sg += chan(c, 1) * n
      sb += chan(c, 2) * n
      tot += n
    let idx = byte(result.colors.len)
    if tot == 0: tot = 1
    result.colors.add [uint8(sr div tot), uint8(sg div tot), uint8(sb div tot)]
    for (c, _) in b.cols: lookup[c] = idx
  result.indices = newSeq[byte](w * h)
  for p in 0 ..< w * h:
    if rgba[p * 4 + 3] < 128:
      result.indices[p] = 0
    else:
      let key = (uint32(rgba[p * 4]) shl 16) or (uint32(rgba[p * 4 + 1]) shl 8) or uint32(rgba[p * 4 + 2])
      result.indices[p] = lookup[key]
