import std/strutils
import nimaid/[sankey, treemap, radar, kanban, packet, journey, quadrant, timeline, xychart, pie, chartheme, chartkit, gantt, gitgraph, mindmap, diagrams, gfx, svg, gif, config, sequence, detect, emoji, types, preprocess, theme, flowdb,
                flowparser, dagre_adapter, painter, label, textmetrics, png]
from nimaid/purevg import pvg_engine_init, pvg_engine_term
export sankey, treemap, radar, kanban, packet, journey, quadrant, timeline, xychart, pie, chartheme, chartkit, gantt, gitgraph, mindmap, diagrams, gfx, svg, gif, config, sequence, detect, emoji, types, theme, flowdb, dagre_adapter, painter,
       label, textmetrics, png

const nimaidVersion* = "0.5.1"

proc parseAndLayoutFlowchart*(chartText: string): LayoutResult =
  let fm = extractFrontMatter(chartText)
  let cleaned = stripAnyComments(stripDirectives(fm.text))
  let db = newFlowDB()
  parseFlowchart(cleaned, db)
  if fm.title.len > 0: db.setDiagramTitle(fm.title)
  result = runDagreLayout(db.getData())

proc themeFor*(text: string, forced = ""): FlowTheme =
  ## CLI/API theme name wins, then front-matter / init directive; themeVariables always apply.
  let cfg = readThemeConfig(text)
  result = themeByName(if forced.len > 0: forced else: cfg.name)
  result.applyOverrides(cfg.vars)

proc buildMermaidScene(text, fontPath: string, scale: float, emojiFontPath, themeName: string): Composed =
  ## Engine must already be initialised. Detects the diagram type, lays out and paints one scene.
  if emojiFontPath.len > 0: discard loadEmojiFont(emojiFontPath)
  if not initTextMetrics(fontPath): raise newException(IOError, "cannot load font " & fontPath)
  var th = themeFor(text, themeName)
  th.fontFamily = loadedFontName
  case detectDiagramType(text)
  of "flowchart":
    let layoutRes = parseAndLayoutFlowchart(text)
    result = composeScene(paintDiagram(layoutRes, th), diagramBounds(layoutRes), th, 16.0, scale)
  of "sequence":
    let (scene, bounds) = sequenceScene(text, th)
    result = composeScene(scene, bounds, th, 0.0, scale)
  of "gantt", "gitgraph", "mindmap":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = case detectDiagramType(text)
      of "gantt": ganttScene(cleaned, th)
      of "gitgraph": gitScene(cleaned, th)
      else: mindmapScene(cleaned, th)
    result = composeScene(scene, bounds, th, 16.0, scale)
  of "state", "er", "class":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    var chart = case detectDiagramType(text)
      of "state": parseStateChart(cleaned)
      of "er": parseErChart(cleaned)
      else: parseClassChart(cleaned)
    if fm.title.len > 0: chart.title = fm.title
    let layoutRes = runDagreLayout(chart)
    result = composeScene(paintDiagram(layoutRes, th), diagramBounds(layoutRes), th, 16.0, scale)
  of "packet":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = packetScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 0.0, scale)
  of "kanban":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = kanbanScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 18.0, scale)
  of "radar":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = radarScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 0.0, scale)
  of "treemap":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = treemapScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 8.0, scale)
  of "sankey":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = sankeyScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 10.0, scale)
  of "journey":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = journeyScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 0.0, scale)
  of "quadrant":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = quadrantScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 0.0, scale)
  of "timeline":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = timelineScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 50.0, scale)
  of "xychart":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = xychartScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 0.0, scale)
  of "pie":
    let fm = extractFrontMatter(text)
    let cleaned = stripAnyComments(stripDirectives(fm.text))
    let (scene, bounds) = pieScene(cleaned, chartVars(text, themeName), fm.title)
    result = composeScene(scene, bounds, th, 0.0, scale)
  else:
    raise newException(ValueError, "unsupported diagram type")

proc backgroundOf(text, themeName: string): array[4, uint8] =
  let b = themeFor(text, themeName).background
  [b.r, b.g, b.b, b.a]

proc renderMermaidToImage*(text, fontPath: string, scale = 2.0, emojiFontPath = "", themeName = ""): RenderedImage =
  discard pvg_engine_init(0)
  defer: discard pvg_engine_term()
  let c = buildMermaidScene(text, fontPath, scale, emojiFontPath, themeName)
  RenderedImage(width: c.width, height: c.height, rgba: renderRgba(c.root, c.width, c.height))

proc renderMermaidToSvg*(text, fontPath: string, emojiFontPath = "", themeName = "", svgText = false): string =
  ## Vector output (scale 1). Text is outlined (exact, font-independent) unless svgText=true (live <text>).
  ## Emoji are flattened to native paths/gradients.
  discard pvg_engine_init(0)
  defer: discard pvg_engine_term()
  let c = buildMermaidScene(text, fontPath, 1.0, emojiFontPath, themeName)
  toSvg(c.root, c.width, c.height, backgroundOf(text, themeName),
        textMode = (if svgText: stText else: stPaths))

proc renderMermaidToFile*(text, outputPath, fontPath: string, scale = 2.0, emojiFontPath = "",
                          themeName = "", colors = 0, svgText = false) =
  ## Format from the extension: .png (DEFLATE; colors=2..256 -> palette PNG), .gif, .svg
  let ext = outputPath.toLowerAscii
  if ext.endsWith(".svg"):
    writeFile(outputPath, renderMermaidToSvg(text, fontPath, emojiFontPath, themeName, svgText))
    return
  let img = renderMermaidToImage(text, fontPath, scale, emojiFontPath, themeName)
  if ext.endsWith(".gif"):
    writeGif(outputPath, img.rgba, img.width, img.height, if colors >= 2: colors else: 256)
  else:
    writePng(outputPath, img.rgba, img.width, img.height, colors)

proc renderFlowchartToPng*(chartText, outputPath: string, fontPath: string,
                           th: FlowTheme = defaultTheme(), scale = 2.0, emojiFontPath = ""): bool =
  try:
    renderMermaidToFile(chartText, outputPath, fontPath, scale, emojiFontPath)
    true
  except IOError: false
