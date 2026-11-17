import std/tables

type
  BoxSpec* = object
    kind*: string                      ## "class" | "er" | "" (none)
    title*, annotation*: string
    sections*: seq[seq[seq[string]]]   ## section -> rows -> cells

  FlowEdgeStroke* = enum
    fesNormal, fesThick, fesInvisible, fesDotted

  FlowLabelKind* = enum
    flkText, flkString, flkMarkdown

  FlowVertex* = ref object
    id*: string
    text*: string
    hasText*: bool            ## false until a label/id default has been assigned
    shape*: string            ## mermaid `type`: "square", "round", "diamond", ... "" = undefined
    domId*: string
    dir*: string
    hasDir*: bool
    classes*: seq[string]
    styles*: seq[string]
    labelType*: FlowLabelKind
    link*: string
    linkTarget*: string
    tooltip*: string
    props*: Table[string, string]
    icon*, form*, img*, pos*, constraint*: string
    assetWidth*, assetHeight*: float

  FlowEdge* = ref object
    id*: string
    source*: string
    target*: string
    text*: string
    stroke*: FlowEdgeStroke
    kind*: string             ## mermaid edge `type`: arrow_point, arrow_open, double_arrow_cross, ...
    length*: int
    classes*: seq[string]
    styles*: seq[string]
    labelType*: FlowLabelKind
    isUserDefinedId*: bool
    interpolate*: string
    animate*: bool
    hasAnimate*: bool

  FlowClass* = object
    id*: string
    styles*: seq[string]
    textStyles*: seq[string]

  FlowSubGraph* = ref object
    id*: string
    title*: string
    dir*: string
    hasDir*: bool
    nodes*: seq[string]
    classes*: seq[string]
    labelType*: FlowLabelKind
    metadata*: Table[string, string]

  DiagramMetadata* = object
    title*: string
    config*: Table[string, string]
