## Pure Nim port of NanoSVG (parser) - https://github.com/memononen/nanosvg
##
## Parses a simple subset of SVG into a list of shapes made of cubic bezier
## paths. Behaviour follows the original C implementation (float32 math,
## same quirks) so results are comparable one-to-one.
##
## Compile with `-d:nanosvgAllColorKeywords` to enable all CSS color names
## (the C library only knows 10 by default).
##
## Differences from the C API: memory is managed by Nim (`nsvgDelete` is a
## no-op kept for API parity), `NSVGpath.npts` is a proc, shapes/paths are
## `seq`s instead of linked lists and `nsvgParse` takes an immutable string.

import std/[math, strutils, algorithm]

const
  NSVG_PI* = 3.14159265358979323846264338327'f32
  NSVG_KAPPA90 = 0.5522847493'f32
  NSVG_MAX_ATTR = 128
  NSVG_MAX_DASHES* = 8
  NSVG_MAX_CLASSES = 32
  NSVG_XML_MAX_ATTRIBS = 256
  nsvgFlagsVisible* = 1'u8

type
  Xform* = array[6, float32]

  NSVGpaintType* = enum
    nsvgPaintUndef = -1, nsvgPaintNone = 0, nsvgPaintColor = 1,
    nsvgPaintLinearGradient = 2, nsvgPaintRadialGradient = 3
  NSVGspreadType* = enum nsvgSpreadPad, nsvgSpreadReflect, nsvgSpreadRepeat
  NSVGlineJoin* = enum nsvgJoinMiter, nsvgJoinRound, nsvgJoinBevel
  NSVGlineCap* = enum nsvgCapButt, nsvgCapRound, nsvgCapSquare
  NSVGfillRule* = enum nsvgFillNonZero, nsvgFillEvenOdd
  NSVGpaintOrder* = enum nsvgPaintFill = 0, nsvgPaintMarkers = 1, nsvgPaintStroke = 2

  NSVGgradientStop* = object
    color*: uint32      ## ABGR packed (r | g<<8 | b<<16 | a<<24)
    offset*: float32

  NSVGgradient* = ref object
    xform*: Xform
    spread*: NSVGspreadType
    fx*, fy*: float32
    stops*: seq[NSVGgradientStop]

  NSVGpaint* = object
    kind*: NSVGpaintType
    color*: uint32
    gradient*: NSVGgradient

  NSVGpath* = object
    pts*: seq[float32]  ## x0,y0, [cpx1,cpy1,cpx2,cpy2,x1,y1], ...
    closed*: bool
    bounds*: array[4, float32]

  NSVGshape* = object
    id*: string
    fill*, stroke*: NSVGpaint
    opacity*: float32
    strokeWidth*: float32
    strokeDashOffset*: float32
    strokeDashArray*: array[8, float32]
    strokeDashCount*: int
    strokeLineJoin*: NSVGlineJoin
    strokeLineCap*: NSVGlineCap
    miterLimit*: float32
    fillRule*: NSVGfillRule
    paintOrder*: uint8
    flags*: uint8
    bounds*: array[4, float32]
    fillGradient*, strokeGradient*: string
    xform*: Xform
    paths*: seq[NSVGpath]

  NSVGimage* = ref object
    width*, height*: float32
    shapes*: seq[NSVGshape]

# ---------------------------------------------------------------------------
# Internal types

type
  NSVGcoordinate = object
    value: float32
    units: int

  NSVGgradientData = ref object
    id, href: string
    kind: NSVGpaintType
    x1, y1, x2, y2: NSVGcoordinate           # linear
    cx, cy, r, fx, fy: NSVGcoordinate        # radial
    spread: NSVGspreadType
    objectSpace: bool
    xform: Xform
    stops: seq[NSVGgradientStop]

  NSVGattrib = object
    id: string
    xform: Xform
    fillColor, strokeColor: uint32
    opacity, fillOpacity, strokeOpacity: float32
    fillGradient, strokeGradient: string
    strokeWidth, strokeDashOffset: float32
    strokeDashArray: array[NSVG_MAX_DASHES, float32]
    strokeDashCount: int
    strokeLineJoin: NSVGlineJoin
    strokeLineCap: NSVGlineCap
    miterLimit: float32
    fillRule: NSVGfillRule
    fontSize: float32
    stopColor: uint32
    stopOpacity, stopOffset: float32
    hasFill, hasStroke: int
    visible: bool
    paintOrder: uint8

  NSVGstyleDeclaration = object
    className, propertiesText: string

  NSVGparser = ref object
    attr: array[NSVG_MAX_ATTR, NSVGattrib]
    attrHead: int
    pts: seq[float32]
    plist: seq[NSVGpath]
    image: NSVGimage
    styles: seq[NSVGstyleDeclaration]
    gradients: seq[NSVGgradientData]
    viewMinx, viewMiny, viewWidth, viewHeight: float32
    alignX, alignY, alignType: int
    dpi: float32
    pathFlag, defsFlag, styleFlag: bool

  Attrs = seq[(string, string)]

const
  UNITS_USER = 0
  UNITS_PX = 1
  UNITS_PT = 2
  UNITS_PC = 3
  UNITS_MM = 4
  UNITS_CM = 5
  UNITS_IN = 6
  UNITS_PERCENT = 7
  UNITS_EM = 8
  UNITS_EX = 9
  ALIGN_MIN = 0
  ALIGN_MID = 1
  ALIGN_MAX = 2
  ALIGN_NONE = 0
  ALIGN_MEET = 1
  ALIGN_SLICE = 2

# ---------------------------------------------------------------------------
# Small helpers (strings behave like NUL terminated C strings via `at`)

template at(s: string, i: int): char =
  (if i >= 0 and i < s.len: s[i] else: '\0')

func isSpace(c: char): bool = c in {' ', '\t', '\n', '\v', '\f', '\r'}
func isDigit(c: char): bool = c in {'0'..'9'}
func minf(a, b: float32): float32 = (if a < b: a else: b)
func maxf(a, b: float32): float32 = (if a > b: a else: b)
func rgb(r, g, b: uint32): uint32 = r or (g shl 8) or (b shl 16)

func truncTo(s: string, n: int): string =
  if s.len > n: s[0 ..< n] else: s

# ---------------------------------------------------------------------------
# Transforms

proc xformIdentity(t: var Xform) = t = [1'f32, 0, 0, 1, 0, 0]
proc xformSetTranslation(t: var Xform, tx, ty: float32) = t = [1'f32, 0, 0, 1, tx, ty]
proc xformSetScale(t: var Xform, sx, sy: float32) = t = [sx, 0'f32, 0, sy, 0, 0]
proc xformSetSkewX(t: var Xform, a: float32) = t = [1'f32, 0, tan(a), 1, 0, 0]
proc xformSetSkewY(t: var Xform, a: float32) = t = [1'f32, tan(a), 0, 1, 0, 0]
proc xformSetRotation(t: var Xform, a: float32) =
  let cs = cos(a)
  let sn = sin(a)
  t = [cs, sn, -sn, cs, 0'f32, 0]

proc xformMultiply(t: var Xform, s: Xform) =
  let t0 = t[0] * s[0] + t[1] * s[2]
  let t2 = t[2] * s[0] + t[3] * s[2]
  let t4 = t[4] * s[0] + t[5] * s[2] + s[4]
  t[1] = t[0] * s[1] + t[1] * s[3]
  t[3] = t[2] * s[1] + t[3] * s[3]
  t[5] = t[4] * s[1] + t[5] * s[3] + s[5]
  t[0] = t0
  t[2] = t2
  t[4] = t4

proc xformInverse(inv: var Xform, t: var Xform) =
  let det = float64(t[0]) * float64(t[3]) - float64(t[2]) * float64(t[1])
  if det > -1e-6 and det < 1e-6:
    xformIdentity(t)
    return
  let invdet = 1.0 / det
  inv[0] = float32(float64(t[3]) * invdet)
  inv[2] = float32(float64(-t[2]) * invdet)
  inv[4] = float32((float64(t[2]) * float64(t[5]) - float64(t[3]) * float64(t[4])) * invdet)
  inv[1] = float32(float64(-t[1]) * invdet)
  inv[3] = float32(float64(t[0]) * invdet)
  inv[5] = float32((float64(t[1]) * float64(t[4]) - float64(t[0]) * float64(t[5])) * invdet)

proc xformPremultiply(t: var Xform, s: Xform) =
  var s2 = s
  xformMultiply(s2, t)
  t = s2

proc xformPoint(dx, dy: var float32, x, y: float32, t: Xform) =
  dx = x * t[0] + y * t[2] + t[4]
  dy = x * t[1] + y * t[3] + t[5]

# ---------------------------------------------------------------------------
# Curve bounds

const NSVG_EPSILON = 1e-12

func ptInBounds(x, y: float32, b: array[4, float32]): bool =
  x >= b[0] and x <= b[2] and y >= b[1] and y <= b[3]

func evalBezier(t, p0, p1, p2, p3: float64): float64 =
  let it = 1.0 - t
  it*it*it*p0 + 3.0*it*it*t*p1 + 3.0*it*t*t*p2 + t*t*t*p3

proc curveBounds(bounds: var array[4, float32], c: openArray[float32]) =
  bounds[0] = minf(c[0], c[6])
  bounds[1] = minf(c[1], c[7])
  bounds[2] = maxf(c[0], c[6])
  bounds[3] = maxf(c[1], c[7])
  if ptInBounds(c[2], c[3], bounds) and ptInBounds(c[4], c[5], bounds):
    return
  for i in 0 .. 1:
    let v0 = float64(c[i])
    let v1 = float64(c[2 + i])
    let v2 = float64(c[4 + i])
    let v3 = float64(c[6 + i])
    let a = -3.0 * v0 + 9.0 * v1 - 9.0 * v2 + 3.0 * v3
    let b = 6.0 * v0 - 12.0 * v1 + 6.0 * v2
    let cc = 3.0 * v1 - 3.0 * v0
    var roots: array[2, float64]
    var count = 0
    if abs(a) < NSVG_EPSILON:
      if abs(b) > NSVG_EPSILON:
        let t = -cc / b
        if t > NSVG_EPSILON and t < 1.0 - NSVG_EPSILON:
          roots[count] = t; inc count
    else:
      let b2ac = b*b - 4.0*cc*a
      if b2ac > NSVG_EPSILON:
        var t = (-b + sqrt(b2ac)) / (2.0 * a)
        if t > NSVG_EPSILON and t < 1.0 - NSVG_EPSILON:
          roots[count] = t; inc count
        t = (-b - sqrt(b2ac)) / (2.0 * a)
        if t > NSVG_EPSILON and t < 1.0 - NSVG_EPSILON:
          roots[count] = t; inc count
    for j in 0 ..< count:
      let v = float32(evalBezier(roots[j], v0, v1, v2, v3))
      bounds[i] = minf(bounds[i], v)
      bounds[2 + i] = maxf(bounds[2 + i], v)

func encodePaintOrder(a, b, c: NSVGpaintOrder): uint8 =
  uint8((ord(a) and 3) or ((ord(b) and 3) shl 2) or ((ord(c) and 3) shl 4))

# ---------------------------------------------------------------------------
# Parser state

proc createParser(): NSVGparser =
  result = NSVGparser(image: NSVGimage())
  let a = addr result.attr[0]
  xformIdentity(a.xform)
  a.fillColor = rgb(0, 0, 0)
  a.strokeColor = rgb(0, 0, 0)
  a.opacity = 1
  a.fillOpacity = 1
  a.strokeOpacity = 1
  a.stopOpacity = 1
  a.strokeWidth = 1
  a.strokeLineJoin = nsvgJoinMiter
  a.strokeLineCap = nsvgCapButt
  a.miterLimit = 4
  a.fillRule = nsvgFillNonZero
  a.hasFill = 1
  a.visible = true
  a.paintOrder = encodePaintOrder(nsvgPaintFill, nsvgPaintStroke, nsvgPaintMarkers)

proc npts(p: NSVGparser): int {.inline.} = p.pts.len div 2
proc npts*(path: NSVGpath): int {.inline.} =
  ## Total number of bezier points.
  path.pts.len div 2

proc resetPath(p: NSVGparser) = p.pts.setLen(0)

proc addPoint(p: NSVGparser, x, y: float32) =
  p.pts.add x
  p.pts.add y

proc moveTo(p: NSVGparser, x, y: float32) =
  if p.npts > 0:
    p.pts[p.pts.len - 2] = x
    p.pts[p.pts.len - 1] = y
  else:
    p.addPoint(x, y)

proc lineTo(p: NSVGparser, x, y: float32) =
  if p.npts > 0:
    let px = p.pts[p.pts.len - 2]
    let py = p.pts[p.pts.len - 1]
    let dx = x - px
    let dy = y - py
    p.addPoint(px + dx/3.0, py + dy/3.0)
    p.addPoint(x - dx/3.0, y - dy/3.0)
    p.addPoint(x, y)

proc cubicBezTo(p: NSVGparser, cpx1, cpy1, cpx2, cpy2, x, y: float32) =
  if p.npts > 0:
    p.addPoint(cpx1, cpy1)
    p.addPoint(cpx2, cpy2)
    p.addPoint(x, y)

proc getAttr(p: NSVGparser): var NSVGattrib {.inline.} = p.attr[p.attrHead]

proc pushAttr(p: NSVGparser) =
  if p.attrHead < NSVG_MAX_ATTR - 1:
    inc p.attrHead
    p.attr[p.attrHead] = p.attr[p.attrHead - 1]

proc popAttr(p: NSVGparser) =
  if p.attrHead > 0: dec p.attrHead

func actualLength(p: NSVGparser): float32 =
  sqrt(p.viewWidth*p.viewWidth + p.viewHeight*p.viewHeight) / sqrt(2.0'f32)

proc convertToPixels(p: NSVGparser, c: NSVGcoordinate, orig, length: float32): float32 =
  case c.units
  of UNITS_USER, UNITS_PX: c.value
  of UNITS_PT: c.value / 72.0'f32 * p.dpi
  of UNITS_PC: c.value / 6.0'f32 * p.dpi
  of UNITS_MM: c.value / 25.4'f32 * p.dpi
  of UNITS_CM: c.value / 2.54'f32 * p.dpi
  of UNITS_IN: c.value * p.dpi
  of UNITS_EM: c.value * p.getAttr.fontSize
  of UNITS_EX: c.value * p.getAttr.fontSize * 0.52'f32
  of UNITS_PERCENT: orig + c.value / 100.0'f32 * length
  else: c.value

proc findGradientData(p: NSVGparser, id: string): NSVGgradientData =
  if id.len == 0: return nil
  for i in countdown(p.gradients.high, 0):   # most recently added first
    if p.gradients[i].id == id: return p.gradients[i]
  nil

proc createGradient(p: NSVGparser, id: string, localBounds: array[4, float32],
                    xform: Xform): NSVGgradient =
  let data = p.findGradientData(id)
  if data == nil: return nil
  var stops: seq[NSVGgradientStop]
  var found = false
  var refd = data
  var refIter = 0
  while refd != nil:
    if not found and refd.stops.len > 0:
      stops = refd.stops
      found = true
      break
    let nextRef = p.findGradientData(refd.href)
    if nextRef == refd: break
    refd = nextRef
    inc refIter
    if refIter > 32: break
  if not found: return nil
  result = NSVGgradient()
  var ox, oy, sw, sh: float32
  if data.objectSpace:
    ox = localBounds[0]
    oy = localBounds[1]
    sw = localBounds[2] - localBounds[0]
    sh = localBounds[3] - localBounds[1]
  else:
    ox = p.viewMinx
    oy = p.viewMiny
    sw = p.viewWidth
    sh = p.viewHeight
  let sl = sqrt(sw*sw + sh*sh) / sqrt(2.0'f32)
  if data.kind == nsvgPaintLinearGradient:
    let x1 = p.convertToPixels(data.x1, ox, sw)
    let y1 = p.convertToPixels(data.y1, oy, sh)
    let x2 = p.convertToPixels(data.x2, ox, sw)
    let y2 = p.convertToPixels(data.y2, oy, sh)
    let dx = x2 - x1
    let dy = y2 - y1
    result.xform = [dy, -dx, dx, dy, x1, y1]
  else:
    let cx = p.convertToPixels(data.cx, ox, sw)
    let cy = p.convertToPixels(data.cy, oy, sh)
    let fx = p.convertToPixels(data.fx, ox, sw)
    let fy = p.convertToPixels(data.fy, oy, sh)
    let r = p.convertToPixels(data.r, 0, sl)
    result.xform = [r, 0'f32, 0, r, cx, cy]
    result.fx = fx / r
    result.fy = fy / r
  xformMultiply(result.xform, data.xform)
  xformMultiply(result.xform, xform)
  result.spread = data.spread
  result.stops = stops

func getAverageScale(t: Xform): float32 =
  let sx = sqrt(t[0]*t[0] + t[2]*t[2])
  let sy = sqrt(t[1]*t[1] + t[3]*t[3])
  (sx + sy) * 0.5'f32

proc getLocalBounds(bounds: var array[4, float32], shape: NSVGshape, xform: Xform) =
  var curve: array[8, float32]
  var curveB: array[4, float32]
  var first = true
  for path in shape.paths:
    xformPoint(curve[0], curve[1], path.pts[0], path.pts[1], xform)
    var i = 0
    while i < path.npts - 1:
      xformPoint(curve[2], curve[3], path.pts[(i+1)*2], path.pts[(i+1)*2+1], xform)
      xformPoint(curve[4], curve[5], path.pts[(i+2)*2], path.pts[(i+2)*2+1], xform)
      xformPoint(curve[6], curve[7], path.pts[(i+3)*2], path.pts[(i+3)*2+1], xform)
      curveBounds(curveB, curve)
      if first:
        bounds = curveB
        first = false
      else:
        bounds[0] = minf(bounds[0], curveB[0])
        bounds[1] = minf(bounds[1], curveB[1])
        bounds[2] = maxf(bounds[2], curveB[2])
        bounds[3] = maxf(bounds[3], curveB[3])
      curve[0] = curve[6]
      curve[1] = curve[7]
      i += 3

proc addShape(p: NSVGparser) =
  let attr = p.getAttr
  if p.plist.len == 0: return
  var shape: NSVGshape
  shape.id = attr.id
  shape.fillGradient = attr.fillGradient
  shape.strokeGradient = attr.strokeGradient
  shape.xform = attr.xform
  let scale = getAverageScale(attr.xform)
  shape.strokeWidth = attr.strokeWidth * scale
  shape.strokeDashOffset = attr.strokeDashOffset * scale
  shape.strokeDashCount = attr.strokeDashCount
  for i in 0 ..< attr.strokeDashCount:
    shape.strokeDashArray[i] = attr.strokeDashArray[i] * scale
  shape.strokeLineJoin = attr.strokeLineJoin
  shape.strokeLineCap = attr.strokeLineCap
  shape.miterLimit = attr.miterLimit
  shape.fillRule = attr.fillRule
  shape.opacity = attr.opacity
  shape.paintOrder = attr.paintOrder
  # The C version builds a head-inserted list, i.e. paths end up reversed.
  shape.paths = p.plist
  shape.paths.reverse()
  p.plist.setLen(0)
  shape.bounds = shape.paths[0].bounds
  for i in 1 ..< shape.paths.len:
    let b = shape.paths[i].bounds
    shape.bounds[0] = minf(shape.bounds[0], b[0])
    shape.bounds[1] = minf(shape.bounds[1], b[1])
    shape.bounds[2] = maxf(shape.bounds[2], b[2])
    shape.bounds[3] = maxf(shape.bounds[3], b[3])
  case attr.hasFill
  of 0: shape.fill.kind = nsvgPaintNone
  of 1:
    shape.fill.kind = nsvgPaintColor
    shape.fill.color = attr.fillColor or (uint32(attr.fillOpacity * 255) shl 24)
  of 2: shape.fill.kind = nsvgPaintUndef
  else: discard
  case attr.hasStroke
  of 0: shape.stroke.kind = nsvgPaintNone
  of 1:
    shape.stroke.kind = nsvgPaintColor
    shape.stroke.color = attr.strokeColor or (uint32(attr.strokeOpacity * 255) shl 24)
  of 2: shape.stroke.kind = nsvgPaintUndef
  else: discard
  shape.flags = if attr.visible: nsvgFlagsVisible else: 0'u8
  p.image.shapes.add shape

proc addPath(p: NSVGparser, closed: bool) =
  let attr = p.getAttr
  if p.npts < 4: return
  if closed: p.lineTo(p.pts[0], p.pts[1])
  if (p.npts mod 3) != 1: return
  var path: NSVGpath
  path.closed = closed
  path.pts = newSeq[float32](p.pts.len)
  for i in 0 ..< p.npts:
    xformPoint(path.pts[i*2], path.pts[i*2+1], p.pts[i*2], p.pts[i*2+1], attr.xform)
  var bounds: array[4, float32]
  var i = 0
  while i < path.npts - 1:
    curveBounds(bounds, path.pts.toOpenArray(i*2, i*2 + 7))
    if i == 0:
      path.bounds = bounds
    else:
      path.bounds[0] = minf(path.bounds[0], bounds[0])
      path.bounds[1] = minf(path.bounds[1], bounds[1])
      path.bounds[2] = maxf(path.bounds[2], bounds[2])
      path.bounds[3] = maxf(path.bounds[3], bounds[3])
    i += 3
  p.plist.add path

# ---------------------------------------------------------------------------
# Number / color parsing

proc readDigits(s: string, i: var int): int64 =
  ## Like strtoll on a digit run (saturating).
  while isDigit(s.at(i)):
    let d = int64(ord(s[i]) - ord('0'))
    if result > (high(int64) - d) div 10: result = high(int64)
    else: result = result * 10 + d
    inc i

# Own string to float: the std one depends on locale in C; kept for fidelity.
proc nsvgAtof(s: string, start = 0): float64 =
  var cur = start
  var sign = 1.0
  var res = 0.0
  var hasInt, hasFrac = false
  if s.at(cur) == '+': inc cur
  elif s.at(cur) == '-':
    sign = -1.0
    inc cur
  if isDigit(s.at(cur)):
    let st = cur
    let v = readDigits(s, cur)
    if cur != st:
      res = float64(v)
      hasInt = true
  if s.at(cur) == '.':
    inc cur
    if isDigit(s.at(cur)):
      let st = cur
      let v = readDigits(s, cur)
      if cur != st:
        res += float64(v) / pow(10.0, float64(cur - st))
        hasFrac = true
  if not hasInt and not hasFrac: return 0.0
  if s.at(cur) in {'e', 'E'}:
    inc cur
    var j = cur
    var esign = 1'i64
    if s.at(j) == '+': inc j
    elif s.at(j) == '-':
      esign = -1
      inc j
    if isDigit(s.at(j)):
      let e = readDigits(s, j)
      res *= pow(10.0, float64(esign * e))
  res * sign

proc parseNumber(s: string, i: var int, size = 64): string =
  ## Reads a number token starting at `i` (max size-1 chars kept).
  let last = size - 1
  template put(c: char) =
    if result.len < last: result.add c
  if s.at(i) in {'-', '+'}:
    put s[i]; inc i
  while isDigit(s.at(i)):
    put s[i]; inc i
  if s.at(i) == '.':
    put s[i]; inc i
    while isDigit(s.at(i)):
      put s[i]; inc i
  if s.at(i) in {'e', 'E'} and s.at(i+1) notin {'m', 'x'}:
    put s[i]; inc i
    if s.at(i) in {'-', '+'}:
      put s[i]; inc i
    while isDigit(s.at(i)):
      put s[i]; inc i

proc getNextPathItemWhenArcFlag(s: string, i: var int): string =
  while s.at(i) != '\0' and (isSpace(s.at(i)) or s.at(i) == ','): inc i
  if i >= s.len: return ""
  if s[i] in {'0', '1'}:
    result = $s[i]
    inc i

proc getNextPathItem(s: string, i: var int): string =
  while s.at(i) != '\0' and (isSpace(s.at(i)) or s.at(i) == ','): inc i
  if i >= s.len: return ""
  let c = s[i]
  if c in {'-', '+', '.'} or isDigit(c):
    result = parseNumber(s, i, 64)
  else:
    result = $c
    inc i

proc parseColorHex(s: string): uint32 =
  # emulates sscanf("#%2x%2x%2x") then sscanf("#%1x%1x%1x")
  proc scan(maxd: int): (bool, array[3, uint32]) =
    var i = 1
    var vals: array[3, uint32]
    for k in 0 .. 2:
      while isSpace(s.at(i)): inc i
      var n = 0
      var v = 0'u32
      while n < maxd and s.at(i) in HexDigits:
        v = v * 16 + uint32(parseHexInt($s[i]))
        inc i; inc n
      if n == 0: return (false, vals)
      vals[k] = v
    (true, vals)
  let (ok2, v2) = scan(2)
  if ok2: return rgb(v2[0], v2[1], v2[2])
  let (ok1, v1) = scan(1)
  if ok1: return rgb(v1[0]*17, v1[1]*17, v1[2]*17)
  rgb(128, 128, 128)

proc parseColorRGB(s: string): uint32 =
  var rgbi: array[3, uint32]
  var okInt = true
  block intParse:   # sscanf("rgb(%u, %u, %u)")
    var i = 4
    for k in 0 .. 2:
      while isSpace(s.at(i)): inc i
      if s.at(i) == '+': inc i
      if not isDigit(s.at(i)):
        okInt = false
        break intParse
      var v = 0'u64
      while isDigit(s.at(i)):
        v = min(v * 10 + uint64(ord(s[i]) - ord('0')), 0xFFFFFFFF'u64)
        inc i
      rgbi[k] = uint32(v)
      if k < 2:
        while isSpace(s.at(i)): inc i
        if s.at(i) != ',':
          okInt = false
          break intParse
        inc i
  if not okInt:
    const delim = [',', ',', ')']
    var rgbf: array[3, float32]
    var i = 4
    var n = 0
    while n < 3:
      while isSpace(s.at(i)): inc i
      if s.at(i) == '+': inc i
      if s.at(i) == '\0': break
      rgbf[n] = float32(nsvgAtof(s, i))
      while isDigit(s.at(i)): inc i
      if s.at(i) == '.':
        inc i
        if not isDigit(s.at(i)): break
        while isDigit(s.at(i)): inc i
      if s.at(i) == '%': inc i
      else: break
      while isSpace(s.at(i)): inc i
      if s.at(i) == delim[n]: inc i
      else: break
      inc n
    if n == 3:
      for k in 0 .. 2: rgbi[k] = uint32(round(rgbf[k] * 2.55'f32))
    else:
      rgbi = [128'u32, 128, 128]
  for k in 0 .. 2:
    if rgbi[k] > 255: rgbi[k] = 255
  rgb(rgbi[0], rgbi[1], rgbi[2])

const namedColors = [
  ("red", rgb(255, 0, 0)),
  ("green", rgb(0, 128, 0)),
  ("blue", rgb(0, 0, 255)),
  ("yellow", rgb(255, 255, 0)),
  ("cyan", rgb(0, 255, 255)),
  ("magenta", rgb(255, 0, 255)),
  ("black", rgb(0, 0, 0)),
  ("grey", rgb(128, 128, 128)),
  ("gray", rgb(128, 128, 128)),
  ("white", rgb(255, 255, 255)),
]

const extendedColors = [
  ("aliceblue", rgb(240, 248, 255)),
  ("antiquewhite", rgb(250, 235, 215)),
  ("aqua", rgb(0, 255, 255)),
  ("aquamarine", rgb(127, 255, 212)),
  ("azure", rgb(240, 255, 255)),
  ("beige", rgb(245, 245, 220)),
  ("bisque", rgb(255, 228, 196)),
  ("blanchedalmond", rgb(255, 235, 205)),
  ("blueviolet", rgb(138, 43, 226)),
  ("brown", rgb(165, 42, 42)),
  ("burlywood", rgb(222, 184, 135)),
  ("cadetblue", rgb(95, 158, 160)),
  ("chartreuse", rgb(127, 255, 0)),
  ("chocolate", rgb(210, 105, 30)),
  ("coral", rgb(255, 127, 80)),
  ("cornflowerblue", rgb(100, 149, 237)),
  ("cornsilk", rgb(255, 248, 220)),
  ("crimson", rgb(220, 20, 60)),
  ("darkblue", rgb(0, 0, 139)),
  ("darkcyan", rgb(0, 139, 139)),
  ("darkgoldenrod", rgb(184, 134, 11)),
  ("darkgray", rgb(169, 169, 169)),
  ("darkgreen", rgb(0, 100, 0)),
  ("darkgrey", rgb(169, 169, 169)),
  ("darkkhaki", rgb(189, 183, 107)),
  ("darkmagenta", rgb(139, 0, 139)),
  ("darkolivegreen", rgb(85, 107, 47)),
  ("darkorange", rgb(255, 140, 0)),
  ("darkorchid", rgb(153, 50, 204)),
  ("darkred", rgb(139, 0, 0)),
  ("darksalmon", rgb(233, 150, 122)),
  ("darkseagreen", rgb(143, 188, 143)),
  ("darkslateblue", rgb(72, 61, 139)),
  ("darkslategray", rgb(47, 79, 79)),
  ("darkslategrey", rgb(47, 79, 79)),
  ("darkturquoise", rgb(0, 206, 209)),
  ("darkviolet", rgb(148, 0, 211)),
  ("deeppink", rgb(255, 20, 147)),
  ("deepskyblue", rgb(0, 191, 255)),
  ("dimgray", rgb(105, 105, 105)),
  ("dimgrey", rgb(105, 105, 105)),
  ("dodgerblue", rgb(30, 144, 255)),
  ("firebrick", rgb(178, 34, 34)),
  ("floralwhite", rgb(255, 250, 240)),
  ("forestgreen", rgb(34, 139, 34)),
  ("fuchsia", rgb(255, 0, 255)),
  ("gainsboro", rgb(220, 220, 220)),
  ("ghostwhite", rgb(248, 248, 255)),
  ("gold", rgb(255, 215, 0)),
  ("goldenrod", rgb(218, 165, 32)),
  ("greenyellow", rgb(173, 255, 47)),
  ("honeydew", rgb(240, 255, 240)),
  ("hotpink", rgb(255, 105, 180)),
  ("indianred", rgb(205, 92, 92)),
  ("indigo", rgb(75, 0, 130)),
  ("ivory", rgb(255, 255, 240)),
  ("khaki", rgb(240, 230, 140)),
  ("lavender", rgb(230, 230, 250)),
  ("lavenderblush", rgb(255, 240, 245)),
  ("lawngreen", rgb(124, 252, 0)),
  ("lemonchiffon", rgb(255, 250, 205)),
  ("lightblue", rgb(173, 216, 230)),
  ("lightcoral", rgb(240, 128, 128)),
  ("lightcyan", rgb(224, 255, 255)),
  ("lightgoldenrodyellow", rgb(250, 250, 210)),
  ("lightgray", rgb(211, 211, 211)),
  ("lightgreen", rgb(144, 238, 144)),
  ("lightgrey", rgb(211, 211, 211)),
  ("lightpink", rgb(255, 182, 193)),
  ("lightsalmon", rgb(255, 160, 122)),
  ("lightseagreen", rgb(32, 178, 170)),
  ("lightskyblue", rgb(135, 206, 250)),
  ("lightslategray", rgb(119, 136, 153)),
  ("lightslategrey", rgb(119, 136, 153)),
  ("lightsteelblue", rgb(176, 196, 222)),
  ("lightyellow", rgb(255, 255, 224)),
  ("lime", rgb(0, 255, 0)),
  ("limegreen", rgb(50, 205, 50)),
  ("linen", rgb(250, 240, 230)),
  ("maroon", rgb(128, 0, 0)),
  ("mediumaquamarine", rgb(102, 205, 170)),
  ("mediumblue", rgb(0, 0, 205)),
  ("mediumorchid", rgb(186, 85, 211)),
  ("mediumpurple", rgb(147, 112, 219)),
  ("mediumseagreen", rgb(60, 179, 113)),
  ("mediumslateblue", rgb(123, 104, 238)),
  ("mediumspringgreen", rgb(0, 250, 154)),
  ("mediumturquoise", rgb(72, 209, 204)),
  ("mediumvioletred", rgb(199, 21, 133)),
  ("midnightblue", rgb(25, 25, 112)),
  ("mintcream", rgb(245, 255, 250)),
  ("mistyrose", rgb(255, 228, 225)),
  ("moccasin", rgb(255, 228, 181)),
  ("navajowhite", rgb(255, 222, 173)),
  ("navy", rgb(0, 0, 128)),
  ("oldlace", rgb(253, 245, 230)),
  ("olive", rgb(128, 128, 0)),
  ("olivedrab", rgb(107, 142, 35)),
  ("orange", rgb(255, 165, 0)),
  ("orangered", rgb(255, 69, 0)),
  ("orchid", rgb(218, 112, 214)),
  ("palegoldenrod", rgb(238, 232, 170)),
  ("palegreen", rgb(152, 251, 152)),
  ("paleturquoise", rgb(175, 238, 238)),
  ("palevioletred", rgb(219, 112, 147)),
  ("papayawhip", rgb(255, 239, 213)),
  ("peachpuff", rgb(255, 218, 185)),
  ("peru", rgb(205, 133, 63)),
  ("pink", rgb(255, 192, 203)),
  ("plum", rgb(221, 160, 221)),
  ("powderblue", rgb(176, 224, 230)),
  ("purple", rgb(128, 0, 128)),
  ("rosybrown", rgb(188, 143, 143)),
  ("royalblue", rgb(65, 105, 225)),
  ("saddlebrown", rgb(139, 69, 19)),
  ("salmon", rgb(250, 128, 114)),
  ("sandybrown", rgb(244, 164, 96)),
  ("seagreen", rgb(46, 139, 87)),
  ("seashell", rgb(255, 245, 238)),
  ("sienna", rgb(160, 82, 45)),
  ("silver", rgb(192, 192, 192)),
  ("skyblue", rgb(135, 206, 235)),
  ("slateblue", rgb(106, 90, 205)),
  ("slategray", rgb(112, 128, 144)),
  ("slategrey", rgb(112, 128, 144)),
  ("snow", rgb(255, 250, 250)),
  ("springgreen", rgb(0, 255, 127)),
  ("steelblue", rgb(70, 130, 180)),
  ("tan", rgb(210, 180, 140)),
  ("teal", rgb(0, 128, 128)),
  ("thistle", rgb(216, 191, 216)),
  ("tomato", rgb(255, 99, 71)),
  ("turquoise", rgb(64, 224, 208)),
  ("violet", rgb(238, 130, 238)),
  ("wheat", rgb(245, 222, 179)),
  ("whitesmoke", rgb(245, 245, 245)),
  ("yellowgreen", rgb(154, 205, 50))
]

proc parseColorName(s: string): uint32 =
  for (name, c) in namedColors:
    if name == s: return c
  when defined(nanosvgAllColorKeywords):
    for (name, c) in extendedColors:
      if name == s: return c
  rgb(128, 128, 128)

proc parseColor(str: string): uint32 =
  var i = 0
  while str.at(i) == ' ': inc i
  let s = str[min(i, str.len) .. ^1]
  if s.len >= 1 and s[0] == '#': parseColorHex(s)
  elif s.len >= 4 and s[0..3] == "rgb(": parseColorRGB(s)
  else: parseColorName(s)

func parseOpacity(s: string): float32 =
  result = float32(nsvgAtof(s))
  if result < 0: result = 0
  if result > 1: result = 1

func parseMiterLimit(s: string): float32 =
  result = float32(nsvgAtof(s))
  if result < 0: result = 0

func parseUnits(s: string, i = 0): int =
  let a = s.at(i)
  let b = s.at(i+1)
  if a == 'p' and b == 'x': UNITS_PX
  elif a == 'p' and b == 't': UNITS_PT
  elif a == 'p' and b == 'c': UNITS_PC
  elif a == 'm' and b == 'm': UNITS_MM
  elif a == 'c' and b == 'm': UNITS_CM
  elif a == 'i' and b == 'n': UNITS_IN
  elif a == '%': UNITS_PERCENT
  elif a == 'e' and b == 'm': UNITS_EM
  elif a == 'e' and b == 'x': UNITS_EX
  else: UNITS_USER

func isCoordinate(s: string): bool =
  var i = 0
  if s.at(i) in {'-', '+'}: inc i
  isDigit(s.at(i)) or s.at(i) == '.'

proc parseCoordinateRaw(s: string): NSVGcoordinate =
  var i = 0
  let buf = parseNumber(s, i, 64)
  result.units = parseUnits(s, i)
  result.value = float32(nsvgAtof(buf))

func coord(v: float32, units: int): NSVGcoordinate =
  NSVGcoordinate(value: v, units: units)

proc parseCoordinate(p: NSVGparser, s: string, orig, length: float32): float32 =
  p.convertToPixels(parseCoordinateRaw(s), orig, length)

# ---------------------------------------------------------------------------
# Transform attribute

proc parseTransformArgs(s: string, args: var openArray[float32], na: var int): int =
  ## Returns the length consumed (0 on too many args, 1 when malformed).
  na = 0
  var i = 0
  while s.at(i) != '\0' and s.at(i) != '(': inc i
  if s.at(i) == '\0': return 1
  var e = i
  while s.at(e) != '\0' and s.at(e) != ')': inc e
  if s.at(e) == '\0': return 1
  while i < e:
    let c = s[i]
    if c in {'-', '+', '.'} or isDigit(c):
      if na >= args.len: return 0
      let it = parseNumber(s, i, 64)
      args[na] = float32(nsvgAtof(it))
      inc na
    else:
      inc i
  e

proc parseTransform(xform: var Xform, str: string) =
  var t: Xform
  xformIdentity(xform)
  xformIdentity(t)
  var i = 0
  while i < str.len:
    let s = str[i .. ^1]
    var len = 0
    var na = 0
    if s.startsWith("matrix"):
      var a: array[6, float32]
      len = parseTransformArgs(s, a, na)
      if na == 6: t = a
    elif s.startsWith("translate"):
      var a: array[2, float32]
      len = parseTransformArgs(s, a, na)
      if na == 1: a[1] = 0
      xformSetTranslation(t, a[0], a[1])
    elif s.startsWith("scale"):
      var a: array[2, float32]
      len = parseTransformArgs(s, a, na)
      if na == 1: a[1] = a[0]
      xformSetScale(t, a[0], a[1])
    elif s.startsWith("rotate"):
      var a: array[3, float32]
      len = parseTransformArgs(s, a, na)
      if na == 1: a[1] = 0; a[2] = 0
      var m: Xform
      xformIdentity(m)
      var tt: Xform
      if na > 1:
        xformSetTranslation(tt, -a[1], -a[2])
        xformMultiply(m, tt)
      xformSetRotation(tt, a[0] / 180.0'f32 * NSVG_PI)
      xformMultiply(m, tt)
      if na > 1:
        xformSetTranslation(tt, a[1], a[2])
        xformMultiply(m, tt)
      t = m
    elif s.startsWith("skewX"):
      var a: array[1, float32]
      len = parseTransformArgs(s, a, na)
      xformSetSkewX(t, a[0] / 180.0'f32 * NSVG_PI)
    elif s.startsWith("skewY"):
      var a: array[1, float32]
      len = parseTransformArgs(s, a, na)
      xformSetSkewY(t, a[0] / 180.0'f32 * NSVG_PI)
    else:
      inc i
      continue
    if len != 0:
      i += len
    else:
      inc i
      continue
    xformPremultiply(xform, t)

func parseUrl(str: string): string =
  var i = 4
  if str.at(i) == '#': inc i
  while result.len < 63 and str.at(i) != '\0' and str.at(i) != ')':
    result.add str[i]
    inc i

func parseLineCap(s: string): NSVGlineCap =
  case s
  of "butt": nsvgCapButt
  of "round": nsvgCapRound
  of "square": nsvgCapSquare
  else: nsvgCapButt

func parseLineJoin(s: string): NSVGlineJoin =
  case s
  of "miter": nsvgJoinMiter
  of "round": nsvgJoinRound
  of "bevel": nsvgJoinBevel
  else: nsvgJoinMiter

func parseFillRule(s: string): NSVGfillRule =
  case s
  of "nonzero": nsvgFillNonZero
  of "evenodd": nsvgFillEvenOdd
  else: nsvgFillNonZero

func parsePaintOrder(s: string): uint8 =
  const F = nsvgPaintFill
  const M = nsvgPaintMarkers
  const S = nsvgPaintStroke
  case s
  of "normal", "fill stroke markers": encodePaintOrder(F, S, M)
  of "fill markers stroke": encodePaintOrder(F, M, S)
  of "markers fill stroke": encodePaintOrder(M, F, S)
  of "markers stroke fill": encodePaintOrder(M, S, F)
  of "stroke fill markers": encodePaintOrder(S, F, M)
  of "stroke markers fill": encodePaintOrder(S, M, F)
  else: encodePaintOrder(F, S, M)

proc getNextDashItem(s: string, i: var int): string =
  while s.at(i) != '\0' and (isSpace(s.at(i)) or s.at(i) == ','): inc i
  while s.at(i) != '\0' and not isSpace(s.at(i)) and s.at(i) != ',':
    if result.len < 63: result.add s[i]
    inc i

proc parseStrokeDashArray(p: NSVGparser, str: string,
                          arr: var array[NSVG_MAX_DASHES, float32]): int =
  if str.at(0) == 'n': return 0
  var i = 0
  var sum = 0'f32
  while i < str.len:
    let item = getNextDashItem(str, i)
    if item.len == 0: break
    if result < NSVG_MAX_DASHES:
      arr[result] = abs(p.parseCoordinate(item, 0, p.actualLength))
      inc result
  for k in 0 ..< result: sum += arr[k]
  if sum <= 1e-6'f32: result = 0

proc parseStyle(p: NSVGparser, str: string)

proc applyClassStyles(p: NSVGparser, value: string) =
  var i = 0
  while i < value.len:
    while isSpace(value.at(i)): inc i
    if i >= value.len: break
    let st = i
    while i < value.len and not isSpace(value[i]): inc i
    let cls = value[st ..< i]
    # head-inserted list in C: most recently declared style is visited first
    for k in countdown(p.styles.high, 0):
      if p.styles[k].className == cls:
        let txt = p.styles[k].propertiesText
        p.parseStyle(txt)

proc parseAttr(p: NSVGparser, name, value: string): bool =
  template attr: untyped = p.getAttr
  case name
  of "style": p.parseStyle(value)
  of "display":
    if value == "none": attr.visible = false
  of "fill":
    if value == "none": attr.hasFill = 0
    elif value.startsWith("url("):
      attr.hasFill = 2
      attr.fillGradient = parseUrl(value)
    else:
      attr.hasFill = 1
      attr.fillColor = parseColor(value)
  of "opacity": attr.opacity = parseOpacity(value)
  of "fill-opacity": attr.fillOpacity = parseOpacity(value)
  of "stroke":
    if value == "none": attr.hasStroke = 0
    elif value.startsWith("url("):
      attr.hasStroke = 2
      attr.strokeGradient = parseUrl(value)
    else:
      attr.hasStroke = 1
      attr.strokeColor = parseColor(value)
  of "stroke-width": attr.strokeWidth = p.parseCoordinate(value, 0, p.actualLength)
  of "stroke-dasharray":
    let n = p.parseStrokeDashArray(value, attr.strokeDashArray)
    attr.strokeDashCount = n
  of "stroke-dashoffset": attr.strokeDashOffset = p.parseCoordinate(value, 0, p.actualLength)
  of "stroke-opacity": attr.strokeOpacity = parseOpacity(value)
  of "stroke-linecap": attr.strokeLineCap = parseLineCap(value)
  of "stroke-linejoin": attr.strokeLineJoin = parseLineJoin(value)
  of "stroke-miterlimit": attr.miterLimit = parseMiterLimit(value)
  of "fill-rule": attr.fillRule = parseFillRule(value)
  of "font-size": attr.fontSize = p.parseCoordinate(value, 0, p.actualLength)
  of "transform":
    var xf: Xform
    parseTransform(xf, value)
    xformPremultiply(attr.xform, xf)
  of "stop-color": attr.stopColor = parseColor(value)
  of "stop-opacity": attr.stopOpacity = parseOpacity(value)
  of "offset": attr.stopOffset = p.parseCoordinate(value, 0, 1)
  of "paint-order": attr.paintOrder = parsePaintOrder(value)
  of "id": attr.id = truncTo(value, 63)
  of "class": p.applyClassStyles(value)
  else: return false
  true

proc parseNameValue(p: NSVGparser, s: string, start, e: int): bool =
  # literal port working on indices; NUL (end of string) counts as space
  template sp(c: char): bool = (c == '\0' or isSpace(c))
  var str = start
  while str < e and s.at(str) != ':': inc str
  var val = str
  while str > start and (s.at(str) == ':' or sp(s.at(str))): dec str
  inc str
  var n = min(str - start, 511)
  let name = if n > 0: s[start ..< start + n] else: ""
  while val < e and (s.at(val) == ':' or isSpace(s.at(val))): inc val
  n = min(e - val, 511)
  let value = if n > 0: s[val ..< val + n] else: ""
  p.parseAttr(name, value)

proc parseStyle(p: NSVGparser, str: string) =
  var i = 0
  while i < str.len:
    while i < str.len and isSpace(str[i]): inc i
    let start = i
    while i < str.len and str[i] != ';': inc i
    var e = i
    while e > start and (str.at(e) == ';' or isSpace(str.at(e)) or str.at(e) == '\0'):
      dec e
    inc e
    discard p.parseNameValue(str, start, e)
    if i < str.len: inc i

proc parseAttribs(p: NSVGparser, attr: Attrs) =
  for (n, v) in attr:
    if n == "style": p.parseStyle(v)
    else: discard p.parseAttr(n, v)

# ---------------------------------------------------------------------------
# Path

func getArgsPerElement(cmd: char): int =
  case cmd
  of 'v', 'V', 'h', 'H': 1
  of 'm', 'M', 'l', 'L', 't', 'T': 2
  of 'q', 'Q', 's', 'S': 4
  of 'c', 'C': 6
  of 'a', 'A': 7
  of 'z', 'Z': 0
  else: -1

proc pathMoveTo(p: NSVGparser, cpx, cpy: var float32, args: openArray[float32], rel: bool) =
  if rel:
    cpx += args[0]; cpy += args[1]
  else:
    cpx = args[0]; cpy = args[1]
  p.moveTo(cpx, cpy)

proc pathLineTo(p: NSVGparser, cpx, cpy: var float32, args: openArray[float32], rel: bool) =
  if rel:
    cpx += args[0]; cpy += args[1]
  else:
    cpx = args[0]; cpy = args[1]
  p.lineTo(cpx, cpy)

proc pathHLineTo(p: NSVGparser, cpx, cpy: var float32, args: openArray[float32], rel: bool) =
  if rel: cpx += args[0] else: cpx = args[0]
  p.lineTo(cpx, cpy)

proc pathVLineTo(p: NSVGparser, cpx, cpy: var float32, args: openArray[float32], rel: bool) =
  if rel: cpy += args[0] else: cpy = args[0]
  p.lineTo(cpx, cpy)

proc pathCubicBezTo(p: NSVGparser, cpx, cpy, cpx2, cpy2: var float32,
                    args: openArray[float32], rel: bool) =
  var cx1, cy1, cx2, cy2, x2, y2: float32
  if rel:
    cx1 = cpx + args[0]; cy1 = cpy + args[1]
    cx2 = cpx + args[2]; cy2 = cpy + args[3]
    x2 = cpx + args[4]; y2 = cpy + args[5]
  else:
    cx1 = args[0]; cy1 = args[1]
    cx2 = args[2]; cy2 = args[3]
    x2 = args[4]; y2 = args[5]
  p.cubicBezTo(cx1, cy1, cx2, cy2, x2, y2)
  cpx2 = cx2; cpy2 = cy2
  cpx = x2; cpy = y2

proc pathCubicBezShortTo(p: NSVGparser, cpx, cpy, cpx2, cpy2: var float32,
                         args: openArray[float32], rel: bool) =
  var cx2, cy2, x2, y2: float32
  let x1 = cpx
  let y1 = cpy
  if rel:
    cx2 = cpx + args[0]; cy2 = cpy + args[1]
    x2 = cpx + args[2]; y2 = cpy + args[3]
  else:
    cx2 = args[0]; cy2 = args[1]
    x2 = args[2]; y2 = args[3]
  let cx1 = 2*x1 - cpx2
  let cy1 = 2*y1 - cpy2
  p.cubicBezTo(cx1, cy1, cx2, cy2, x2, y2)
  cpx2 = cx2; cpy2 = cy2
  cpx = x2; cpy = y2

proc pathQuadBezTo(p: NSVGparser, cpx, cpy, cpx2, cpy2: var float32,
                   args: openArray[float32], rel: bool) =
  var cx, cy, x2, y2: float32
  let x1 = cpx
  let y1 = cpy
  if rel:
    cx = cpx + args[0]; cy = cpy + args[1]
    x2 = cpx + args[2]; y2 = cpy + args[3]
  else:
    cx = args[0]; cy = args[1]
    x2 = args[2]; y2 = args[3]
  let cx1 = x1 + 2.0'f32/3.0'f32*(cx - x1)
  let cy1 = y1 + 2.0'f32/3.0'f32*(cy - y1)
  let cx2 = x2 + 2.0'f32/3.0'f32*(cx - x2)
  let cy2 = y2 + 2.0'f32/3.0'f32*(cy - y2)
  p.cubicBezTo(cx1, cy1, cx2, cy2, x2, y2)
  cpx2 = cx; cpy2 = cy
  cpx = x2; cpy = y2

proc pathQuadBezShortTo(p: NSVGparser, cpx, cpy, cpx2, cpy2: var float32,
                        args: openArray[float32], rel: bool) =
  var x2, y2: float32
  let x1 = cpx
  let y1 = cpy
  if rel:
    x2 = cpx + args[0]; y2 = cpy + args[1]
  else:
    x2 = args[0]; y2 = args[1]
  let cx = 2*x1 - cpx2
  let cy = 2*y1 - cpy2
  let cx1 = x1 + 2.0'f32/3.0'f32*(cx - x1)
  let cy1 = y1 + 2.0'f32/3.0'f32*(cy - y1)
  let cx2 = x2 + 2.0'f32/3.0'f32*(cx - x2)
  let cy2 = y2 + 2.0'f32/3.0'f32*(cy - y2)
  p.cubicBezTo(cx1, cy1, cx2, cy2, x2, y2)
  cpx2 = cx; cpy2 = cy
  cpx = x2; cpy = y2

func sqr(x: float32): float32 = x*x
func vmag(x, y: float32): float32 = sqrt(x*x + y*y)
func vecrat(ux, uy, vx, vy: float32): float32 =
  (ux*vx + uy*vy) / (vmag(ux, uy) * vmag(vx, vy))
func vecang(ux, uy, vx, vy: float32): float32 =
  var r = vecrat(ux, uy, vx, vy)
  if r < -1.0'f32: r = -1.0'f32
  if r > 1.0'f32: r = 1.0'f32
  (if ux*vy < uy*vx: -1.0'f32 else: 1.0'f32) * arccos(r)

proc pathArcTo(p: NSVGparser, cpx, cpy: var float32, args: openArray[float32], rel: bool) =
  # Ported from canvg
  var rx = abs(args[0])
  var ry = abs(args[1])
  let rotx = args[2] / 180.0'f32 * NSVG_PI
  let fa = abs(args[3]) > 1e-6
  let fs = abs(args[4]) > 1e-6
  let x1 = cpx
  let y1 = cpy
  var x2, y2: float32
  if rel:
    x2 = cpx + args[5]; y2 = cpy + args[6]
  else:
    x2 = args[5]; y2 = args[6]
  var dx = x1 - x2
  var dy = y1 - y2
  var d = sqrt(dx*dx + dy*dy)
  if d < 1e-6'f32 or rx < 1e-6'f32 or ry < 1e-6'f32:
    p.lineTo(x2, y2)
    cpx = x2; cpy = y2
    return
  let sinrx = sin(rotx)
  let cosrx = cos(rotx)
  let x1p = cosrx * dx / 2.0'f32 + sinrx * dy / 2.0'f32
  let y1p = -sinrx * dx / 2.0'f32 + cosrx * dy / 2.0'f32
  d = sqr(x1p)/sqr(rx) + sqr(y1p)/sqr(ry)
  if d > 1:
    d = sqrt(d)
    rx *= d
    ry *= d
  var s = 0.0'f32
  var sa = sqr(rx)*sqr(ry) - sqr(rx)*sqr(y1p) - sqr(ry)*sqr(x1p)
  let sb = sqr(rx)*sqr(y1p) + sqr(ry)*sqr(x1p)
  if sa < 0: sa = 0
  if sb > 0: s = sqrt(sa / sb)
  if fa == fs: s = -s
  let cxp = s * rx * y1p / ry
  let cyp = s * -ry * x1p / rx
  let cx = (x1 + x2)/2.0'f32 + cosrx*cxp - sinrx*cyp
  let cy = (y1 + y2)/2.0'f32 + sinrx*cxp + cosrx*cyp
  let ux = (x1p - cxp) / rx
  let uy = (y1p - cyp) / ry
  let vx = (-x1p - cxp) / rx
  let vy = (-y1p - cyp) / ry
  let a1 = vecang(1.0'f32, 0.0'f32, ux, uy)
  var da = vecang(ux, uy, vx, vy)
  if not fs and da > 0: da -= 2 * NSVG_PI
  elif fs and da < 0: da += 2 * NSVG_PI
  let t: Xform = [cosrx, sinrx, -sinrx, cosrx, cx, cy]
  let ndivs = int(abs(da) / (NSVG_PI*0.5'f32) + 1.0'f32)
  var hda = (da / float32(ndivs)) / 2.0'f32
  if hda < 1e-3'f32 and hda > -1e-3'f32: hda *= 0.5'f32
  else: hda = (1.0'f32 - cos(hda)) / sin(hda)
  var kappa = abs(4.0'f32 / 3.0'f32 * hda)
  if da < 0: kappa = -kappa
  var px, py, ptanx, ptany: float32
  for i in 0 .. ndivs:
    let a = a1 + da * (float32(i)/float32(ndivs))
    dx = cos(a)
    dy = sin(a)
    var x, y, tanx, tany: float32
    xformPoint(x, y, dx*rx, dy*ry, t)
    # xformVec
    tanx = (-dy*rx * kappa) * t[0] + (dx*ry * kappa) * t[2]
    tany = (-dy*rx * kappa) * t[1] + (dx*ry * kappa) * t[3]
    if i > 0:
      p.cubicBezTo(px + ptanx, py + ptany, x - tanx, y - tany, x, y)
    px = x; py = y
    ptanx = tanx; ptany = tany
  cpx = x2
  cpy = y2

proc parsePath(p: NSVGparser, attr: Attrs) =
  var d = ""
  var hasD = false
  for (n, v) in attr:
    if n == "d":
      d = v
      hasD = true
    else:
      p.parseAttribs(@[(n, v)])
  if hasD:
    p.resetPath()
    var cmd = '\0'
    var args: array[10, float32]
    var nargs = 0
    var rargs = 0
    var initPoint = false
    var cpx, cpy, cpx2, cpy2: float32
    var closedFlag = false
    var i = 0
    while i < d.len:
      var item = ""
      if (cmd == 'A' or cmd == 'a') and (nargs == 3 or nargs == 4):
        item = getNextPathItemWhenArcFlag(d, i)
      if item.len == 0:
        item = getNextPathItem(d, i)
      if item.len == 0: break
      if cmd != '\0' and isCoordinate(item):
        if nargs < 10:
          args[nargs] = float32(nsvgAtof(item))
          inc nargs
        if nargs >= rargs:
          case cmd
          of 'm', 'M':
            p.pathMoveTo(cpx, cpy, args, cmd == 'm')
            cmd = if cmd == 'm': 'l' else: 'L'
            rargs = getArgsPerElement(cmd)
            cpx2 = cpx; cpy2 = cpy
            initPoint = true
          of 'l', 'L':
            p.pathLineTo(cpx, cpy, args, cmd == 'l')
            cpx2 = cpx; cpy2 = cpy
          of 'H', 'h':
            p.pathHLineTo(cpx, cpy, args, cmd == 'h')
            cpx2 = cpx; cpy2 = cpy
          of 'V', 'v':
            p.pathVLineTo(cpx, cpy, args, cmd == 'v')
            cpx2 = cpx; cpy2 = cpy
          of 'C', 'c': p.pathCubicBezTo(cpx, cpy, cpx2, cpy2, args, cmd == 'c')
          of 'S', 's': p.pathCubicBezShortTo(cpx, cpy, cpx2, cpy2, args, cmd == 's')
          of 'Q', 'q': p.pathQuadBezTo(cpx, cpy, cpx2, cpy2, args, cmd == 'q')
          of 'T', 't': p.pathQuadBezShortTo(cpx, cpy, cpx2, cpy2, args, cmd == 't')
          of 'A', 'a':
            p.pathArcTo(cpx, cpy, args, cmd == 'a')
            cpx2 = cpx; cpy2 = cpy
          else:
            if nargs >= 2:
              cpx = args[nargs-2]
              cpy = args[nargs-1]
              cpx2 = cpx; cpy2 = cpy
          nargs = 0
      else:
        cmd = item[0]
        if cmd == 'M' or cmd == 'm':
          if p.npts > 0: p.addPath(closedFlag)
          p.resetPath()
          closedFlag = false
          nargs = 0
        elif not initPoint:
          cmd = '\0'
        if cmd == 'Z' or cmd == 'z':
          closedFlag = true
          if p.npts > 0:
            cpx = p.pts[0]
            cpy = p.pts[1]
            cpx2 = cpx; cpy2 = cpy
            p.addPath(closedFlag)
          p.resetPath()
          p.moveTo(cpx, cpy)
          closedFlag = false
          nargs = 0
        rargs = getArgsPerElement(cmd)
        if rargs == -1:
          cmd = '\0'
          rargs = 0
    if p.npts > 0: p.addPath(closedFlag)
  p.addShape()

# ---------------------------------------------------------------------------
# Basic shapes

proc parseRect(p: NSVGparser, attr: Attrs) =
  var x, y, w, h = 0'f32
  var rx = -1'f32
  var ry = -1'f32
  for (n, v) in attr:
    if not p.parseAttr(n, v):
      case n
      of "x": x = p.parseCoordinate(v, p.viewMinx, p.viewWidth)
      of "y": y = p.parseCoordinate(v, p.viewMiny, p.viewHeight)
      of "width": w = p.parseCoordinate(v, 0, p.viewWidth)
      of "height": h = p.parseCoordinate(v, 0, p.viewHeight)
      of "rx": rx = abs(p.parseCoordinate(v, 0, p.viewWidth))
      of "ry": ry = abs(p.parseCoordinate(v, 0, p.viewHeight))
      else: discard
  if rx < 0 and ry > 0: rx = ry
  if ry < 0 and rx > 0: ry = rx
  if rx < 0: rx = 0
  if ry < 0: ry = 0
  if rx > w/2.0'f32: rx = w/2.0'f32
  if ry > h/2.0'f32: ry = h/2.0'f32
  if w != 0 and h != 0:
    p.resetPath()
    if rx < 0.00001'f32 or ry < 0.0001'f32:
      p.moveTo(x, y)
      p.lineTo(x+w, y)
      p.lineTo(x+w, y+h)
      p.lineTo(x, y+h)
    else:
      let k = 1 - NSVG_KAPPA90
      p.moveTo(x+rx, y)
      p.lineTo(x+w-rx, y)
      p.cubicBezTo(x+w-rx*k, y, x+w, y+ry*k, x+w, y+ry)
      p.lineTo(x+w, y+h-ry)
      p.cubicBezTo(x+w, y+h-ry*k, x+w-rx*k, y+h, x+w-rx, y+h)
      p.lineTo(x+rx, y+h)
      p.cubicBezTo(x+rx*k, y+h, x, y+h-ry*k, x, y+h-ry)
      p.lineTo(x, y+ry)
      p.cubicBezTo(x, y+ry*k, x+rx*k, y, x+rx, y)
    p.addPath(true)
    p.addShape()

proc ellipsePath(p: NSVGparser, cx, cy, rx, ry: float32) =
  p.resetPath()
  p.moveTo(cx+rx, cy)
  p.cubicBezTo(cx+rx, cy+ry*NSVG_KAPPA90, cx+rx*NSVG_KAPPA90, cy+ry, cx, cy+ry)
  p.cubicBezTo(cx-rx*NSVG_KAPPA90, cy+ry, cx-rx, cy+ry*NSVG_KAPPA90, cx-rx, cy)
  p.cubicBezTo(cx-rx, cy-ry*NSVG_KAPPA90, cx-rx*NSVG_KAPPA90, cy-ry, cx, cy-ry)
  p.cubicBezTo(cx+rx*NSVG_KAPPA90, cy-ry, cx+rx, cy-ry*NSVG_KAPPA90, cx+rx, cy)
  p.addPath(true)
  p.addShape()

proc parseCircle(p: NSVGparser, attr: Attrs) =
  var cx, cy, r = 0'f32
  for (n, v) in attr:
    if not p.parseAttr(n, v):
      case n
      of "cx": cx = p.parseCoordinate(v, p.viewMinx, p.viewWidth)
      of "cy": cy = p.parseCoordinate(v, p.viewMiny, p.viewHeight)
      of "r": r = abs(p.parseCoordinate(v, 0, p.actualLength))
      else: discard
  if r > 0: p.ellipsePath(cx, cy, r, r)

proc parseEllipse(p: NSVGparser, attr: Attrs) =
  var cx, cy, rx, ry = 0'f32
  for (n, v) in attr:
    if not p.parseAttr(n, v):
      case n
      of "cx": cx = p.parseCoordinate(v, p.viewMinx, p.viewWidth)
      of "cy": cy = p.parseCoordinate(v, p.viewMiny, p.viewHeight)
      of "rx": rx = abs(p.parseCoordinate(v, 0, p.viewWidth))
      of "ry": ry = abs(p.parseCoordinate(v, 0, p.viewHeight))
      else: discard
  if rx > 0 and ry > 0: p.ellipsePath(cx, cy, rx, ry)

proc parseLine(p: NSVGparser, attr: Attrs) =
  var x1, y1, x2, y2 = 0'f32
  for (n, v) in attr:
    if not p.parseAttr(n, v):
      case n
      of "x1": x1 = p.parseCoordinate(v, p.viewMinx, p.viewWidth)
      of "y1": y1 = p.parseCoordinate(v, p.viewMiny, p.viewHeight)
      of "x2": x2 = p.parseCoordinate(v, p.viewMinx, p.viewWidth)
      of "y2": y2 = p.parseCoordinate(v, p.viewMiny, p.viewHeight)
      else: discard
  p.resetPath()
  p.moveTo(x1, y1)
  p.lineTo(x2, y2)
  p.addPath(false)
  p.addShape()

proc parsePoly(p: NSVGparser, attr: Attrs, closeFlag: bool) =
  p.resetPath()
  var npoints = 0
  for (n, v) in attr:
    if not p.parseAttr(n, v) and n == "points":
      var i = 0
      var args: array[2, float32]
      var nargs = 0
      while i < v.len:
        let item = getNextPathItem(v, i)
        args[nargs] = float32(nsvgAtof(item))
        inc nargs
        if nargs >= 2:
          if npoints == 0: p.moveTo(args[0], args[1])
          else: p.lineTo(args[0], args[1])
          nargs = 0
          inc npoints
  p.addPath(closeFlag)
  p.addShape()

proc parseSVG(p: NSVGparser, attr: Attrs) =
  for (n, v) in attr:
    if not p.parseAttr(n, v):
      case n
      of "width": p.image.width = p.parseCoordinate(v, 0, 0)
      of "height": p.image.height = p.parseCoordinate(v, 0, 0)
      of "viewBox":
        var i = 0
        template skip() =
          while v.at(i) != '\0' and (isSpace(v.at(i)) or v.at(i) == '%' or v.at(i) == ','):
            inc i
        p.viewMinx = float32(nsvgAtof(parseNumber(v, i, 64)))
        skip()
        if i >= v.len: return
        p.viewMiny = float32(nsvgAtof(parseNumber(v, i, 64)))
        skip()
        if i >= v.len: return
        p.viewWidth = float32(nsvgAtof(parseNumber(v, i, 64)))
        skip()
        if i >= v.len: return
        p.viewHeight = float32(nsvgAtof(parseNumber(v, i, 64)))
      of "preserveAspectRatio":
        if "none" in v:
          p.alignType = ALIGN_NONE
        else:
          if "xMin" in v: p.alignX = ALIGN_MIN
          elif "xMid" in v: p.alignX = ALIGN_MID
          elif "xMax" in v: p.alignX = ALIGN_MAX
          if "yMin" in v: p.alignY = ALIGN_MIN
          elif "yMid" in v: p.alignY = ALIGN_MID
          elif "yMax" in v: p.alignY = ALIGN_MAX
          p.alignType = ALIGN_MEET
          if "slice" in v: p.alignType = ALIGN_SLICE
      else: discard

# ---------------------------------------------------------------------------
# Gradients

proc parseGradient(p: NSVGparser, attr: Attrs, kind: NSVGpaintType) =
  let grad = NSVGgradientData(objectSpace: true, kind: kind)
  if kind == nsvgPaintLinearGradient:
    grad.x1 = coord(0, UNITS_PERCENT)
    grad.y1 = coord(0, UNITS_PERCENT)
    grad.x2 = coord(100, UNITS_PERCENT)
    grad.y2 = coord(0, UNITS_PERCENT)
  elif kind == nsvgPaintRadialGradient:
    grad.cx = coord(50, UNITS_PERCENT)
    grad.cy = coord(50, UNITS_PERCENT)
    grad.r = coord(50, UNITS_PERCENT)
  xformIdentity(grad.xform)
  for (n, v) in attr:
    if n == "id":
      grad.id = truncTo(v, 63)
    elif not p.parseAttr(n, v):
      case n
      of "gradientUnits": grad.objectSpace = (v == "objectBoundingBox")
      of "gradientTransform": parseTransform(grad.xform, v)
      of "cx": grad.cx = parseCoordinateRaw(v)
      of "cy": grad.cy = parseCoordinateRaw(v)
      of "r": grad.r = parseCoordinateRaw(v)
      of "fx": grad.fx = parseCoordinateRaw(v)
      of "fy": grad.fy = parseCoordinateRaw(v)
      of "x1": grad.x1 = parseCoordinateRaw(v)
      of "y1": grad.y1 = parseCoordinateRaw(v)
      of "x2": grad.x2 = parseCoordinateRaw(v)
      of "y2": grad.y2 = parseCoordinateRaw(v)
      of "spreadMethod":
        case v
        of "pad": grad.spread = nsvgSpreadPad
        of "reflect": grad.spread = nsvgSpreadReflect
        of "repeat": grad.spread = nsvgSpreadRepeat
        else: discard
      of "xlink:href":
        grad.href = if v.len > 1: truncTo(v[1 .. ^1], 62) else: ""
      else: discard
  p.gradients.add grad

proc parseGradientStop(p: NSVGparser, attr: Attrs) =
  template cur: untyped = p.getAttr
  cur.stopOffset = 0
  cur.stopColor = 0
  cur.stopOpacity = 1.0'f32
  for (n, v) in attr: discard p.parseAttr(n, v)
  if p.gradients.len == 0: return
  let grad = p.gradients[^1]
  var idx = grad.stops.len
  for i in 0 ..< grad.stops.len:
    if cur.stopOffset < grad.stops[i].offset:
      idx = i
      break
  grad.stops.insert(NSVGgradientStop(
    color: cur.stopColor or (uint32(cur.stopOpacity * 255) shl 24),
    offset: cur.stopOffset), idx)

# ---------------------------------------------------------------------------
# XML

proc startElement(p: NSVGparser, el: string, attr: Attrs) =
  if p.defsFlag:
    # Skip everything but gradients and styles in defs
    case el
    of "linearGradient": p.parseGradient(attr, nsvgPaintLinearGradient)
    of "radialGradient": p.parseGradient(attr, nsvgPaintRadialGradient)
    of "stop": p.parseGradientStop(attr)
    of "style": p.styleFlag = true
    else: discard
    return
  case el
  of "g":
    p.pushAttr()
    p.parseAttribs(attr)
  of "path":
    if p.pathFlag: return
    p.pushAttr(); p.parsePath(attr); p.popAttr()
  of "rect":
    p.pushAttr(); p.parseRect(attr); p.popAttr()
  of "circle":
    p.pushAttr(); p.parseCircle(attr); p.popAttr()
  of "ellipse":
    p.pushAttr(); p.parseEllipse(attr); p.popAttr()
  of "line":
    p.pushAttr(); p.parseLine(attr); p.popAttr()
  of "polyline":
    p.pushAttr(); p.parsePoly(attr, false); p.popAttr()
  of "polygon":
    p.pushAttr(); p.parsePoly(attr, true); p.popAttr()
  of "linearGradient": p.parseGradient(attr, nsvgPaintLinearGradient)
  of "radialGradient": p.parseGradient(attr, nsvgPaintRadialGradient)
  of "stop": p.parseGradientStop(attr)
  of "defs": p.defsFlag = true
  of "svg": p.parseSVG(attr)
  of "style": p.styleFlag = true
  else: discard

proc endElement(p: NSVGparser, el: string) =
  case el
  of "g": p.popAttr()
  of "path": p.pathFlag = false
  of "defs": p.defsFlag = false
  of "style": p.styleFlag = false
  else: discard

proc content(p: NSVGparser, s: string) =
  if not p.styleFlag: return
  # Only selector lists of simple class selectors (".foo, .bar { ... }").
  var i = 0
  while i < s.len:
    var staged: seq[string]
    while i < s.len and s[i] != '{':
      while i < s.len and (isSpace(s[i]) or s[i] == ','): inc i
      if i >= s.len or s[i] == '{': break
      let selStart = i
      while i < s.len and not isSpace(s[i]) and s[i] != ',' and s[i] != '{': inc i
      if s[selStart] != '.' or staged.len >= NSVG_MAX_CLASSES: continue
      staged.add s[selStart + 1 ..< i]
    if i >= s.len: break
    inc i  # past '{'
    let propsStart = i
    while i < s.len and s[i] != '}': inc i
    let props = s[propsStart ..< i]
    for cls in staged:
      p.styles.add NSVGstyleDeclaration(className: cls, propertiesText: props)
    if i < s.len: inc i

proc parseElement(p: NSVGparser, s: string) =
  var i = 0
  var isStart = false
  var isEnd = false
  while isSpace(s.at(i)): inc i
  if s.at(i) == '/':
    inc i
    isEnd = true
  else:
    isStart = true
  if i >= s.len or s[i] == '?' or s[i] == '!': return
  let nameStart = i
  while i < s.len and not isSpace(s[i]): inc i
  let name = s[nameStart ..< i]
  if i < s.len: inc i
  var attrs: Attrs
  var nattr = 0
  while not isEnd and i < s.len and nattr < NSVG_XML_MAX_ATTRIBS - 3:
    while isSpace(s.at(i)): inc i
    if i >= s.len: break
    if s[i] == '/':
      isEnd = true
      break
    let an = i
    while i < s.len and not isSpace(s[i]) and s[i] != '=': inc i
    let aname = s[an ..< i]
    if i < s.len: inc i
    while i < s.len and s[i] != '"' and s[i] != '\'': inc i
    if i >= s.len: break
    let quote = s[i]
    inc i
    let vs = i
    while i < s.len and s[i] != quote: inc i
    let value = s[vs ..< i]
    if i < s.len: inc i
    attrs.add (aname, value)
    nattr += 2
  if isStart: p.startElement(name, attrs)
  if isEnd: p.endElement(name)

proc parseXML(p: NSVGparser, input: string) =
  var i = 0
  var mark = 0
  var inTag = false
  while i < input.len:
    let c = input[i]
    if c == '<' and not inTag:
      var j = mark
      while j < i and isSpace(input[j]): inc j
      if j < i: p.content(input[j ..< i])
      mark = i + 1
      inTag = true
    elif c == '>' and inTag:
      p.parseElement(input[mark ..< i])
      mark = i + 1
      inTag = false
    inc i

# ---------------------------------------------------------------------------
# Post processing

proc imageBounds(p: NSVGparser, bounds: var array[4, float32]) =
  if p.image.shapes.len == 0:
    bounds = [0'f32, 0, 0, 0]
    return
  bounds = p.image.shapes[0].bounds
  for k in 1 ..< p.image.shapes.len:
    let b = p.image.shapes[k].bounds
    bounds[0] = minf(bounds[0], b[0])
    bounds[1] = minf(bounds[1], b[1])
    bounds[2] = maxf(bounds[2], b[2])
    bounds[3] = maxf(bounds[3], b[3])

func viewAlign(content, container: float32, typ: int): float32 =
  if typ == ALIGN_MIN: 0
  elif typ == ALIGN_MAX: container - content
  else: (container - content) * 0.5'f32

proc scaleGradient(grad: NSVGgradient, tx, ty, sx, sy: float32) =
  var t: Xform
  xformSetTranslation(t, tx, ty)
  xformMultiply(grad.xform, t)
  xformSetScale(t, sx, sy)
  xformMultiply(grad.xform, t)

func isGradient(k: NSVGpaintType): bool =
  k == nsvgPaintLinearGradient or k == nsvgPaintRadialGradient

proc scaleToViewbox(p: NSVGparser, units: string) =
  var bounds: array[4, float32]
  p.imageBounds(bounds)
  let img = p.image
  if p.viewWidth == 0:
    if img.width > 0: p.viewWidth = img.width
    else:
      p.viewMinx = bounds[0]
      p.viewWidth = bounds[2] - bounds[0]
  if p.viewHeight == 0:
    if img.height > 0: p.viewHeight = img.height
    else:
      p.viewMiny = bounds[1]
      p.viewHeight = bounds[3] - bounds[1]
  if img.width == 0: img.width = p.viewWidth
  if img.height == 0: img.height = p.viewHeight
  var tx = -p.viewMinx
  var ty = -p.viewMiny
  var sx = if p.viewWidth > 0: img.width / p.viewWidth else: 0'f32
  var sy = if p.viewHeight > 0: img.height / p.viewHeight else: 0'f32
  let us = 1.0'f32 / p.convertToPixels(coord(1.0'f32, parseUnits(units)), 0, 1)
  if p.alignType == ALIGN_MEET:
    sx = minf(sx, sy); sy = sx
    tx += viewAlign(p.viewWidth*sx, img.width, p.alignX) / sx
    ty += viewAlign(p.viewHeight*sy, img.height, p.alignY) / sy
  elif p.alignType == ALIGN_SLICE:
    sx = maxf(sx, sy); sy = sx
    tx += viewAlign(p.viewWidth*sx, img.width, p.alignX) / sx
    ty += viewAlign(p.viewHeight*sy, img.height, p.alignY) / sy
  sx *= us
  sy *= us
  let avgs = (sx + sy) / 2.0'f32
  for shape in img.shapes.mitems:
    shape.bounds[0] = (shape.bounds[0] + tx) * sx
    shape.bounds[1] = (shape.bounds[1] + ty) * sy
    shape.bounds[2] = (shape.bounds[2] + tx) * sx
    shape.bounds[3] = (shape.bounds[3] + ty) * sy
    for path in shape.paths.mitems:
      path.bounds[0] = (path.bounds[0] + tx) * sx
      path.bounds[1] = (path.bounds[1] + ty) * sy
      path.bounds[2] = (path.bounds[2] + tx) * sx
      path.bounds[3] = (path.bounds[3] + ty) * sy
      for i in 0 ..< path.npts:
        path.pts[i*2] = (path.pts[i*2] + tx) * sx
        path.pts[i*2+1] = (path.pts[i*2+1] + ty) * sy
    for paint in [addr shape.fill, addr shape.stroke]:
      if paint.kind.isGradient:
        scaleGradient(paint.gradient, tx, ty, sx, sy)
        var t = paint.gradient.xform
        xformInverse(paint.gradient.xform, t)
    shape.strokeWidth *= avgs
    shape.strokeDashOffset *= avgs
    for i in 0 ..< shape.strokeDashCount:
      shape.strokeDashArray[i] *= avgs

proc createGradients(p: NSVGparser) =
  for shape in p.image.shapes.mitems:
    for which in 0 .. 1:
      let paint = if which == 0: addr shape.fill else: addr shape.stroke
      if paint.kind == nsvgPaintUndef:
        let gname = if which == 0: shape.fillGradient else: shape.strokeGradient
        if gname.len > 0:
          var inv: Xform
          xformIdentity(inv)
          var lb: array[4, float32]
          xformInverse(inv, shape.xform)
          getLocalBounds(lb, shape, inv)
          let grad = p.createGradient(gname, lb, shape.xform)
          if grad != nil:
            paint.gradient = grad
            paint.kind = p.findGradientData(gname).kind
        if paint.kind == nsvgPaintUndef:
          paint.kind = nsvgPaintNone

# ---------------------------------------------------------------------------
# Public API

proc nsvgParse*(input: string, units = "px", dpi = 96.0'f32): NSVGimage =
  ## Parses SVG text. `units` is the output unit ("px","pt","pc","mm","cm","in")
  ## and `dpi` the dots-per-inch used for unit conversion.
  var text = input
  let nul = text.find('\0')
  if nul >= 0: text.setLen(nul)
  let p = createParser()
  p.dpi = dpi
  p.parseXML(text)
  p.createGradients()
  p.scaleToViewbox(units)
  result = p.image

proc nsvgParseFromFile*(filename: string, units = "px", dpi = 96.0'f32): NSVGimage =
  ## Returns nil when the file cannot be read.
  var data: string
  try:
    data = readFile(filename)
  except IOError:
    return nil
  nsvgParse(data, units, dpi)

proc nsvgDuplicatePath*(p: NSVGpath): NSVGpath = p
  ## Deep copy of a path (Nim value semantics already guarantee this).

proc nsvgDelete*(image: NSVGimage) = discard
  ## No-op: memory is garbage collected. Kept for API parity.
