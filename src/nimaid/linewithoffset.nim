import std/math
import geom

type
  DeltaAngle* = object
    angle*: float
    deltaX*: float
    deltaY*: float

proc getMarkerOffsetVal*(markerType: string): float =
  case markerType
  of "aggregation", "extension", "composition": 17.25
  of "lollipop": 13.0
  of "er_one": 12.0
  of "er_zero_one", "er_many": 20.0
  of "er_zero_many": 28.0
  of "arrow_cross", "arrow_circle": 8.0
  of "arrow_hollow_circle": 8.0
  of "dependency": 6.0
  of "arrow_barb_neo": 5.5
  of "arrow_point", "arrow_open_head": 4.0
  of "arrow_barb": 0.0
  else: 0.0

proc calculateDeltaAndAngle*(p1, p2: Point): DeltaAngle =
  let dx = p2.x - p1.x
  let dy = p2.y - p1.y
  result.deltaX = dx
  result.deltaY = dy
  if dx == 0.0 and dy == 0.0:
    result.angle = 0.0
  else:
    result.angle = arctan2(dy, dx)

proc applyPreciseMarkerOffsets*(points: seq[Point], arrowStart, arrowEnd: string): seq[Point] =
  result = points
  let count = result.len
  if count < 2:
    return

  let startOffset = getMarkerOffsetVal(arrowStart)
  let endOffset = getMarkerOffsetVal(arrowEnd)

  if startOffset > 0.0:
    let da = calculateDeltaAndAngle(result[0], result[1])
    let ox = startOffset * cos(da.angle)
    let oy = startOffset * sin(da.angle)
    let diffX = abs(result[1].x - result[0].x)
    let diffY = abs(result[1].y - result[0].y)
    if diffX > abs(ox) or diffY > abs(oy):
      result[0] = Point(x: result[0].x + ox, y: result[0].y + oy)

  if endOffset > 0.0:
    let da = calculateDeltaAndAngle(result[count - 1], result[count - 2])
    let ox = endOffset * cos(da.angle)
    let oy = endOffset * sin(da.angle)
    let diffX = abs(result[count - 2].x - result[count - 1].x)
    let diffY = abs(result[count - 2].y - result[count - 1].y)
    if diffX > abs(ox) or diffY > abs(oy):
      result[count - 1] = Point(x: result[count - 1].x + ox, y: result[count - 1].y + oy)
