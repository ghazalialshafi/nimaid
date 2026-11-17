import std/[strutils, sets]
import geom, label

type
  ClusterKind* = enum
    ckRect,
    ckSquareRect,
    ckRoundedWithTitle,
    ckNoteGroup,
    ckDivider,
    ckKanbanSection,
    ckFlowGroup,
    ckUsecaseSystemBoundary

  ClusterGeometry* = object
    x*, y*, width*, height*: float
    bodyY*, bodyHeight*: float
    tabWidth*, tabHeight*: float
    labelX*, labelY*: float
    diff*: float
    offsetY*: float
    isPackage*: bool
    paintsTitle*: bool
    hasInner*: bool
    innerY*, innerHeight*: float

proc parseClusterKind*(shape: string): ClusterKind =
  case shape
  of "squareRect": ckSquareRect
  of "roundedWithTitle": ckRoundedWithTitle
  of "noteGroup": ckNoteGroup
  of "divider": ckDivider
  of "kanbanSection": ckKanbanSection
  of "flowGroup": ckFlowGroup
  of "usecaseSystemBoundary": ckUsecaseSystemBoundary
  else: ckRect

proc clusterPaintsTitle*(shape: string): bool =
  case shape
  of "noteGroup", "divider": false
  else: true

proc calculateClusterGeometry*(
  shape: string,
  nodeX, nodeY, nodeW, nodeH, padding: float,
  labelW, labelH: float,
  titleTopMargin: float = 8.0,
  boundaryType: string = "rect"
): ClusterGeometry =
  let ck = parseClusterKind(shape)
  result.paintsTitle = clusterPaintsTitle(shape)
  let pad = if padding > 0.0: padding else: 8.0

  case ck
  of ckNoteGroup:
    result.width = nodeW
    result.height = nodeH
    result.x = nodeX - nodeW / 2.0
    result.y = nodeY - nodeH / 2.0
    result.offsetY = 0.0

  of ckDivider:
    result.width = nodeW
    result.height = nodeH
    result.x = nodeX - nodeW / 2.0
    result.y = nodeY - nodeH / 2.0
    result.diff = -pad
    result.offsetY = 0.0

  of ckRoundedWithTitle:
    let minW = labelW + pad
    let w = if nodeW <= minW: minW else: nodeW
    result.width = w
    result.height = nodeH
    result.x = nodeX - w / 2.0
    result.y = nodeY - nodeH / 2.0
    result.diff = if nodeW <= minW: (w - nodeW) / 2.0 - pad else: -pad
    result.hasInner = true
    result.innerHeight = max(0.0, nodeH - labelH - 6.0)
    result.innerY = nodeY - nodeH / 2.0 + labelH + 2.0
    result.labelX = nodeX - labelW / 2.0
    result.labelY = result.y + 1.0
    result.offsetY = labelH - pad / 2.0

  of ckUsecaseSystemBoundary:
    result.isPackage = (boundaryType == "package")
    let hPad = if result.isPackage: 20.0 else: pad
    let tHeight = if result.isPackage: labelH + 10.0 else: 0.0
    let w = max(nodeW, labelW + hPad)
    let h = if result.isPackage: max(nodeH, tHeight + pad * 2.0) else: nodeH
    result.width = w
    result.height = h
    result.x = nodeX - w / 2.0
    result.y = nodeY - h / 2.0
    result.tabHeight = tHeight
    result.tabWidth = if result.isPackage: min(w, max(80.0, labelW + 20.0)) else: 0.0
    result.bodyY = result.y + tHeight
    result.bodyHeight = h - tHeight
    result.diff = if nodeW <= labelW + pad: (w - nodeW) / 2.0 - pad else: -pad
    if result.isPackage:
      result.labelX = result.x + (result.tabWidth - labelW) / 2.0
      result.labelY = result.y + (tHeight - labelH) / 2.0
    else:
      result.labelX = nodeX - labelW / 2.0
      result.labelY = result.y + titleTopMargin
    result.offsetY = labelH - pad / 2.0

  else:
    let minW = labelW + pad
    let w = if nodeW <= minW: minW else: nodeW
    result.width = w
    result.height = nodeH
    result.x = nodeX - w / 2.0
    result.y = nodeY - nodeH / 2.0
    result.diff = if nodeW <= minW: (w - nodeW) / 2.0 - pad else: -pad
    result.labelX = nodeX - labelW / 2.0
    result.labelY = nodeY - nodeH / 2.0 + titleTopMargin
    result.offsetY = labelH - pad / 2.0
