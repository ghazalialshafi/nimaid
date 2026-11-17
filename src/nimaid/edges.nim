import std/[math, strutils, tables]
import types, geom

type
  PathCommandKind* = enum
    pckMove,
    pckLine,
    pckCubic

  PathCommand* = object
    kind*: PathCommandKind
    p1*, p2*, p3*: Point

  MarkerKind* = enum
    mkNone,
    mkPoint,
    mkCircle,
    mkCross,
    mkBarb,
    mkOpenArrow,
    mkHollowCircle,
    mkAggregation,
    mkExtension,
    mkComposition,
    mkDependency,
    mkLollipop,
    mkErOne,
    mkErZeroOne,
    mkErMany,
    mkErZeroMany

  MarkerShape* = object
    kind*: MarkerKind
    fill*: bool
    points*: seq[Point]
    circleCenter*: Point
    circleRadius*: float
    lines*: seq[tuple[p1, p2: Point]]

proc parseMarkerKind*(arrowType: string): MarkerKind =
  case arrowType
  of "arrow_point", "point": mkPoint
  of "arrow_circle", "circle": mkCircle
  of "arrow_cross", "cross": mkCross
  of "arrow_barb", "arrow_barb_neo", "barb": mkBarb
  of "arrow_open_head", "openArrow": mkOpenArrow
  of "arrow_hollow_circle", "hollowCircle": mkHollowCircle
  of "aggregation": mkAggregation
  of "extension": mkExtension
  of "composition": mkComposition
  of "dependency": mkDependency
  of "lollipop": mkLollipop
  of "er_one": mkErOne
  of "er_zero_one": mkErZeroOne
  of "er_many": mkErMany
  of "er_zero_many": mkErZeroMany
  else: mkNone

proc getMarkerOffset*(marker: MarkerKind): float =
  case marker
  of mkPoint: 5.0
  of mkCircle, mkHollowCircle: 5.0
  of mkCross: 4.0
  of mkBarb: 6.0
  of mkOpenArrow: 5.0
  of mkAggregation, mkExtension: 10.0
  of mkLollipop: 13.0
  of mkErOne: 12.0
  of mkErZeroOne, mkErMany: 20.0
  of mkErZeroMany: 28.0
  of mkComposition, mkDependency: 10.0
  of mkNone: 0.0

proc getMarkerOffset*(arrowType: string): float =
  getMarkerOffset(parseMarkerKind(arrowType))

proc getMarkerShape*(marker: MarkerKind): MarkerShape =
  result.kind = marker
  case marker
  of mkPoint:
    result.fill = true
    result.points = @[Point(x: -8.0, y: -4.0), Point(x: 0.0, y: 0.0), Point(x: -8.0, y: 4.0)]
  of mkBarb, mkOpenArrow:
    result.fill = false
    result.lines = @[(Point(x: -8.0, y: -5.0), Point(x: 0.0, y: 0.0)), (Point(x: 0.0, y: 0.0), Point(x: -8.0, y: 5.0))]
  of mkCircle:
    result.fill = true
    result.circleCenter = Point(x: -4.0, y: 0.0)
    result.circleRadius = 3.5
  of mkHollowCircle:
    result.fill = false
    result.circleCenter = Point(x: -4.0, y: 0.0)
    result.circleRadius = 3.5
  of mkCross:
    result.fill = false
    result.lines = @[(Point(x: -8.0, y: -4.0), Point(x: 0.0, y: 4.0)), (Point(x: -8.0, y: 4.0), Point(x: 0.0, y: -4.0))]
  of mkExtension:
    result.fill = false
    result.points = @[Point(x: 0.0, y: 0.0), Point(x: -17.0, y: -8.0), Point(x: -17.0, y: 8.0)]
  of mkAggregation:
    result.fill = false
    result.points = @[Point(x: 0.0, y: 0.0), Point(x: -9.0, y: -5.5), Point(x: -18.0, y: 0.0), Point(x: -9.0, y: 5.5)]
  of mkComposition, mkDependency:
    result.fill = true
    result.points = @[Point(x: 0.0, y: 0.0), Point(x: -9.0, y: -5.5), Point(x: -18.0, y: 0.0), Point(x: -9.0, y: 5.5)]
  of mkLollipop:
    result.fill = false
    result.circleCenter = Point(x: -6.5, y: 0.0)
    result.circleRadius = 6.0
  of mkErOne:
    result.lines = @[(Point(x: -5.0, y: -7.0), Point(x: -5.0, y: 7.0)), (Point(x: -10.0, y: -7.0), Point(x: -10.0, y: 7.0))]
  of mkErZeroOne:
    result.lines = @[(Point(x: -5.0, y: -7.0), Point(x: -5.0, y: 7.0))]
    result.circleCenter = Point(x: -14.0, y: 0.0)
    result.circleRadius = 4.5
  of mkErMany, mkErZeroMany:
    result.lines = @[(Point(x: -15.0, y: 0.0), Point(x: 0.0, y: -7.0)), (Point(x: -15.0, y: 0.0), Point(x: 0.0, y: 0.0)),
                     (Point(x: -15.0, y: 0.0), Point(x: 0.0, y: 7.0))]
    if marker == mkErMany:
      result.lines.add (Point(x: -19.0, y: -7.0), Point(x: -19.0, y: 7.0))
    else:
      result.circleCenter = Point(x: -23.0, y: 0.0)
      result.circleRadius = 4.5
  of mkNone:
    discard

proc transformMarker*(shape: MarkerShape, anchor: Point, angle: float): MarkerShape =
  result = shape
  let cosA = cos(angle)
  let sinA = sin(angle)
  proc rotatePt(p: Point): Point =
    Point(x: anchor.x + p.x * cosA - p.y * sinA, y: anchor.y + p.x * sinA + p.y * cosA)
  for i in 0 ..< result.points.len:
    result.points[i] = rotatePt(result.points[i])
  for i in 0 ..< result.lines.len:
    result.lines[i] = (rotatePt(result.lines[i].p1), rotatePt(result.lines[i].p2))
  result.circleCenter = rotatePt(result.circleCenter)

proc applyMarkerOffsetsToPoints*(points: seq[Point], arrowStart, arrowEnd: string): seq[Point] =
  result = points
  let n = result.len
  if n < 2:
    return
  let startOffset = getMarkerOffset(arrowStart)
  if startOffset > 0.0:
    let dx = result[1].x - result[0].x
    let dy = result[1].y - result[0].y
    let angle = arctan2(dy, dx)
    result[0] = Point(x: result[0].x + startOffset * cos(angle), y: result[0].y + startOffset * sin(angle))
  let endOffset = getMarkerOffset(arrowEnd)
  if endOffset > 0.0:
    let dx = result[n - 1].x - result[n - 2].x
    let dy = result[n - 1].y - result[n - 2].y
    let angle = arctan2(dy, dx)
    result[n - 1] = Point(x: result[n - 1].x - endOffset * cos(angle), y: result[n - 1].y - endOffset * sin(angle))

proc generateRoundedPathCommands*(points: seq[Point], radius = 5.0): seq[PathCommand] =
  let size = points.len
  if size < 2:
    return
  result.add PathCommand(kind: pckMove, p1: points[0])
  if size == 2:
    result.add PathCommand(kind: pckLine, p1: points[1])
    return
  let epsilon = 1e-5
  for i in 1 ..< size - 1:
    let curr = points[i]
    let prev = points[i - 1]
    let next = points[i + 1]
    let dx1 = curr.x - prev.x
    let dy1 = curr.y - prev.y
    let dx2 = next.x - curr.x
    let dy2 = next.y - curr.y
    let len1 = hypot(dx1, dy1)
    let len2 = hypot(dx2, dy2)
    if len1 < epsilon or len2 < epsilon:
      result.add PathCommand(kind: pckLine, p1: curr)
      continue
    let nx1 = dx1 / len1
    let ny1 = dy1 / len1
    let nx2 = dx2 / len2
    let ny2 = dy2 / len2
    let dot = nx1 * nx2 + ny1 * ny2
    let clampedDot = max(-1.0, min(1.0, dot))
    let angle = arccos(clampedDot)
    if angle < epsilon or abs(PI - angle) < epsilon:
      result.add PathCommand(kind: pckLine, p1: curr)
      continue
    let cutLen = min(radius / sin(angle / 2.0), min(len1 / 2.0, len2 / 2.0))
    let startPt = Point(x: curr.x - nx1 * cutLen, y: curr.y - ny1 * cutLen)
    let endPt = Point(x: curr.x + nx2 * cutLen, y: curr.y + ny2 * cutLen)
    result.add PathCommand(kind: pckLine, p1: startPt)
    let c1 = Point(x: startPt.x + (2.0 / 3.0) * (curr.x - startPt.x), y: startPt.y + (2.0 / 3.0) * (curr.y - startPt.y))
    let c2 = Point(x: endPt.x + (2.0 / 3.0) * (curr.x - endPt.x), y: endPt.y + (2.0 / 3.0) * (curr.y - endPt.y))
    result.add PathCommand(kind: pckCubic, p1: c1, p2: c2, p3: endPt)
  result.add PathCommand(kind: pckLine, p1: points[^1])

proc generateRoundedPathSvg*(points: seq[Point], radius = 5.0): string =
  let size = points.len
  if size < 2:
    return ""
  result = "M " & $points[0].x & " " & $points[0].y
  if size == 2:
    return result & " L " & $points[1].x & " " & $points[1].y
  let epsilon = 1e-5
  for i in 1 ..< size - 1:
    let curr = points[i]
    let prev = points[i - 1]
    let next = points[i + 1]
    let dx1 = curr.x - prev.x
    let dy1 = curr.y - prev.y
    let dx2 = next.x - curr.x
    let dy2 = next.y - curr.y
    let len1 = hypot(dx1, dy1)
    let len2 = hypot(dx2, dy2)
    if len1 < epsilon or len2 < epsilon:
      result.add " L " & $curr.x & " " & $curr.y
      continue
    let nx1 = dx1 / len1
    let ny1 = dy1 / len1
    let nx2 = dx2 / len2
    let ny2 = dy2 / len2
    let dot = nx1 * nx2 + ny1 * ny2
    let clampedDot = max(-1.0, min(1.0, dot))
    let angle = arccos(clampedDot)
    if angle < epsilon or abs(PI - angle) < epsilon:
      result.add " L " & $curr.x & " " & $curr.y
      continue
    let cutLen = min(radius / sin(angle / 2.0), min(len1 / 2.0, len2 / 2.0))
    let startPt = Point(x: curr.x - nx1 * cutLen, y: curr.y - ny1 * cutLen)
    let endPt = Point(x: curr.x + nx2 * cutLen, y: curr.y + ny2 * cutLen)
    result.add " L " & $startPt.x & " " & $startPt.y
    result.add " Q " & $curr.x & " " & $curr.y & " " & $endPt.x & " " & $endPt.y
  result.add " L " & $points[^1].x & " " & $points[^1].y

proc calculatePolylineTotalLength*(points: seq[Point]): float =
  for i in 0 ..< points.len - 1:
    let dx = points[i + 1].x - points[i].x
    let dy = points[i + 1].y - points[i].y
    result += hypot(dx, dy)

proc resolveEdgeLabelPosition*(points: seq[Point]): Point =
  if points.len == 0:
    return Point(x: 0.0, y: 0.0)
  if points.len == 1:
    return points[0]
  let totalLen = calculatePolylineTotalLength(points)
  let halfLen = totalLen / 2.0
  var accum = 0.0
  for i in 0 ..< points.len - 1:
    let dx = points[i + 1].x - points[i].x
    let dy = points[i + 1].y - points[i].y
    let segLen = hypot(dx, dy)
    if accum + segLen >= halfLen:
      let rem = halfLen - accum
      let t = if segLen > 1e-6: rem / segLen else: 0.0
      return Point(x: points[i].x + t * dx, y: points[i].y + t * dy)
    accum += segLen
  points[^1]

proc getEdgeTerminalMarkers*(
  points: seq[Point],
  arrowStart, arrowEnd: string
): (bool, MarkerShape, bool, MarkerShape) =
  var hasStart = false
  var startShape: MarkerShape
  var hasEnd = false
  var endShape: MarkerShape
  let n = points.len
  if n >= 2:
    let mkS = parseMarkerKind(arrowStart)
    if mkS != mkNone:
      let angle = arctan2(points[0].y - points[1].y, points[0].x - points[1].x)
      startShape = transformMarker(getMarkerShape(mkS), points[0], angle)
      hasStart = true
    let mkE = parseMarkerKind(arrowEnd)
    if mkE != mkNone:
      let angle = arctan2(points[n - 1].y - points[n - 2].y, points[n - 1].x - points[n - 2].x)
      endShape = transformMarker(getMarkerShape(mkE), points[n - 1], angle)
      hasEnd = true
  (hasStart, startShape, hasEnd, endShape)
