import std/[strutils, tables, math]

type
  Color* = object
    r*, g*, b*, a*: uint8

  FlowTheme* = object
    background*: Color
    nodeBkg*: Color
    nodeBorder*: Color
    clusterBkg*: Color
    clusterBorder*: Color
    lineColor*: Color
    arrowheadColor*: Color
    textColor*: Color
    titleColor*: Color
    edgeLabelBkg*: Color
    fontFamily*: string
    fontSize*: float32
    radius*: float32
    strokeWidth*: float32
    nodeText*: Color
    noteBkg*, noteBorder*, noteText*: Color
    actorBkg*, actorBorder*, actorText*, actorLine*: Color
    signal*, signalText*: Color
    labelBoxBkg*, labelBoxBorder*, labelText*, loopText*: Color
    activationBkg*, activationBorder*, seqNumber*: Color

proc rgba*(r, g, b: uint8, a: uint8 = 255): Color {.inline.} =
  Color(r: r, g: g, b: b, a: a)

proc hexDigit(c: char): int {.inline.} =
  case c
  of '0'..'9': ord(c) - ord('0')
  of 'a'..'f': ord(c) - ord('a') + 10
  of 'A'..'F': ord(c) - ord('A') + 10
  else: -1

proc parseColor*(raw: string): Color =
  let s = raw.strip()
  if s.len == 0:
    return rgba(0, 0, 0, 255)

  if s.startsWith("#"):
    let hex = s[1 .. ^1]
    case hex.len
    of 3:
      let r = hexDigit(hex[0])
      let g = hexDigit(hex[1])
      let b = hexDigit(hex[2])
      if r >= 0 and g >= 0 and b >= 0:
        return rgba(uint8(r * 17), uint8(g * 17), uint8(b * 17))
    of 6:
      let r1 = hexDigit(hex[0]); let r2 = hexDigit(hex[1])
      let g1 = hexDigit(hex[2]); let g2 = hexDigit(hex[3])
      let b1 = hexDigit(hex[4]); let b2 = hexDigit(hex[5])
      if r1 >= 0 and r2 >= 0 and g1 >= 0 and g2 >= 0 and b1 >= 0 and b2 >= 0:
        return rgba(uint8(r1 * 16 + r2), uint8(g1 * 16 + g2), uint8(b1 * 16 + b2))
    of 8:
      let r1 = hexDigit(hex[0]); let r2 = hexDigit(hex[1])
      let g1 = hexDigit(hex[2]); let g2 = hexDigit(hex[3])
      let b1 = hexDigit(hex[4]); let b2 = hexDigit(hex[5])
      let a1 = hexDigit(hex[6]); let a2 = hexDigit(hex[7])
      if r1 >= 0 and r2 >= 0 and g1 >= 0 and g2 >= 0 and b1 >= 0 and b2 >= 0 and a1 >= 0 and a2 >= 0:
        return rgba(uint8(r1 * 16 + r2), uint8(g1 * 16 + g2), uint8(b1 * 16 + b2), uint8(a1 * 16 + a2))
    else:
      discard

  if s.toLowerAscii.startsWith("rgba(") and s.endsWith(")"):
    let parts = s[5 .. ^2].split(',')
    if parts.len == 4:
      let r = uint8(clamp(parseInt(parts[0].strip()), 0, 255))
      let g = uint8(clamp(parseInt(parts[1].strip()), 0, 255))
      let b = uint8(clamp(parseInt(parts[2].strip()), 0, 255))
      let a = uint8(clamp(int(parseFloat(parts[3].strip()) * 255.0), 0, 255))
      return rgba(r, g, b, a)

  if s.toLowerAscii.startsWith("rgb(") and s.endsWith(")"):
    let parts = s[4 .. ^2].split(',')
    if parts.len == 3:
      let r = uint8(clamp(parseInt(parts[0].strip()), 0, 255))
      let g = uint8(clamp(parseInt(parts[1].strip()), 0, 255))
      let b = uint8(clamp(parseInt(parts[2].strip()), 0, 255))
      return rgba(r, g, b, 255)

  case s.toLowerAscii
  of "white": rgba(255, 255, 255)
  of "black": rgba(0, 0, 0)
  of "red": rgba(255, 0, 0)
  of "green": rgba(0, 128, 0)
  of "blue": rgba(0, 0, 255)
  of "grey", "gray": rgba(128, 128, 128)
  of "lightgrey", "lightgray": rgba(211, 211, 211)
  of "transparent": rgba(0, 0, 0, 0)
  else: rgba(0, 0, 0, 255)

import themepresets

proc presetColor(p: Table[string, array[4, int]], key: string, fallback: Color): Color =
  if key in p:
    let v = p[key]
    Color(r: uint8(v[0]), g: uint8(v[1]), b: uint8(v[2]), a: uint8(v[3]))
  else: fallback

const themeNames* = ["default", "dark", "forest", "neutral", "base"]

proc themeByName*(name: string): FlowTheme =
  ## Exact values evaluated from mermaid's theme-*.js (default, dark, forest, neutral, base).
  let key = if name.toLowerAscii in themeNames: name.toLowerAscii else: "default"
  let p = themePresets[key]
  let white = rgba(255, 255, 255)
  let c = proc(k: string, fb: Color): Color = presetColor(p, k, fb)
  result.background = c("background", white)
  result.nodeBkg = c("mainBkg", rgba(236, 236, 255))
  result.nodeBorder = c("nodeBorder", rgba(147, 112, 219))
  result.clusterBkg = c("clusterBkg", rgba(255, 255, 222))
  result.clusterBorder = c("clusterBorder", rgba(170, 170, 51))
  result.lineColor = c("lineColor", rgba(51, 51, 51))
  result.arrowheadColor = c("arrowheadColor", result.lineColor)
  result.textColor = c("textColor", rgba(51, 51, 51))
  result.titleColor = c("titleColor", result.textColor)
  result.edgeLabelBkg = c("edgeLabelBackground", rgba(232, 232, 232, 204))
  result.nodeText = c("nodeTextColor", result.textColor)
  result.noteBkg = c("noteBkgColor", rgba(255, 245, 173))
  result.noteBorder = c("noteBorderColor", rgba(170, 170, 51))
  result.noteText = c("noteTextColor", rgba(0, 0, 0))
  result.actorBkg = c("actorBkg", result.nodeBkg)
  result.actorBorder = c("actorBorder", result.nodeBorder)
  result.actorText = c("actorTextColor", rgba(0, 0, 0))
  result.actorLine = c("actorLineColor", rgba(153, 153, 153))
  result.signal = c("signalColor", result.lineColor)
  result.signalText = c("signalTextColor", result.textColor)
  result.labelBoxBkg = c("labelBoxBkgColor", result.actorBkg)
  result.labelBoxBorder = c("labelBoxBorderColor", result.actorBorder)
  result.labelText = c("labelTextColor", result.actorText)
  result.loopText = c("loopTextColor", result.actorText)
  result.activationBkg = c("activationBkgColor", rgba(244, 244, 244))
  result.activationBorder = c("activationBorderColor", rgba(102, 102, 102))
  result.seqNumber = c("sequenceNumberColor", rgba(255, 255, 255))
  result.fontFamily = "sans-serif"
  result.fontSize = 16.0
  result.radius = 5.0
  result.strokeWidth = 1.0

proc defaultTheme*(): FlowTheme = themeByName("default")

proc applyOverrides*(theme: var FlowTheme, overrides: Table[string, string]) =
  if "background" in overrides: theme.background = parseColor(overrides["background"])
  if "nodeBkg" in overrides: theme.nodeBkg = parseColor(overrides["nodeBkg"])
  if "mainBkg" in overrides: theme.nodeBkg = parseColor(overrides["mainBkg"])
  if "nodeBorder" in overrides: theme.nodeBorder = parseColor(overrides["nodeBorder"])
  if "border1" in overrides: theme.nodeBorder = parseColor(overrides["border1"])
  if "clusterBkg" in overrides: theme.clusterBkg = parseColor(overrides["clusterBkg"])
  if "secondBkg" in overrides: theme.clusterBkg = parseColor(overrides["secondBkg"])
  if "clusterBorder" in overrides: theme.clusterBorder = parseColor(overrides["clusterBorder"])
  if "border2" in overrides: theme.clusterBorder = parseColor(overrides["border2"])
  if "lineColor" in overrides: theme.lineColor = parseColor(overrides["lineColor"])
  if "arrowheadColor" in overrides: theme.arrowheadColor = parseColor(overrides["arrowheadColor"])
  if "textColor" in overrides: theme.textColor = parseColor(overrides["textColor"])
  if "titleColor" in overrides: theme.titleColor = parseColor(overrides["titleColor"])
  if "edgeLabelBackground" in overrides: theme.edgeLabelBkg = parseColor(overrides["edgeLabelBackground"])
  template ov(key: string, field: untyped) =
    if key in overrides: theme.field = parseColor(overrides[key])
  ov "primaryColor", nodeBkg
  ov "primaryBorderColor", nodeBorder
  ov "tertiaryColor", clusterBkg
  ov "nodeTextColor", nodeText
  ov "noteBkgColor", noteBkg
  ov "noteBorderColor", noteBorder
  ov "noteTextColor", noteText
  ov "actorBkg", actorBkg
  ov "actorBorder", actorBorder
  ov "actorTextColor", actorText
  ov "actorLineColor", actorLine
  ov "signalColor", signal
  ov "signalTextColor", signalText
  ov "labelBoxBkgColor", labelBoxBkg
  ov "labelBoxBorderColor", labelBoxBorder
  ov "labelTextColor", labelText
  ov "loopTextColor", loopText
  ov "activationBkgColor", activationBkg
  ov "activationBorderColor", activationBorder
  ov "sequenceNumberColor", seqNumber
  if "primaryTextColor" in overrides and "nodeTextColor" notin overrides: theme.nodeText = parseColor(overrides["primaryTextColor"])
  if "fontSize" in overrides:
    try:
      let raw = overrides["fontSize"].toLowerAscii.replace("px", "").strip()
      theme.fontSize = parseFloat(raw)
    except ValueError:
      discard
  if "fontFamily" in overrides: theme.fontFamily = overrides["fontFamily"]
  if "radius" in overrides:
    try:
      theme.radius = parseFloat(overrides["radius"].strip())
    except ValueError:
      discard
  if "strokeWidth" in overrides:
    try:
      let raw = overrides["strokeWidth"].toLowerAscii.replace("px", "").strip()
      theme.strokeWidth = parseFloat(raw)
    except ValueError:
      discard
