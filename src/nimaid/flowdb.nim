## Port of mermaid's flowchart FlowDB (diagrams/flowchart/flowDb.ts).
import std/[tables, strutils, sets, options]
import types, shapereg

type
  DroppedSubGraphMember* = object
    node*, keptBy*, droppedFrom*: string

  FlowTextObj* = object
    text*: string
    kind*: FlowLabelKind

  FlowLinkInfo* = object          ## what the parser hands to addLink
    id*: string
    linkType*: string
    stroke*: FlowEdgeStroke
    length*: int
    hasText*: bool
    text*: FlowTextObj

  DocItemKind* = enum dikNode, dikDir
  DocItem* = object               ## one element of a (flattened) parsed `document`
    kind*: DocItemKind
    text*: string                 ## node/subgraph id, or direction value

  RenderNode* = object
    id*, label*: string
    labelType*: FlowLabelKind
    parentId*: string
    padding*: float32
    isGroup*: bool
    shape*: string                ## canonical handler id (squareRect, question, ...)
    dir*: string
    domId*: string
    styles*: seq[string]          ## inline `style` statements
    compiledStyles*: seq[string]  ## from classDef (applied before inline styles)
    classes*: seq[string]
    colorIndex*: int
    link*, linkTarget*, tooltip*: string
    icon*, img*: string
    box*: BoxSpec

  RenderEdge* = object
    id*, source*, target*, label*: string
    labelType*: FlowLabelKind
    stroke*: FlowEdgeStroke
    minlen*: int
    arrowTypeStart*, arrowTypeEnd*: string
    styles*: seq[string]
    compiledStyles*: seq[string]
    classes*: seq[string]
    isUserDefinedId*: bool
    curve*: string

  FlowChartData* = object
    nodes*: seq[RenderNode]
    edges*: seq[RenderEdge]
    direction*: string
    title*, accTitle*, accDescription*: string

  FlowDB* = ref object
    vertexCounter: int
    diagramId*: string
    vertices: OrderedTable[string, FlowVertex]
    edges: seq[FlowEdge]
    defaultInterpolate*: string
    defaultStyle*: seq[string]
    classes: Table[string, FlowClass]
    subGraphs: seq[FlowSubGraph]
    subGraphLookup: Table[string, FlowSubGraph]
    droppedSubGraphMembers*: seq[DroppedSubGraphMember]
    subCount: int
    firstGraphFlag: bool
    direction: string
    title, accTitle, accDescription: string
    tooltips: Table[string, string]
    maxEdges*: int

const MermaidDomIdPrefix = "flowchart-"

proc newFlowDB*(): FlowDB =
  FlowDB(firstGraphFlag: true, direction: "TB", maxEdges: 500,
         vertices: initOrderedTable[string, FlowVertex](),
         classes: initTable[string, FlowClass](),
         subGraphLookup: initTable[string, FlowSubGraph](),
         tooltips: initTable[string, string]())

proc clear*(db: FlowDB) =
  let keep = db.maxEdges
  db[] = newFlowDB()[]
  db.maxEdges = keep

proc setDiagramTitle*(db: FlowDB, t: string) = db.title = t.strip()
proc getDiagramTitle*(db: FlowDB): string = db.title
proc setAccTitle*(db: FlowDB, t: string) = db.accTitle = t.strip()
proc getAccTitle*(db: FlowDB): string = db.accTitle
proc setAccDescription*(db: FlowDB, t: string) = db.accDescription = t.strip()
proc getAccDescription*(db: FlowDB): string = db.accDescription

proc setDirection*(db: FlowDB, dir: string) =
  var d = dir.strip()
  if '<' in d: d = "RL"
  if '^' in d: d = "BT"
  if '>' in d: d = "LR"
  if 'v' in d: d = "TB"
  if d == "TD": d = "TB"
  db.direction = d

proc getDirection*(db: FlowDB): string = db.direction.strip()

proc firstGraph*(db: FlowDB): bool =
  if db.firstGraphFlag:
    db.firstGraphFlag = false
    return true
  false

proc sanitizeText(txt: string): string = txt

proc sanitizeNodeLabelType(t: string): FlowLabelKind =
  case t
  of "text": flkText
  of "string": flkString
  else: flkMarkdown      # mermaid: unknown -> 'markdown'

proc lookUpDomId*(db: FlowDB, id: string): string =
  if id in db.vertices:
    let d = db.vertices[id].domId
    return if db.diagramId.len > 0: db.diagramId & "-" & d else: d
  if db.diagramId.len > 0: db.diagramId & "-" & id else: id

# ---------------------------------------------------------------------------
# `@{ ... }` metadata: the YAML subset mermaid actually uses (flat key: value)
# ---------------------------------------------------------------------------
proc unquoteYaml(v: string): string =
  let s = v.strip()
  if s.len >= 2 and ((s[0] == '"' and s[^1] == '"') or (s[0] == '\'' and s[^1] == '\'')):
    result = s[1 ..< s.len - 1]
    if s[0] == '"': result = result.replace("\\\"", "\"").replace("\\n", "\n")
  else:
    result = s

proc splitTopLevel(s: string, sep: char): seq[string] =
  var cur = ""
  var q = '\0'
  for c in s:
    if q != '\0':
      cur.add c
      if c == q: q = '\0'
    elif c == '"' or c == '\'':
      q = c; cur.add c
    elif c == sep:
      result.add cur; cur = ""
    else:
      cur.add c
  result.add cur

proc parseMetadata*(meta: string): OrderedTable[string, string] =
  result = initOrderedTable[string, string]()
  let internal = ["laneRole", "laneIndex", "drawnExtent"]
  if '\n' notin meta:
    for p in splitTopLevel(meta, ','):
      let t = p.strip()
      let ci = t.find(':')
      if t.len > 0 and ci > 0:
        let k = t[0 ..< ci].strip()
        if k notin internal: result[k] = unquoteYaml(t[ci + 1 .. ^1])
    return
  let lines = meta.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    inc i
    if line.strip().len == 0: continue
    let indent = line.len - line.strip(trailing = false).len
    for p in splitTopLevel(line, ','):
      let t = p.strip()
      let ci = t.find(':')
      if t.len == 0 or ci <= 0: continue
      let k = t[0 ..< ci].strip()
      let v = t[ci + 1 .. ^1].strip()
      if v in ["|", ">", "|-", ">-"] and p == splitTopLevel(line, ',')[0]:
        # block scalar: following lines indented deeper than the key
        var parts: seq[string]
        while i < lines.len and (lines[i].strip().len == 0 or
              lines[i].len - lines[i].strip(trailing = false).len > indent):
          parts.add lines[i].strip()
          inc i
        let sep = if v[0] == '|': "\n" else: " "
        var text = parts.join(sep)
        if v.len == 1: text.add (if v[0] == '|': "\n" else: "")
        if k notin internal: result[k] = text
      elif k notin internal:
        result[k] = unquoteYaml(v)

# ---------------------------------------------------------------------------
proc addVertex*(db: FlowDB, id: string,
                text: Option[FlowTextObj] = none(FlowTextObj),
                shape = "",
                style: seq[string] = @[], hasStyle = false,
                classes: seq[string] = @[],
                dir = "",
                props: Table[string, string] = initTable[string, string](),
                metadata: Option[string] = none(string)) =
  if id.strip().len == 0: return

  var doc = initOrderedTable[string, string]()
  var hasDoc = false
  if metadata.isSome:
    doc = parseMetadata(metadata.get)
    hasDoc = true

  if hasDoc and id in db.subGraphLookup:
    if doc.len > 0:
      let sg = db.subGraphLookup[id]
      for k, v in doc: sg.metadata[k] = v
    return

  for e in db.edges:
    if e.id == id:
      if "animate" in doc:
        e.animate = doc["animate"] == "true"
        e.hasAnimate = true
      if "curve" in doc: e.interpolate = doc["curve"]
      return

  var v = db.vertices.getOrDefault(id)
  if v.isNil:
    v = FlowVertex(id: id, labelType: flkText,
                   domId: MermaidDomIdPrefix & id & "-" & $db.vertexCounter)
    db.vertices[id] = v
  inc db.vertexCounter

  if text.isSome:
    var txt = sanitizeText(text.get.text.strip())
    v.labelType = text.get.kind
    if txt.len >= 2 and txt.startsWith("\"") and txt.endsWith("\""):
      txt = txt[1 ..< txt.len - 1]
    v.text = txt
    v.hasText = true
  elif not v.hasText:
    v.text = id
    v.hasText = true

  if shape.len > 0: v.shape = shape
  if hasStyle or style.len > 0:
    for s in style: v.styles.add s
  for c in classes: v.classes.add c
  if dir.len > 0:
    v.dir = dir
    v.hasDir = true
  for k, val in props: v.props[k] = val

  if hasDoc:
    if "shape" in doc and doc["shape"].len > 0:
      let sh = doc["shape"]
      if sh != sh.toLowerAscii or '_' in sh:
        raise newException(ValueError, "No such shape: " & sh & ". Shape names should be lowercase.")
      elif not isValidShape(sh):
        raise newException(ValueError, "No such shape: " & sh & ".")
      v.shape = sh
    if "label" in doc and doc["label"].len > 0:
      v.text = doc["label"]
      v.labelType = sanitizeNodeLabelType(doc.getOrDefault("labelType", "markdown"))
    if "icon" in doc and doc["icon"].len > 0:
      v.icon = doc["icon"]
      if doc.getOrDefault("label", "").strip().len == 0 and v.text == id: v.text = ""
    if "form" in doc: v.form = doc["form"]
    if "pos" in doc: v.pos = doc["pos"]
    if "img" in doc and doc["img"].len > 0:
      v.img = doc["img"]
      if doc.getOrDefault("label", "").strip().len == 0 and v.text == id: v.text = ""
    if "constraint" in doc: v.constraint = doc["constraint"]
    try:
      if "w" in doc: v.assetWidth = parseFloat(doc["w"])
      if "h" in doc: v.assetHeight = parseFloat(doc["h"])
    except ValueError: discard

# ---------------------------------------------------------------------------
# links
# ---------------------------------------------------------------------------
proc destructStartLink(raw: string): tuple[linkType: string, stroke: FlowEdgeStroke] =
  var s = raw.strip()
  result.linkType = "arrow_open"
  if s.len > 0:
    case s[0]
    of '<': result.linkType = "arrow_point"; s = s[1 .. ^1]
    of 'x': result.linkType = "arrow_cross"; s = s[1 .. ^1]
    of 'o': result.linkType = "arrow_circle"; s = s[1 .. ^1]
    else: discard
  result.stroke = fesNormal
  if '=' in s: result.stroke = fesThick
  if '.' in s: result.stroke = fesDotted

proc destructEndLink(raw: string): FlowLinkInfo =
  let s = raw.strip()
  if s.len == 0: return FlowLinkInfo(linkType: "arrow_open", length: 0)
  var line = s[0 ..< s.len - 1]
  var t = "arrow_open"
  case s[^1]
  of 'x':
    t = "arrow_cross"
    if s.startsWith('x'):
      t = "double_" & t
      line = line[1 .. ^1]
  of '>':
    t = "arrow_point"
    if s.startsWith('<'):
      t = "double_" & t
      line = line[1 .. ^1]
  of 'o':
    t = "arrow_circle"
    if s.startsWith('o'):
      t = "double_" & t
      line = line[1 .. ^1]
  else: discard
  var stroke = fesNormal
  var length = line.len - 1
  if line.startsWith('='): stroke = fesThick
  if line.startsWith('~'): stroke = fesInvisible
  let dots = line.count('.')
  if dots > 0:
    stroke = fesDotted
    length = dots
  FlowLinkInfo(linkType: t, stroke: stroke, length: length)

proc destructLink*(endStr: string, startStr: string = ""): FlowLinkInfo =
  let info = destructEndLink(endStr)
  if startStr.len > 0:
    var st = destructStartLink(startStr)
    if st.stroke != info.stroke:
      return FlowLinkInfo(linkType: "INVALID", stroke: fesNormal)
    if st.linkType == "arrow_open":
      st.linkType = info.linkType
    else:
      if st.linkType != info.linkType:
        return FlowLinkInfo(linkType: "INVALID", stroke: fesNormal)
      st.linkType = "double_" & st.linkType
    if st.linkType == "double_arrow": st.linkType = "double_arrow_point"
    return FlowLinkInfo(linkType: st.linkType, stroke: st.stroke, length: info.length)
  info

proc addSingleLink*(db: FlowDB, start, endNode: string, link: FlowLinkInfo, id = "") =
  var edge = FlowEdge(source: start, target: endNode, labelType: flkText,
                      interpolate: db.defaultInterpolate)
  if link.hasText:
    edge.text = sanitizeText(link.text.text.strip())
    if edge.text.len >= 2 and edge.text.startsWith("\"") and edge.text.endsWith("\""):
      edge.text = edge.text[1 ..< edge.text.len - 1]
    edge.labelType = link.text.kind
  edge.kind = link.linkType
  edge.stroke = link.stroke
  edge.length = min(link.length, 10)

  var idTaken = false
  if id.len > 0:
    for e in db.edges:
      if e.id == id: idTaken = true
  if id.len > 0 and not idTaken:
    edge.id = id
    edge.isUserDefinedId = true
  else:
    var existing = 0
    for e in db.edges:
      if e.source == start and e.target == endNode: inc existing
    let counter = if existing == 0: 0 else: existing + 1
    edge.id = "L_" & start & "_" & endNode & "_" & $counter

  if db.edges.len < db.maxEdges:
    db.edges.add edge
  else:
    raise newException(ValueError, "Edge limit exceeded. " & $db.edges.len &
                       " edges found, but the limit is " & $db.maxEdges & ".")

proc addLink*(db: FlowDB, starts, ends: seq[string], link: FlowLinkInfo) =
  let id = link.id.replace("@", "")
  for s in starts:
    for e in ends:
      let isLastStart = s == starts[^1]
      let isFirstEnd = e == ends[0]
      if isLastStart and isFirstEnd: db.addSingleLink(s, e, link, id)
      else: db.addSingleLink(s, e, link, "")

proc updateLinkInterpolate*(db: FlowDB, positions: seq[string], interpolate: string) =
  for p in positions:
    if p == "default": db.defaultInterpolate = interpolate
    else: db.edges[parseInt(p)].interpolate = interpolate

proc updateLink*(db: FlowDB, positions: seq[string], style: seq[string]) =
  for p in positions:
    if p != "default" and parseInt(p) >= db.edges.len:
      raise newException(ValueError, "The index " & p & " for linkStyle is out of bounds. Valid indices for linkStyle are between 0 and " &
                         $(db.edges.len - 1) & ".")
    if p == "default":
      db.defaultStyle = style
    else:
      let e = db.edges[parseInt(p)]
      e.styles = style
      if e.styles.len > 0:
        var hasFill = false
        for s in e.styles:
          if s.startsWith("fill"): hasFill = true
        if not hasFill: e.styles.add "fill:none"

proc addClass*(db: FlowDB, ids: string, styleIn: seq[string]) =
  let joined = styleIn.join(",").replace("\\,", "§§§").replace(",", ";").replace("§§§", ",")
  for id in ids.split(','):
    if id notin db.classes:
      db.classes[id] = FlowClass(id: id)
    for s in joined.split(';'):
      if "color" in s:
        db.classes[id].textStyles.add s.replace("fill", "bgFill")
      db.classes[id].styles.add s

proc setClass*(db: FlowDB, ids: string, className: string) =
  for id in ids.split(','):
    if id in db.vertices: db.vertices[id].classes.add className
    for e in db.edges:
      if e.id == id:
        e.classes.add className
        break
    if id in db.subGraphLookup: db.subGraphLookup[id].classes.add className

proc setTooltip*(db: FlowDB, ids, tooltip: string) =
  for id in ids.split(','): db.tooltips[id] = sanitizeText(tooltip)

proc setLink*(db: FlowDB, ids, linkStr: string, target = "") =
  for id in ids.split(','):
    if id in db.vertices:
      db.vertices[id].link = linkStr
      db.vertices[id].linkTarget = target
  db.setClass(ids, "clickable")

proc setClickEvent*(db: FlowDB, ids, functionName: string, functionArgs = "") =
  # callbacks only run in a browser (securityLevel 'loose'); nothing to bind here.
  db.setClass(ids, "clickable")

# ---------------------------------------------------------------------------
# subgraphs
# ---------------------------------------------------------------------------
proc existsIn(all: seq[FlowSubGraph], id: string): bool =
  for sg in all:
    if id in sg.nodes: return true

proc isNestedIn(db: FlowDB, id: string, ancestor: FlowSubGraph): bool =
  var visited = initHashSet[string]()
  var cur = id
  while cur.len > 0 and cur notin visited:
    if cur in ancestor.nodes: return true
    visited.incl cur
    var parent = ""
    for sg in db.subGraphs:
      if cur in sg.nodes:
        parent = sg.id
        break
    cur = parent

proc addSubGraph*(db: FlowDB, idText: string, list: seq[DocItem], titleText: string,
                  titleKind = flkText, idIsTitle = false): string =
  var id = idText.strip()
  var hasId = idText.len > 0
  if idIsTitle and titleText.find(Whitespace) >= 0: hasId = false

  var nodeList: seq[string]
  var seen = initHashSet[string]()
  var dir = ""
  var hasDir = false
  for it in list:
    case it.kind
    of dikDir:
      dir = it.text
      hasDir = true
    of dikNode:
      if it.text.strip().len == 0: continue
      if it.text notin seen:
        seen.incl it.text
        nodeList.add it.text

  if not hasId: id = "subGraph" & $db.subCount
  inc db.subCount
  let sg = FlowSubGraph(id: id, nodes: nodeList, title: sanitizeText(titleText).strip(),
                        dir: dir, hasDir: hasDir, labelType: titleKind)
  var uniqueNodes: seq[string]
  for n in sg.nodes:
    if not existsIn(db.subGraphs, n): uniqueNodes.add n
  let kept = uniqueNodes.toHashSet()
  for n in sg.nodes:
    if n in kept or n == sg.id: continue
    for owner in db.subGraphs:
      if n in owner.nodes:
        if owner.id != sg.id and not db.isNestedIn(owner.id, sg):
          db.droppedSubGraphMembers.add DroppedSubGraphMember(node: n, keptBy: owner.id, droppedFrom: sg.id)
        break
  sg.nodes = @[]
  for n in uniqueNodes:
    if n != id: sg.nodes.add n

  var existing: FlowSubGraph = nil
  for s in db.subGraphs:
    if s.id == id:
      existing = s
      break
  if not existing.isNil: existing.nodes.add sg.nodes
  else: db.subGraphs.add sg
  db.subGraphLookup[id] = if existing.isNil: sg else: existing
  id

# ---------------------------------------------------------------------------
# getData: DB -> layout input
# ---------------------------------------------------------------------------
proc getCompiledStyles(db: FlowDB, classDefs: seq[string]): seq[string] =
  for c in classDefs:
    if c in db.classes:
      for s in db.classes[c].styles: result.add s.strip()
      for s in db.classes[c].textStyles: result.add s.strip()

proc shapeFor(v: FlowVertex): string =
  if v.img.len > 0: return "imageSquare"
  if v.icon.len > 0:
    case v.form
    of "circle": return "iconCircle"
    of "square": return "iconSquare"
    of "rounded": return "iconRounded"
    else: return "icon"
  case v.shape
  of "", "square": "squareRect"
  of "round": "roundedRect"
  else: v.shape

proc destructEdgeType(t: string): tuple[s, e: string] =
  result = ("none", "arrow_point")
  case t
  of "arrow_point", "arrow_circle", "arrow_cross": result.e = t
  of "double_arrow_point", "double_arrow_circle", "double_arrow_cross":
    result.s = t.replace("double_", "")
    result.e = result.s
  else: discard

proc getData*(db: FlowDB): FlowChartData =
  result.direction = db.direction
  result.title = db.title
  result.accTitle = db.accTitle
  result.accDescription = db.accDescription

  var parentDB = initTable[string, string]()
  var subGraphParent = initTable[string, string]()
  for sg in db.subGraphs:
    for c in sg.nodes:
      if c in db.subGraphLookup: subGraphParent[c] = sg.id

  # colour slots follow source order: pre-order walk of the containment forest
  var childrenOf = initTable[string, seq[string]]()
  for sg in db.subGraphs:
    if sg.id in subGraphParent:
      childrenOf.mgetOrPut(subGraphParent[sg.id], @[]).add sg.id
  var declIdx = initTable[string, int]()
  var nextIdx = 0
  proc walk(id: string) =
    declIdx[id] = nextIdx
    inc nextIdx
    for c in childrenOf.getOrDefault(id): walk(c)
  for sg in db.subGraphs:
    if sg.id notin subGraphParent: walk(sg.id)

  for i in countdown(db.subGraphs.len - 1, 0):
    let sg = db.subGraphs[i]
    for id in sg.nodes: parentDB[id] = sg.id

  var nodeIndex = initTable[string, int]()
  for i in countdown(db.subGraphs.len - 1, 0):
    let sg = db.subGraphs[i]
    nodeIndex[sg.id] = result.nodes.len
    result.nodes.add RenderNode(
      id: sg.id, label: sg.title, labelType: sg.labelType,
      parentId: parentDB.getOrDefault(sg.id), padding: 8, isGroup: true, shape: "rect",
      dir: sg.dir, domId: sg.id, classes: sg.classes,
      compiledStyles: db.getCompiledStyles(sg.classes),
      colorIndex: declIdx.getOrDefault(sg.id, 0))

  for _, v in db.vertices:
    if v.id in nodeIndex:
      let idx = nodeIndex[v.id]
      result.nodes[idx].styles = v.styles
      result.nodes[idx].compiledStyles = db.getCompiledStyles(v.classes)
      result.nodes[idx].classes = v.classes
      continue
    result.nodes.add RenderNode(
      id: v.id, label: v.text, labelType: v.labelType,
      parentId: parentDB.getOrDefault(v.id), padding: 8, isGroup: false,
      shape: shapeFor(v), dir: v.dir, domId: v.domId,
      styles: v.styles,
      compiledStyles: db.getCompiledStyles(@["default", "node"] & v.classes),
      classes: v.classes, colorIndex: -1,
      link: v.link, linkTarget: v.linkTarget,
      tooltip: db.tooltips.getOrDefault(v.id), icon: v.icon, img: v.img)

  for e in db.edges:
    let (aStart, aEnd) = destructEdgeType(e.kind)
    let hidden = e.stroke == fesInvisible or e.kind == "arrow_open"
    result.edges.add RenderEdge(
      id: e.id, source: e.source, target: e.target, label: e.text, labelType: e.labelType,
      stroke: e.stroke, minlen: max(1, e.length),
      arrowTypeStart: (if hidden: "none" else: aStart),
      arrowTypeEnd: (if hidden: "none" else: aEnd),
      styles: db.defaultStyle & e.styles,
      compiledStyles: db.getCompiledStyles(e.classes),
      classes: e.classes, isUserDefinedId: e.isUserDefinedId,
      curve: (if e.interpolate.len > 0: e.interpolate else: db.defaultInterpolate))

# ---- read accessors (mirror mermaid's FlowDB getters) ----
proc getVertices*(db: FlowDB): OrderedTable[string, FlowVertex] = db.vertices
proc getEdges*(db: FlowDB): seq[FlowEdge] = db.edges
proc getSubGraphs*(db: FlowDB): seq[FlowSubGraph] = db.subGraphs
proc getClasses*(db: FlowDB): Table[string, FlowClass] = db.classes
proc getTooltip*(db: FlowDB, id: string): string = db.tooltips.getOrDefault(id)
