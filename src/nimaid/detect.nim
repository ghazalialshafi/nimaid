import std/strutils
import preprocess

proc detectDiagramType*(rawText: string): string =
  let fm = extractFrontMatter(rawText)
  var text = stripAnyComments(stripDirectives(fm.text)).strip()

  if text.startsWith("flowchart-v2") or text.startsWith("flowchart") or text.startsWith("swimlane-beta") or text.startsWith("graph"):
    return "flowchart"
  if text.startsWith("sequenceDiagram"):
    return "sequence"
  if text.startsWith("gantt"):
    return "gantt"
  if text.startsWith("gitGraph"):
    return "gitgraph"
  if text.startsWith("mindmap"):
    return "mindmap"
  if text.startsWith("stateDiagram"):
    return "state"
  if text.startsWith("erDiagram"):
    return "er"
  if text.startsWith("classDiagram"):
    return "class"
  return "unknown"
