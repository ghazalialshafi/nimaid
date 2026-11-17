import std/[tables, strutils, math]
import curves, textmetrics, gfx, label, png, types, theme, geom, shapes, styles, edges, clusters, dagre_adapter, flowdb

proc drawPolygon(shape: Pvg_Paint, pts: seq[Point]) =
  if pts.len < 3: return
  discard pvg_shape_move_to(shape, cfloat(pts[0].x), cfloat(pts[0].y))
  for i in 1 ..< pts.len:
    discard pvg_shape_line_to(shape, cfloat(pts[i].x), cfloat(pts[i].y))
  discard pvg_shape_close(shape)

proc emitPath(sh: Pvg_Paint, p: GPath) =
  for c in p.cmds:
    case c.op
    of 'M': discard pvg_shape_move_to(sh, cfloat(c.x1), cfloat(c.y1))
    of 'L': discard pvg_shape_line_to(sh, cfloat(c.x1), cfloat(c.y1))
    of 'C': discard pvg_shape_cubic_to(sh, cfloat(c.x1), cfloat(c.y1), cfloat(c.x2), cfloat(c.y2), cfloat(c.x3), cfloat(c.y3))
    of 'Z': discard pvg_shape_close(sh)
    else: discard

proc setDash(sh: Pvg_Paint, dash: seq[float]) =
  if dash.len == 0: return
  var d = newSeq[cfloat](dash.len)
  for i, v in dash: d[i] = cfloat(v)
  discard pvg_shape_set_stroke_dash(sh, addr d[0], uint32(d.len), 0.0)

proc addText(scene: Pvg_Paint, text: string, x, y: float, size: float, color: Color, th: FlowTheme) =
  drawLabel(scene, text, x, y, size, color)

proc buildClusterPaint(sub: LayoutResultNode, th: FlowTheme): Pvg_Paint =
  let scene = pvg_scene_new()
  let geom = calculateClusterGeometry(sub.shape, sub.x, sub.y, sub.width, sub.height, 8.0, float(measureLabel(sub.label, 14.0).w), 16.0)
  let rs = resolveStyles(sub.compiledStyles, sub.styles)
  let cFill = if rs.hasFill: rs.fill else: th.clusterBkg
  let cStroke = if rs.hasStroke: rs.stroke else: th.clusterBorder
  let box = pvg_shape_new()
  discard pvg_shape_append_rect(box, cfloat(geom.x), cfloat(geom.y), cfloat(geom.width), cfloat(geom.height), 0.0, 0.0, true)
  discard pvg_shape_set_fill_color(box, cFill.r, cFill.g, cFill.b, cFill.a)
  discard pvg_shape_set_stroke_width(box, if rs.strokeWidth > 0: cfloat(rs.strokeWidth) else: th.strokeWidth)
  discard pvg_shape_set_stroke_color(box, cStroke.r, cStroke.g, cStroke.b, cStroke.a)
  if rs.hasDash: setDash(box, rs.dash)
  discard pvg_scene_add(scene, box)

  if geom.paintsTitle and sub.label.len > 0:
    let tc = if rs.hasColor: rs.color else: th.titleColor
    drawLabel(scene, sub.label, sub.x, sub.y - sub.height / 2.0 + 1.0, th.fontSize, tc, alignTop = true)

  scene

proc buildEdgeLabelPaint(edge: LayoutResultEdge, th: FlowTheme): Pvg_Paint =
  ## Opaque badge (pre-blended over the page background) so edge lines never show through the label.
  let scene = pvg_scene_new()
  let (lw, lh) = edgeLabelSize(edge.label)
  let a = float(th.edgeLabelBkg.a) / 255.0
  proc mix(f, b: uint8): uint8 = uint8(float(f) * a + float(b) * (1 - a))
  let bg = th.background
  let badge = pvg_shape_new()
  discard pvg_shape_append_rect(badge, cfloat(edge.labelPos.x - lw / 2.0), cfloat(edge.labelPos.y - lh / 2.0), cfloat(lw), cfloat(lh), 3.0, 3.0, true)
  discard pvg_shape_set_fill_color(badge, mix(th.edgeLabelBkg.r, bg.r), mix(th.edgeLabelBkg.g, bg.g), mix(th.edgeLabelBkg.b, bg.b), 255)
  discard pvg_scene_add(scene, badge)
  drawLabel(scene, edge.label, edge.labelPos.x, edge.labelPos.y, float(edgeLabelFontSize), th.textColor)
  scene

proc buildNodePaint*(node: LayoutResultNode, th: FlowTheme): Pvg_Paint =
  let scene = pvg_scene_new()
  let rs = resolveStyles(node.compiledStyles, node.styles)
  let fillC = if rs.hasFill: rs.fill else: th.nodeBkg
  let strokeC = if rs.hasStroke: rs.stroke else: th.nodeBorder
  let sw = if rs.strokeWidth > 0: rs.strokeWidth else: th.strokeWidth
  let textC = if rs.hasColor: rs.color else: th.nodeText
  let g = node.geom

  for gp in g.paths:
    let sh = pvg_shape_new()
    emitPath(sh, gp)
    case gp.fill
    of fmNode: discard pvg_shape_set_fill_color(sh, fillC.r, fillC.g, fillC.b, fillC.a)
    of fmLine: discard pvg_shape_set_fill_color(sh, th.lineColor.r, th.lineColor.g, th.lineColor.b, th.lineColor.a)
    of fmBorder: discard pvg_shape_set_fill_color(sh, strokeC.r, strokeC.g, strokeC.b, strokeC.a)
    of fmBg: discard pvg_shape_set_fill_color(sh, th.background.r, th.background.g, th.background.b, th.background.a)
    of fmAlt:
      discard pvg_shape_set_fill_color(sh, uint8((int(fillC.r) + int(th.background.r)) div 2),
        uint8((int(fillC.g) + int(th.background.g)) div 2), uint8((int(fillC.b) + int(th.background.b)) div 2), 255)
    of fmNone: discard
    if gp.stroke:
      discard pvg_shape_set_stroke_width(sh, cfloat(sw))
      discard pvg_shape_set_stroke_color(sh, strokeC.r, strokeC.g, strokeC.b, strokeC.a)
      discard pvg_shape_set_stroke_join(sh, PVG_STROKE_JOIN_ROUND)
      if rs.hasDash: setDash(sh, rs.dash)
    discard pvg_scene_add(scene, sh)

  for t in g.texts:
    let size = t.size
    if t.alignLeft:
      drawLabel(scene, t.text, t.x, t.y, size, textC, alignLeft = true)
    else:
      drawLabel(scene, t.text, t.x, t.y, size, textC)
  if node.label.len > 0 and not g.noLabel:
    addText(scene, node.label, g.labelDx, g.labelDy, if rs.fontSize > 0: rs.fontSize else: th.fontSize, textC, th)

  discard pvg_paint_translate(scene, cfloat(node.x), cfloat(node.y))
  if rs.opacity >= 0:
    discard pvg_paint_set_opacity(scene, uint8(clamp(rs.opacity * 255.0, 0.0, 255.0)))
  scene

proc drawMarker(scene: Pvg_Paint, marker: MarkerShape, th: FlowTheme) =
  if marker.points.len >= 3:
    let sh = pvg_shape_new()
    drawPolygon(sh, marker.points)
    if marker.fill:
      discard pvg_shape_set_fill_color(sh, th.arrowheadColor.r, th.arrowheadColor.g, th.arrowheadColor.b, th.arrowheadColor.a)
    else:
      discard pvg_shape_set_fill_color(sh, th.background.r, th.background.g, th.background.b, 255)
    discard pvg_shape_set_stroke_width(sh, th.strokeWidth)
    discard pvg_shape_set_stroke_color(sh, th.arrowheadColor.r, th.arrowheadColor.g, th.arrowheadColor.b, th.arrowheadColor.a)
    discard pvg_scene_add(scene, sh)

  if marker.circleRadius > 0.0:
    let sh = pvg_shape_new()
    discard pvg_shape_append_circle(sh, cfloat(marker.circleCenter.x), cfloat(marker.circleCenter.y), cfloat(marker.circleRadius), cfloat(marker.circleRadius), true)
    if marker.fill:
      discard pvg_shape_set_fill_color(sh, th.arrowheadColor.r, th.arrowheadColor.g, th.arrowheadColor.b, th.arrowheadColor.a)
    else:
      discard pvg_shape_set_fill_color(sh, th.background.r, th.background.g, th.background.b, 255)
    discard pvg_shape_set_stroke_width(sh, th.strokeWidth)
    discard pvg_shape_set_stroke_color(sh, th.arrowheadColor.r, th.arrowheadColor.g, th.arrowheadColor.b, th.arrowheadColor.a)
    discard pvg_scene_add(scene, sh)

  for l in marker.lines:
    let sh = pvg_shape_new()
    discard pvg_shape_move_to(sh, cfloat(l.p1.x), cfloat(l.p1.y))
    discard pvg_shape_line_to(sh, cfloat(l.p2.x), cfloat(l.p2.y))
    discard pvg_shape_set_stroke_width(sh, th.strokeWidth)
    discard pvg_shape_set_stroke_color(sh, th.arrowheadColor.r, th.arrowheadColor.g, th.arrowheadColor.b, th.arrowheadColor.a)
    discard pvg_scene_add(scene, sh)

proc buildEdgePaint(edge: LayoutResultEdge, th: FlowTheme): Pvg_Paint =
  let scene = pvg_scene_new()
  if edge.points.len >= 2:
    let sh = pvg_shape_new()
    let cmds = curveCommands(edge.points, edge.curve)
    for c in cmds:
      case c.kind
      of pckMove: discard pvg_shape_move_to(sh, cfloat(c.p1.x), cfloat(c.p1.y))
      of pckLine: discard pvg_shape_line_to(sh, cfloat(c.p1.x), cfloat(c.p1.y))
      of pckCubic: discard pvg_shape_cubic_to(sh, cfloat(c.p1.x), cfloat(c.p1.y), cfloat(c.p2.x), cfloat(c.p2.y), cfloat(c.p3.x), cfloat(c.p3.y))

    let es = resolveStyles(edge.compiledStyles, edge.styles)
    let lineC = if es.hasStroke: es.stroke else: th.lineColor
    var sWidth = if edge.stroke == fesThick: 3.5 else: 2.0 * th.strokeWidth
    if es.strokeWidth > 0: sWidth = es.strokeWidth
    if edge.stroke == fesInvisible: sWidth = 0
    discard pvg_shape_set_stroke_width(sh, cfloat(sWidth))
    discard pvg_shape_set_stroke_color(sh, lineC.r, lineC.g, lineC.b, lineC.a)
    discard pvg_shape_set_stroke_cap(sh, PVG_STROKE_CAP_BUTT)
    discard pvg_shape_set_stroke_join(sh, PVG_STROKE_JOIN_ROUND)

    if es.hasDash: setDash(sh, es.dash)
    elif edge.stroke == fesDotted: setDash(sh, @[2.0, 2.0])

    discard pvg_scene_add(scene, sh)

    let (hasStart, startShape, hasEnd, endShape) = getEdgeTerminalMarkers((if edge.markerPoints.len >= 2: edge.markerPoints else: edge.points), edge.arrowTypeStart, edge.arrowTypeEnd)
    if hasStart: drawMarker(scene, startShape, th)
    if hasEnd: drawMarker(scene, endShape, th)

  scene

type DiagramBounds* = tuple[minX, minY, maxX, maxY: float]

const TitleFontSize = 18.0
const TitleBand = 38.0      ## vertical space reserved above the diagram for a title

proc contentBounds(res: LayoutResult): DiagramBounds

proc paintDiagram*(res: LayoutResult, th: FlowTheme = defaultTheme()): Pvg_Paint =
  let root = pvg_scene_new()
  if res.title.len > 0:
    let cb = contentBounds(res)
    addText(root, res.title, (cb.minX + cb.maxX) / 2, cb.minY - TitleBand / 2 - 2, TitleFontSize, th.titleColor, th)
  for sub in res.subgraphs:
    discard pvg_scene_add(root, buildClusterPaint(sub, th))
  for e in res.edges:
    discard pvg_scene_add(root, buildEdgePaint(e, th))
  for _, node in res.nodes:
    if not node.isGroup:
      discard pvg_scene_add(root, buildNodePaint(node, th))
  for e in res.edges:
    if e.label.len > 0: discard pvg_scene_add(root, buildEdgeLabelPaint(e, th))
  root

proc contentBounds(res: LayoutResult): DiagramBounds =
  var b: DiagramBounds = (1e18, 1e18, -1e18, -1e18)
  proc grow(b: var DiagramBounds, x, y: float) =
    b.minX = min(b.minX, x); b.maxX = max(b.maxX, x)
    b.minY = min(b.minY, y); b.maxY = max(b.maxY, y)
  for _, n in res.nodes:
    b.grow(n.x - n.width / 2, n.y - n.height / 2)
    b.grow(n.x + n.width / 2, n.y + n.height / 2)
  for n in res.subgraphs:
    b.grow(n.x - n.width / 2, n.y - n.height / 2)
    b.grow(n.x + n.width / 2, n.y + n.height / 2)
  for e in res.edges:
    for p in e.points: b.grow(p.x, p.y)
    if e.label.len > 0:
      let (lw, lh) = edgeLabelSize(e.label)
      b.grow(e.labelPos.x - lw / 2, e.labelPos.y - lh / 2)
      b.grow(e.labelPos.x + lw / 2, e.labelPos.y + lh / 2)
  if b.minX > b.maxX: b = (0.0, 0.0, 100.0, 100.0)
  b

proc diagramBounds*(res: LayoutResult): DiagramBounds =
  result = contentBounds(res)
  if res.title.len > 0:
    let tw = float(measureLabel(res.title, TitleFontSize).w)
    let cx = (result.minX + result.maxX) / 2
    result.minX = min(result.minX, cx - tw / 2)
    result.maxX = max(result.maxX, cx + tw / 2)
    result.minY -= TitleBand

type RenderedImage* = object
  width*, height*: int
  rgba*: seq[byte]   ## straight RGBA8 bytes, row-major

type Composed* = object
  root*: Node
  width*, height*: int

proc composeScene*(content: Pvg_Paint, b: DiagramBounds, th: FlowTheme,
                   margin = 16.0, scale = 2.0): Composed =
  ## Background + margin + scale around the painted content (shared by raster and SVG output).
  let w = max(1, int(ceil((b.maxX - b.minX + 2 * margin) * scale)))
  let h = max(1, int(ceil((b.maxY - b.minY + 2 * margin) * scale)))
  let outer = pvg_scene_new()
  let bg = pvg_shape_new()
  discard pvg_shape_append_rect(bg, 0, 0, cfloat(w), cfloat(h), 0, 0, true)
  discard pvg_shape_set_fill_color(bg, th.background.r, th.background.g, th.background.b, th.background.a)
  discard pvg_scene_add(outer, bg)
  discard pvg_paint_translate(content, cfloat(margin - b.minX), cfloat(margin - b.minY))
  let scaled = pvg_scene_new()
  discard pvg_scene_add(scaled, content)
  if scale != 1.0: discard pvg_paint_scale(scaled, cfloat(scale))
  discard pvg_scene_add(outer, scaled)
  Composed(root: outer, width: w, height: h)

proc rasterizeScene*(content: Pvg_Paint, b: DiagramBounds, th: FlowTheme,
                     margin = 16.0, scale = 2.0): RenderedImage =
  let c = composeScene(content, b, th, margin, scale)
  RenderedImage(width: c.width, height: c.height, rgba: renderRgba(c.root, c.width, c.height))

proc renderToImage*(res: LayoutResult, th: FlowTheme = defaultTheme(),
                    margin = 16.0, scale = 2.0): RenderedImage =
  ## Rasterises the laid-out flowchart (call pvg_engine_init first).
  rasterizeScene(paintDiagram(res, th), diagramBounds(res), th, margin, scale)

proc renderToPngFile*(res: LayoutResult, path: string, th: FlowTheme = defaultTheme(),
                      margin = 16.0, scale = 2.0) =
  let img = renderToImage(res, th, margin, scale)
  writePng(path, img.rgba, img.width, img.height)
