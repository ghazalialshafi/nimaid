import std/[math, algorithm]
import dagre/graphlib
export graphlib.Point


# =============================================================================
# intersect-line.nim
# =============================================================================
# Based on Graphics Gems, No 2, J. Avro (ed.), p7 and p473.
# Avoids the integer division rounding bug by using floating-point arithmetic directly.

proc sameSign(r1, r2: float): bool =
  r1 * r2 > 0

proc intersectLine*(p1, p2, q1, q2: Point): Point =
  # Compute a1, b1, c1, where line joining points 1 and 2 is F(x,y) = a1 x + b1 y + c1 = 0.
  let a1 = p2.y - p1.y
  let b1 = p1.x - p2.x
  let c1 = p2.x * p1.y - p1.x * p2.y

  # Compute r3 and r4.
  let r3 = a1 * q1.x + b1 * q1.y + c1
  let r4 = a1 * q2.x + b1 * q2.y + c1

  # Epsilon for floating point comparisons
  let epsilon = 1e-9

  # Check signs of r3 and r4. If both point 3 and point 4 lie on
  # same side of line 1, the line segments do not intersect.
  if abs(r3) > epsilon and abs(r4) > epsilon and sameSign(r3, r4):
    return Point(x: NaN, y: NaN) # Indicate no intersection

  # Compute a2, b2, c2 where line joining points 3 and 4 is G(x,y) = a2 x + b2 y + c2 = 0
  let a2 = q2.y - q1.y
  let b2 = q1.x - q2.x
  let c2 = q2.x * q1.y - q1.x * q2.y

  # Compute r1 and r2
  let r1 = a2 * p1.x + b2 * p1.y + c2
  let r2 = a2 * p2.x + b2 * p2.y + c2

  # Check signs of r1 and r2. If both point 1 and point 2 lie
  # on same side of second line segment, the line segments do
  # not intersect.
  if abs(r1) < epsilon and abs(r2) < epsilon and sameSign(r1, r2):
    return Point(x: NaN, y: NaN) # Indicate no intersection

  # Line segments intersect: compute intersection point.
  let denom = a1 * b2 - a2 * b1
  if abs(denom) < epsilon:
    return Point(x: NaN, y: NaN) # Indicate collinearity or no intersection

  let x = (b1 * c2 - b2 * c1) / denom
  let y = (a2 * c1 - a1 * c2) / denom

  return Point(x: x, y: y)

# =============================================================================
# intersect-ellipse.nim
# =============================================================================
# Formulae from: https://mathworld.wolfram.com/Ellipse-LineIntersection.html
# This function handles both circles (rx=ry) and ellipses.

proc intersectEllipse*(node: tuple[x, y: float, width, height: float], rx, ry: float, point: Point): Point =
  let cx = node.x
  let cy = node.y

  let px = cx - point.x
  let py = cy - point.y

  # Handle degenerate cases
  if rx <= 0 or ry <= 0:
    return Point(x: NaN, y: NaN)

  let det = sqrt(rx * rx * py * py + ry * ry * px * px)

  # Avoid division by zero if the determinant is very small
  if abs(det) < 1e-9:
    return Point(x: NaN, y: NaN)

  var dx = (rx * ry * px) / det
  if point.x < cx:
    dx = -dx
  var dy = (rx * ry * py) / det
  if point.y < cy:
    dy = -dy

  return Point(x: cx + dx, y: cy + dy)

# =============================================================================
# intersect-circle.nim
# =============================================================================
proc intersectCircle*(node: tuple[x, y: float, width, height: float], point: Point): Point =
  # For a circle, rx = ry = min(width, height) / 2
  let radius = min(node.width, node.height) / 2.0
  if radius <= 0:
    return Point(x: NaN, y: NaN)
  return intersectEllipse(node, radius, radius, point)

# =============================================================================
# intersect-node.nim
# =============================================================================
# This function assumes 'node' has an 'intersect' procedure defined,
# which is true for shapes defined in Mermaid (like rect, circle, etc.).
# Your `dagre_nim`'s NodeLabel might need a similar `intersect` method or
# we can pass the shape information explicitly.
# For now, we'll pass the node object and rely on its shape properties.

proc intersectNode*(node: tuple[x, y: float, width, height: float], point: Point): Point =
  # This will need to be adapted based on how shapes are represented in your Nim `NodeLabel`
  # For simple rect/circle, the logic is direct. For complex polygons, it needs more.
  # If your NodeLabel has a `shape` field, you'd use that.
  # For now, assuming a simple rectangular node if no specific shape is known.
  # This placeholder assumes the node itself is a simple rect.
  # A more robust solution would check node.shape and call specific intersect functions.

  # Default to rect intersection if node shape isn't explicitly handled here
  # However, the original JS implies `node.intersect` is a pre-defined method on the node object.
  # Let's replicate intersectRect directly here as a fallback/example.
  # A proper implementation would require a `shape` enum in NodeLabel and a dispatch.

  # Replicating intersectRect logic here for demonstration:
  let x = node.x
  let y = node.y
  let dx = point.x - x
  let dy = point.y - y
  var w = node.width / 2.0
  var h = node.height / 2.0

  var sx, sy: float
  if abs(dy) * w > abs(dx) * h:
    if dy < 0: h = -h
    sx = if abs(dy) < 1e-9: 0.0 else: (h * dx) / dy
    sy = h
  else:
    if dx < 0: w = -w
    sx = w
    sy = if abs(dx) < 1e-9: 0.0 else: (w * dy) / dx

  return Point(x: x + sx, y: y + sy)

# =============================================================================
# intersect-polygon.nim
# =============================================================================
# Handles intersection with arbitrary polygons. Relies on intersectLine.

proc intersectPolygon*(node: tuple[x, y: float, width, height: float], polyPoints: seq[Point], point: Point): Point =
  let x1 = node.x
  let y1 = node.y

  var intersections = newSeq[Point]()

  var minX = 1e18 # Use a large number for initial min/max
  var minY = 1e18

  # Find the minimum x and y of the polygon points to correctly offset them relative to the node center
  for p in polyPoints:
    minX = min(minX, p.x)
    minY = min(minY, p.y)

  let left = x1 - node.width / 2.0 - minX
  let top = y1 - node.height / 2.0 - minY

  # Check intersection with each edge of the polygon
  for i in 0 ..< polyPoints.len:
    let p1 = polyPoints[i]
    let p2 = polyPoints[if i < polyPoints.len - 1: i + 1 else: 0] # Wrap around for the last edge

    let polyP1 = Point(x: left + p1.x, y: top + p1.y)
    let polyP2 = Point(x: left + p2.x, y: top + p2.y)

    let intersectPt = intersectLine(Point(x: x1, y: y1), point, polyP1, polyP2)

    if not (isNaN(intersectPt.x) or isNaN(intersectPt.y)):
      intersections.add(intersectPt)

  if intersections.len == 0:
    # No intersection found, return the node center itself (or point, depending on desired behavior)
    # The original JS returned `node`, which implies the node center.
    return Point(x: x1, y: y1)
  elif intersections.len > 1:
    # Sort intersections by distance to the 'point' (the edge endpoint)
    intersections.sort(proc(a, b: Point): int =
      let pdx = a.x - point.x
      let pdy = a.y - point.y
      let distp = sqrt(pdx * pdx + pdy * pdy)

      let qdx = b.x - point.x
      let qdy = b.y - point.y
      let distq = sqrt(qdx * qdx + qdy * qdy)

      cmp(distp, distq)
    )
    return intersections[0] # Return the closest intersection
  else:
    return intersections[0] # Only one intersection

# =============================================================================
# intersect-rect.nim
# =============================================================================
proc intersectRect*(node: tuple[x, y: float, width, height: float], point: Point): Point =
  let x = node.x
  let y = node.y
  let dx = point.x - x
  let dy = point.y - y
  var w = node.width / 2.0
  var h = node.height / 2.0

  var sx, sy: float
  # Intersection point is on top or bottom edge
  if abs(dy) * w > abs(dx) * h:
    if dy < 0: h = -h # Point is above the node center
    sx = if abs(dy) < 1e-9: 0.0 else: (h * dx) / dy # dx/dy is slope from center to point; h/sx = dy/dx
    sy = h
  # Intersection point is on left or right edge
  else:
    if dx < 0: w = -w # Point is left of the node center
    sx = w
    sy = if abs(dx) < 1e-9: 0.0 else: (w * dy) / dx # dy/dx is slope from center to point; w/sy = dx/dy

  return Point(x: x + sx, y: y + sy)

# =============================================================================
# Helper for lineWithOffset.ts (Not strictly needed for core intersection math, but good to have)
# =============================================================================
# The `lineWithOffset.ts` logic is more about calculating endpoint positions *after*
# an edge path is determined, considering arrow dimensions. It doesn't involve
# new geometric primitives but rather uses existing ones (like line-segment
# calculations). The core logic for calculating arrow offsets usually involves
# trigonometry and vector math, which are standard in `std/math`.

# For example, to calculate the offset for an arrowhead:
# 1. Get the last segment of the edge path: `p1` to `p2`.
# 2. Calculate the angle of this segment: `atan2(p2.y - p1.y, p2.x - p1.x)`.
# 3. Calculate the arrowhead geometry (e.g., triangle dimensions).
# 4. Use trigonometry with the segment angle and arrowhead dimensions to determine
#    how far back along the segment the arrowhead base should attach.
#
# This can be implemented as needed when you integrate edge rendering.
