## Port of mermaid's flow.jison: stateful lexer (jison start conditions, first-match-wins rule order)
## followed by a recursive-descent implementation of the grammar.
import std/[strutils, options, tables]
import types, flowdb

type
  TK = enum
    tEof, tNewline, tSpace, tSemi, tAmp, tComma, tColon, tStyleSep, tMult, tBrkt, tNum,
    tNodeString, tMinus, tUnicode, tDown, tUp, tDefault,
    tGraph, tNoDir, tDir, tSubgraph, tEnd, tLinkTarget,
    tDirection,                       # `direction LR` statement (text = LR/TB/...)
    tStyle, tLinkStyle, tInterpolate, tClassDef, tClass,
    tClick, tHref, tCallbackName, tCallbackArgs,
    tAccTitle, tAccTitleValue, tAccDescr, tAccDescrValue, tAccDescrMulti,
    tShapeData, tLinkId, tLink, tStartLink, tEdgeText,
    tStr, tMdStr, tText,
    tSqs, tSqe, tPs, tPe, tDiamondStart, tDiamondStop, tPipe, tTagStart, tTagEnd,
    tStadiumStart, tStadiumEnd, tSubStart, tSubEnd, tCylStart, tCylEnd,
    tDblStart, tDblEnd, tEllStart, tEllEnd,
    tTrapStart, tTrapEnd, tInvTrapStart, tInvTrapEnd, tPropsStart

  Tok = object
    kind: TK
    text: string

  LState = enum
    lsInitial, lsString, lsMdString, lsAccTitle, lsAccDescr, lsAccDescrMulti, lsDir, lsText,
    lsEllipse, lsTrap, lsEdge, lsThickEdge, lsDottedEdge, lsClick, lsCallbackName,
    lsCallbackArgs, lsShapeData, lsShapeDataStr

  Lexer = object
    src: string
    pos: int
    states: seq[LState]
    db: FlowDB

  ParseError* = object of CatchableError

proc fail(msg: string) {.noreturn.} = raise newException(ParseError, msg)

# ---------------------------------------------------------------------------
# lexer helpers
# ---------------------------------------------------------------------------
template cur(L: Lexer): LState = L.states[^1]
proc pushState(L: var Lexer, s: LState) = L.states.add s
proc popState(L: var Lexer) = (if L.states.len > 1: L.states.setLen(L.states.len - 1))

proc at(L: Lexer, i: int): char = (if i < L.src.len: L.src[i] else: '\0')
proc starts(L: Lexer, s: string, p = -1): bool =
  let p = if p < 0: L.pos else: p
  p + s.len <= L.src.len and L.src.substr(p, p + s.len - 1) == s

proc isWs(c: char): bool = c in {' ', '\t', '\n', '\r', '\v', '\f'}
proc isHSpace(c: char): bool = c in {' ', '\t', '\v', '\f'}
proc isWordChar(c: char): bool = c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc skipWs(L: Lexer, p: int): int =
  result = p
  while result < L.src.len and isWs(L.src[result]): inc result

proc utf8Len(c: char): int =
  let b = ord(c)
  if b < 0x80: 1 elif b >= 0xF0: 4 elif b >= 0xE0: 3 elif b >= 0xC0: 2 else: 1

const nodeStringChars = {'A'..'Z', 'a'..'z', '0'..'9', '!', '"', '#', '$', '%', '&', '\'', '*', '+',
                         '.', '`', '?', '\\', '_', '/'}

proc matchNodeString(L: Lexer): int =
  var i = L.pos
  while i < L.src.len:
    let c = L.src[i]
    if c in nodeStringChars: inc i
    elif c == '-' and i + 1 < L.src.len and L.src[i + 1] notin {'>', '-', '.'}: inc i
    elif c == '=' and L.at(i + 1) != '=': inc i
    else: break
  i - L.pos

proc matchLinkId(L: Lexer): int =
  ## [^\s"\[\]\(\)\{\}\|]+\@(?=[^\{"])
  var e = L.pos
  while e < L.src.len and L.src[e] notin {' ', '\t', '\n', '\r', '\v', '\f', '"', '[', ']', '(', ')', '{', '}', '|'}:
    inc e
  var k = e - 1
  while k > L.pos:
    if L.src[k] == '@' and k + 1 < L.src.len and L.src[k + 1] notin {'{', '"'}:
      return k + 1 - L.pos
    dec k
  0

proc matchLinkRun(L: Lexer, c: char): int =
  ## \s*[xo<]?cc+[c xo>]\s*      (c is '-' or '=')
  var i = L.skipWs(L.pos)
  if L.at(i) in {'x', 'o', '<'}: inc i
  var d = 0
  while L.at(i) == c:
    inc i
    inc d
  if d < 2: return 0
  if L.at(i) in {'x', 'o', '>'}: inc i
  elif d < 3: return 0
  i = L.skipWs(i)
  i - L.pos

proc matchStartLink(L: Lexer, c: char): int =
  ## \s*[xo<]?cc\s*
  var i = L.skipWs(L.pos)
  if L.at(i) in {'x', 'o', '<'}: inc i
  if L.at(i) == c and L.at(i + 1) == c:
    i += 2
    return L.skipWs(i) - L.pos
  0

proc matchDottedLink(L: Lexer): int =
  ## \s*[xo<]?\-?\.+\-[xo>]?\s*
  var i = L.skipWs(L.pos)
  if L.at(i) in {'x', 'o', '<'}: inc i
  if L.at(i) == '-': inc i
  var dots = 0
  while L.at(i) == '.':
    inc i
    inc dots
  if dots == 0 or L.at(i) != '-': return 0
  inc i
  if L.at(i) in {'x', 'o', '>'}: inc i
  L.skipWs(i) - L.pos

proc matchStartDotted(L: Lexer): int =
  var i = L.skipWs(L.pos)
  if L.at(i) in {'x', 'o', '<'}: inc i
  if L.at(i) == '-' and L.at(i + 1) == '.':
    i += 2
    return L.skipWs(i) - L.pos
  0

proc matchTildeLink(L: Lexer): int =
  var i = L.skipWs(L.pos)
  var n = 0
  while L.at(i) == '~':
    inc i
    inc n
  if n < 3: return 0
  L.skipWs(i) - L.pos

proc matchDirectionStmt(L: Lexer): (int, string) =
  ## .*direction\s+(TB|BT|RL|LR|TD)[^\n]*   (rules tried in file order)
  var eol = L.pos
  while eol < L.src.len and L.src[eol] != '\n': inc eol
  for name in ["TB", "BT", "RL", "LR", "TD"]:
    var best = -1
    var k = L.pos
    while true:
      let f = L.src.find("direction", k)
      if f < 0 or f >= eol: break
      var j = f + 9
      var ws = 0
      while j < eol and isWs(L.src[j]):
        inc j
        inc ws
      if ws > 0 and L.src.substr(j, j + 1) == name: best = f
      k = f + 1
    if best >= 0: return (eol - L.pos, name)
  (0, "")

# ---------------------------------------------------------------------------
# lexer: one token
# ---------------------------------------------------------------------------
proc nextTok(L: var Lexer): Tok =
  template emit(k: TK, n: int) =
    let t = L.src.substr(L.pos, L.pos + n - 1)
    L.pos += n
    return Tok(kind: k, text: t)
  template emitText(k: TK, n: int, txt: string) =
    L.pos += n
    return Tok(kind: k, text: txt)

  while true:
    if L.pos >= L.src.len: return Tok(kind: tEof)
    let st = L.cur
    let c = L.src[L.pos]
    let init = st == lsInitial

    # --- accTitle / accDescr ------------------------------------------------
    if init and L.starts("accTitle"):
      var i = L.skipWs(L.pos + 8)
      if L.at(i) == ':':
        i = L.skipWs(i + 1)
        let n = i - L.pos
        L.pos = i
        L.pushState lsAccTitle
        return Tok(kind: tAccTitle, text: "accTitle")
    if st == lsAccTitle:
      var e = L.pos
      while e < L.src.len and L.src[e] != '\n': inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      L.popState()
      return Tok(kind: tAccTitleValue, text: v)
    if init and L.starts("accDescr"):
      var i = L.skipWs(L.pos + 8)
      if L.at(i) == ':':
        L.pos = L.skipWs(i + 1)
        L.pushState lsAccDescr
        return Tok(kind: tAccDescr, text: "accDescr")
      elif L.at(i) == '{':
        L.pos = L.skipWs(i + 1)
        L.pushState lsAccDescrMulti
        continue
    if st == lsAccDescr:
      var e = L.pos
      while e < L.src.len and L.src[e] != '\n': inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      L.popState()
      return Tok(kind: tAccDescrValue, text: v)
    if st == lsAccDescrMulti:
      if c == '}':
        inc L.pos
        L.popState()
        continue
      var e = L.pos
      while e < L.src.len and L.src[e] != '}': inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      return Tok(kind: tAccDescrMulti, text: v)

    # --- shape data  @{ ... } ---------------------------------------------
    if init and L.starts("@{"):
      L.pos += 2
      L.pushState lsShapeData
      return Tok(kind: tShapeData, text: "")
    if st == lsShapeData:
      if c == '"':
        inc L.pos
        L.pushState lsShapeDataStr
        return Tok(kind: tShapeData, text: "\"")
      if c == '}':
        inc L.pos
        L.popState()
        continue
      var e = L.pos
      while e < L.src.len and L.src[e] notin {'}', '^', '"'}: inc e
      if e > L.pos:
        let v = L.src.substr(L.pos, e - 1)
        L.pos = e
        return Tok(kind: tShapeData, text: v)
      fail("Lexical error: unexpected '" & $c & "' in shape data")
    if st == lsShapeDataStr:
      if c == '"':
        inc L.pos
        L.popState()
        return Tok(kind: tShapeData, text: "\"")
      var e = L.pos
      while e < L.src.len and L.src[e] != '"': inc e
      var v = L.src.substr(L.pos, e - 1)
      L.pos = e
      # replace /\n\s*/ with <br/>
      var o = ""
      var i = 0
      while i < v.len:
        if v[i] == '\n':
          o.add "<br/>"
          inc i
          while i < v.len and isWs(v[i]): inc i
        else:
          o.add v[i]
          inc i
      return Tok(kind: tShapeData, text: o)

    # --- call / callback ------------------------------------------------------
    if init and L.starts("call") and isWs(L.at(L.pos + 4)):
      L.pos = L.skipWs(L.pos + 4)
      L.pushState lsCallbackName
      continue
    if st == lsCallbackName:
      if c == '(':
        let close = L.skipWs(L.pos + 1)
        if L.at(close) == ')':
          L.pos = close + 1
          L.popState()
          continue
        inc L.pos
        L.popState()
        L.pushState lsCallbackArgs
        continue
      var e = L.pos
      while e < L.src.len and L.src[e] != '(': inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      return Tok(kind: tCallbackName, text: v)
    if st == lsCallbackArgs:
      if c == ')':
        inc L.pos
        L.popState()
        continue
      var e = L.pos
      while e < L.src.len and L.src[e] != ')': inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      return Tok(kind: tCallbackArgs, text: v)

    # --- strings --------------------------------------------------------------
    if st == lsMdString:
      if c == '`' and L.at(L.pos + 1) == '"':
        L.pos += 2
        L.popState()
        continue
      var e = L.pos
      while e < L.src.len and L.src[e] notin {'`', '"'}: inc e
      if e > L.pos:
        let v = L.src.substr(L.pos, e - 1)
        L.pos = e
        return Tok(kind: tMdStr, text: v)
    if c == '"' and L.at(L.pos + 1) == '`' and st != lsString:
      L.pos += 2
      L.pushState lsMdString
      continue
    if st == lsString:
      if c == '"':
        inc L.pos
        L.popState()
        continue
      var e = L.pos
      while e < L.src.len and L.src[e] != '"': inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      return Tok(kind: tStr, text: v)
    if c == '"':
      inc L.pos
      L.pushState lsString
      continue

    # --- keywords -------------------------------------------------------------
    if init:
      if L.starts("style"): emit(tStyle, 5)
      if L.starts("default"): emit(tDefault, 7)
      if L.starts("linkStyle"): emit(tLinkStyle, 9)
      if L.starts("interpolate"): emit(tInterpolate, 11)
      if L.starts("classDef"): emit(tClassDef, 8)
      if L.starts("class"): emit(tClass, 5)
      if L.starts("href") and isWs(L.at(L.pos + 4)): emit(tHref, 5)
      if L.starts("click") and isWs(L.at(L.pos + 5)):
        L.pos = L.skipWs(L.pos + 5)
        L.pushState lsClick
        continue
    if st == lsClick:
      if isWs(c):
        inc L.pos
        L.popState()
        continue
      var e = L.pos
      while e < L.src.len and not isWs(L.src[e]): inc e
      let v = L.src.substr(L.pos, e - 1)
      L.pos = e
      return Tok(kind: tClick, text: v)

    if init:
      for kw in ["flowchart-elk", "swimlane-beta", "graph", "flowchart"]:
        if L.starts(kw):
          L.pos += kw.len
          if L.db.firstGraph(): L.pushState lsDir
          return Tok(kind: tGraph, text: kw)
      if L.starts("subgraph"): emit(tSubgraph, 8)
      if L.starts("end") and not isWordChar(L.at(L.pos + 3)):
        let e = L.skipWs(L.pos + 3)
        emitText(tEnd, e - L.pos, "end")
      for kw in ["_self", "_blank", "_parent", "_top"]:
        if L.starts(kw): emit(tLinkTarget, kw.len)

    # --- direction state ---------------------------------------------------------
    if st == lsDir:
      var e = L.pos
      while e < L.src.len and isWs(L.src[e]): inc e
      var lastNl = -1
      for k in L.pos ..< e:
        if L.src[k] == '\n': lastNl = k
      if lastNl >= 0:
        L.pos = lastNl + 1
        L.popState()
        return Tok(kind: tNoDir, text: "")
      for d in ["LR", "RL", "TB", "BT", "TD", "BR", "<", ">", "^", "v"]:
        if L.starts(d, e):
          let txt = L.src.substr(L.pos, e + d.len - 1)
          L.pos = e + d.len
          L.popState()
          return Tok(kind: tDir, text: txt)
      L.popState()      # lenient: no direction given
      continue

    if init:
      let (n, nm) = L.matchDirectionStmt()
      if n > 0:
        L.pos += n
        return Tok(kind: tDirection, text: nm)
      let n2 = L.matchLinkId()
      if n2 > 0: emit(tLinkId, n2)
      if c in {'0'..'9'}:
        var e = L.pos
        while e < L.src.len and L.src[e] in {'0'..'9'}: inc e
        emit(tNum, e - L.pos)
      if c == '#': emit(tBrkt, 1)
      if L.starts(":::"): emit(tStyleSep, 3)
      if c == ':': emit(tColon, 1)
      if c == '&': emit(tAmp, 1)
      if c == ';': emit(tSemi, 1)
      if c == ',': emit(tComma, 1)
      if c == '*': emit(tMult, 1)

    # --- links ------------------------------------------------------------------
    if init or st == lsEdge:
      let n = L.matchLinkRun('-')
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        L.popState()
        return Tok(kind: tLink, text: t)
    if init:
      let n = L.matchStartLink('-')
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        L.pushState lsEdge
        return Tok(kind: tStartLink, text: t)
    if st == lsEdge:
      if c != '-': (let n = utf8Len(c); emit(tEdgeText, n))
      elif L.at(L.pos + 1) != '-': emit(tEdgeText, 1)
    if init or st == lsThickEdge:
      let n = L.matchLinkRun('=')
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        L.popState()
        return Tok(kind: tLink, text: t)
    if init:
      let n = L.matchStartLink('=')
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        L.pushState lsThickEdge
        return Tok(kind: tStartLink, text: t)
    if st == lsThickEdge:
      if c != '=': (let n = utf8Len(c); emit(tEdgeText, n))
      elif L.at(L.pos + 1) != '=': emit(tEdgeText, 1)
    if init or st == lsDottedEdge:
      let n = L.matchDottedLink()
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        L.popState()
        return Tok(kind: tLink, text: t)
    if init:
      let n = L.matchStartDotted()
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        L.pushState lsDottedEdge
        return Tok(kind: tStartLink, text: t)
    if st == lsDottedEdge:
      if c != '.': (let n = utf8Len(c); emit(tEdgeText, n))
      elif L.at(L.pos + 1) != '-': emit(tEdgeText, 1)
    block tilde:
      let n = L.matchTildeLink()
      if n > 0:
        let t = L.src.substr(L.pos, L.pos + n - 1)
        L.pos += n
        return Tok(kind: tLink, text: t)

    # --- shapes ---------------------------------------------------------------------
    if st == lsEllipse:
      if c in {'-', '/', ')'} and L.at(L.pos + 1) == ')':
        L.pos += 2
        L.popState()
        return Tok(kind: tEllEnd, text: "-)")
      if c notin {'(', ')', '[', ']', '{', '}'}: (let n = utf8Len(c); emit(tText, n))
    if L.starts("(-"):
      L.pos += 2
      L.pushState lsEllipse
      return Tok(kind: tEllStart, text: "(-")
    if st == lsText and L.starts("])"):
      L.pos += 2
      L.popState()
      return Tok(kind: tStadiumEnd, text: "])")
    if L.starts("(["):
      L.pos += 2
      L.pushState lsText
      return Tok(kind: tStadiumStart, text: "([")
    if st == lsText and L.starts("]]"):
      L.pos += 2
      L.popState()
      return Tok(kind: tSubEnd, text: "]]")
    if L.starts("[["):
      L.pos += 2
      L.pushState lsText
      return Tok(kind: tSubStart, text: "[[")
    if init and L.starts("[|"): emit(tPropsStart, 2)
    if init and c == '>':
      inc L.pos
      L.pushState lsText
      return Tok(kind: tTagEnd, text: ">")
    if st == lsText and L.starts(")]"):
      L.pos += 2
      L.popState()
      return Tok(kind: tCylEnd, text: ")]")
    if L.starts("[("):
      L.pos += 2
      L.pushState lsText
      return Tok(kind: tCylStart, text: "[(")
    if st == lsText and L.starts(")))"):
      L.pos += 3
      L.popState()
      return Tok(kind: tDblEnd, text: ")))")
    if L.starts("((("):
      L.pos += 3
      L.pushState lsText
      return Tok(kind: tDblStart, text: "(((")
    if st == lsTrap:
      if c in {'\\', '(', '?', '=', ']', ')'} and L.at(L.pos + 1) == ']':
        L.pos += 2
        L.popState()
        return Tok(kind: tTrapEnd, text: "\\]")
      if c == '/' and L.at(L.pos + 1) == ']':
        L.pos += 2
        L.popState()
        return Tok(kind: tInvTrapEnd, text: "/]")
      if c == '/' or c == '\\': emit(tText, 1)
      var e = L.pos
      while e < L.src.len and L.src[e] notin {'\\', '[', ']', '(', ')', '{', '}', '/'}: inc e
      if e > L.pos: emit(tText, e - L.pos)
    if L.starts("[/"):
      L.pos += 2
      L.pushState lsTrap
      return Tok(kind: tTrapStart, text: "[/")
    if L.starts("[\\"):
      L.pos += 2
      L.pushState lsTrap
      return Tok(kind: tInvTrapStart, text: "[\\")

    if init:
      if c == '<': emit(tTagStart, 1)
      if c == '^': emit(tUp, 1)
      if c == 'v': emit(tDown, 1)
      let n = L.matchNodeString()
      if n > 0: emit(tNodeString, n)
      if c == '-': emit(tMinus, 1)
      if ord(c) >= 0x80: emit(tUnicode, utf8Len(c))

    if st == lsText and c == '|':
      inc L.pos
      L.popState()
      return Tok(kind: tPipe, text: "|")
    if c == '|':
      inc L.pos
      L.pushState lsText
      return Tok(kind: tPipe, text: "|")
    if st == lsText and c == ')':
      inc L.pos
      L.popState()
      return Tok(kind: tPe, text: ")")
    if c == '(':
      inc L.pos
      L.pushState lsText
      return Tok(kind: tPs, text: "(")
    if st == lsText and c == ']':
      inc L.pos
      L.popState()
      return Tok(kind: tSqe, text: "]")
    if c == '[':
      inc L.pos
      L.pushState lsText
      return Tok(kind: tSqs, text: "[")
    if st == lsText and c == '}':
      inc L.pos
      L.popState()
      return Tok(kind: tDiamondStop, text: "}")
    if c == '{':
      inc L.pos
      L.pushState lsText
      return Tok(kind: tDiamondStart, text: "{")
    if st == lsText:
      var e = L.pos
      while e < L.src.len and L.src[e] notin {'[', ']', '(', ')', '{', '}', '|', '"'}: inc e
      if e > L.pos: emit(tText, e - L.pos)

    if init:
      if c == '\n':
        var e = L.pos
        while e < L.src.len and L.src[e] == '\n': inc e
        emit(tNewline, e - L.pos)
      if isHSpace(c):
        var e = L.pos
        while e < L.src.len and isHSpace(L.src[e]): inc e
        emit(tSpace, e - L.pos)

    # line number for error message
    var line = 1
    for k in 0 ..< L.pos:
      if L.src[k] == '\n': inc line
    fail("Lexical error on line " & $line & ": unrecognized text '" & L.src.substr(L.pos, min(L.src.len - 1, L.pos + 10)).splitLines()[0] & "'")

# ---------------------------------------------------------------------------
# parser
# ---------------------------------------------------------------------------
type
  Parser = object
    toks: seq[Tok]
    i: int
    db: FlowDB

  TextObj = object
    text: string
    kind: FlowLabelKind

template kind(P: Parser): TK = P.toks[P.i].kind
template text(P: Parser): string = P.toks[P.i].text
proc peekKind(P: Parser, k: int): TK = (if P.i + k < P.toks.len: P.toks[P.i + k].kind else: tEof)
proc advance(P: var Parser) = (if P.i < P.toks.len - 1: inc P.i)

proc expect(P: var Parser, k: TK, what: string) =
  if P.kind != k: fail("Parse error: expecting " & what & ", got " & $P.kind)
  P.advance()

const
  idStringTokens = {tNum, tNodeString, tDown, tMinus, tDefault, tComma, tColon, tAmp, tBrkt, tMult, tUnicode}
  styleComponents = {tNum, tNodeString, tColon, tSpace, tBrkt, tStyle}
  keywordTokens = {tStyle, tLinkStyle, tClassDef, tClass, tClick, tGraph, tDir, tSubgraph, tEnd, tDown, tUp}
  textNoTagsTokens = {tNum, tNodeString, tSpace, tMinus, tAmp, tUnicode, tColon, tMult, tBrkt,
                      tStartLink} + keywordTokens
  alphaNumTokens = {tNum, tUnicode, tNodeString, tDir, tDown, tMinus, tComma, tColon, tAmp, tBrkt, tMult}

proc parseIdString(P: var Parser): string =
  if P.kind notin idStringTokens: fail("Parse error: expecting node id, got " & $P.kind)
  while P.kind in idStringTokens:
    result.add P.text
    P.advance()

proc parseAlphaNum(P: var Parser): string =
  if P.kind notin alphaNumTokens: fail("Parse error: expecting identifier, got " & $P.kind)
  while P.kind in alphaNumTokens:
    result.add P.text
    P.advance()

proc skipSpaces(P: var Parser): bool =
  while P.kind == tSpace:
    result = true
    P.advance()

proc parseText(P: var Parser): TextObj =
  case P.kind
  of tStr:
    result = TextObj(text: P.text, kind: flkString)
    P.advance()
  of tMdStr:
    result = TextObj(text: P.text, kind: flkMarkdown)
    P.advance()
  of tText, tTagStart, tTagEnd, tUnicode:
    result.kind = flkText
    while P.kind in {tText, tTagStart, tTagEnd, tUnicode}:
      result.text.add P.text
      P.advance()
  else: fail("Parse error: expecting text, got " & $P.kind)

proc parseEdgeText(P: var Parser): TextObj =
  case P.kind
  of tStr:
    result = TextObj(text: P.text, kind: flkString)
    P.advance()
  of tMdStr:
    result = TextObj(text: P.text, kind: flkMarkdown)
    P.advance()
  of tEdgeText, tUnicode:
    result.kind = flkText
    while P.kind in {tEdgeText, tUnicode}:
      result.text.add P.text
      P.advance()
  else: fail("Parse error: expecting edge text, got " & $P.kind)

proc parseTextNoTags(P: var Parser): TextObj =
  case P.kind
  of tStr:
    result = TextObj(text: P.text, kind: flkText)
    P.advance()
  of tMdStr:
    result = TextObj(text: P.text, kind: flkMarkdown)
    P.advance()
  else:
    if P.kind notin textNoTagsTokens: fail("Parse error: expecting subgraph title, got " & $P.kind)
    result.kind = flkText
    while P.kind in textNoTagsTokens:
      result.text.add P.text
      P.advance()

proc fto(t: TextObj): Option[FlowTextObj] = some(FlowTextObj(text: t.text, kind: t.kind))

proc parseVertex(P: var Parser): string =
  let id = P.parseIdString()
  result = id
  let db = P.db
  case P.kind
  of tSqs:
    P.advance()
    let t = P.parseText()
    P.expect(tSqe, "']'")
    db.addVertex(id, fto(t), "square")
  of tDblStart:
    P.advance()
    let t = P.parseText()
    P.expect(tDblEnd, "')))'")
    db.addVertex(id, fto(t), "doublecircle")
  of tPs:
    P.advance()
    if P.kind == tPs:
      P.advance()
      let t = P.parseText()
      P.expect(tPe, "')'")
      P.expect(tPe, "')'")
      db.addVertex(id, fto(t), "circle")
    else:
      let t = P.parseText()
      P.expect(tPe, "')'")
      db.addVertex(id, fto(t), "round")
  of tEllStart:
    P.advance()
    let t = P.parseText()
    P.expect(tEllEnd, "'-)'")
    db.addVertex(id, fto(t), "ellipse")
  of tStadiumStart:
    P.advance()
    let t = P.parseText()
    P.expect(tStadiumEnd, "'])'")
    db.addVertex(id, fto(t), "stadium")
  of tSubStart:
    P.advance()
    let t = P.parseText()
    P.expect(tSubEnd, "']]'")
    db.addVertex(id, fto(t), "subroutine")
  of tPropsStart:
    P.advance()
    if P.kind != tNodeString: fail("Parse error: expecting property name")
    let field = P.text
    P.advance()
    P.expect(tColon, "':'")
    if P.kind != tNodeString: fail("Parse error: expecting property value")
    let value = P.text
    P.advance()
    P.expect(tPipe, "'|'")
    let t = P.parseText()
    P.expect(tSqe, "']'")
    var props = initTable[string, string]()
    props[field] = value
    db.addVertex(id, fto(t), "rect", props = props)
  of tCylStart:
    P.advance()
    let t = P.parseText()
    P.expect(tCylEnd, "')]'")
    db.addVertex(id, fto(t), "cylinder")
  of tDiamondStart:
    P.advance()
    if P.kind == tDiamondStart:
      P.advance()
      let t = P.parseText()
      P.expect(tDiamondStop, "'}'")
      P.expect(tDiamondStop, "'}'")
      db.addVertex(id, fto(t), "hexagon")
    else:
      let t = P.parseText()
      P.expect(tDiamondStop, "'}'")
      db.addVertex(id, fto(t), "diamond")
  of tTagEnd:
    P.advance()
    let t = P.parseText()
    P.expect(tSqe, "']'")
    db.addVertex(id, fto(t), "odd")
  of tTrapStart, tInvTrapStart:
    let startK = P.kind
    P.advance()
    let t = P.parseText()
    let endK = P.kind
    if endK notin {tTrapEnd, tInvTrapEnd}: fail("Parse error: expecting trapezoid end, got " & $endK)
    P.advance()
    let shape =
      if startK == tTrapStart and endK == tTrapEnd: "trapezoid"
      elif startK == tInvTrapStart and endK == tInvTrapEnd: "inv_trapezoid"
      elif startK == tTrapStart: "lean_right"
      else: "lean_left"
    db.addVertex(id, fto(t), shape)
  else:
    db.addVertex(id)

proc parseStyledVertex(P: var Parser): string =
  result = P.parseVertex()
  if P.kind == tStyleSep:
    P.advance()
    let cls = P.parseIdString()
    P.db.setClass(result, cls)

proc collectShapeData(P: var Parser): string =
  while P.kind == tShapeData:
    result.add P.text
    P.advance()

proc parseNode(P: var Parser): seq[string] =
  result = @[P.parseStyledVertex()]
  while true:
    let save = P.i
    var sd = ""
    var hasSd = false
    if P.kind == tShapeData:
      sd = P.collectShapeData()
      hasSd = true
    let hadSp = P.skipSpaces()
    if P.kind == tAmp and (hadSp or hasSd or true):
      # `node [shapeData] spaceList AMP spaceList styledVertex`
      if not hadSp:
        P.i = save
        break
      P.advance()
      if not P.skipSpaces():
        P.i = save
        break
      if P.kind notin idStringTokens:
        P.i = save
        break
      if hasSd:
        P.db.addVertex(result[^1], metadata = some(sd))
      result.add P.parseStyledVertex()
    else:
      P.i = save
      break

proc parseLink(P: var Parser): FlowLinkInfo =
  var linkId = ""
  if P.kind == tLinkId:
    linkId = P.text
    P.advance()
  if P.kind == tStartLink:
    let startStr = P.text
    P.advance()
    let et = P.parseEdgeText()
    if P.kind != tLink: fail("Parse error: expecting link end, got " & $P.kind)
    let endStr = P.text
    P.advance()
    result = destructLink(endStr, startStr)
    result.hasText = true
    result.text = FlowTextObj(text: et.text, kind: et.kind)
  elif P.kind == tLink:
    result = destructLink(P.text)
    P.advance()
    if P.kind == tPipe:
      P.advance()
      let t = P.parseText()
      P.expect(tPipe, "'|'")
      result.hasText = true
      result.text = FlowTextObj(text: t.text, kind: t.kind)
      if P.kind == tSpace: P.advance()
  else:
    fail("Parse error: expecting link, got " & $P.kind)
  result.id = linkId

proc parseVertexStatement(P: var Parser): seq[string] =
  var stmt = P.parseNode()
  var all = stmt
  var first = true
  while true:
    if P.kind == tShapeData:
      let sd = P.collectShapeData()
      P.db.addVertex(stmt[^1], metadata = some(sd))
    discard P.skipSpaces()
    if P.kind in {tLink, tLinkId, tStartLink}:
      let link = P.parseLink()
      let n2 = P.parseNode()
      if P.kind == tShapeData:
        let sd = P.collectShapeData()
        P.db.addVertex(n2[^1], metadata = some(sd))
      discard P.skipSpaces()
      P.db.addLink(stmt, n2, link)
      all = n2 & all
      stmt = n2
      first = false
    else:
      break
  all

proc parseStyles(P: var Parser): seq[string] =
  ## stylesOpt: style (COMMA style)* ; style: styleComponent+
  while true:
    if P.kind notin styleComponents: fail("Parse error: expecting style, got " & $P.kind)
    var s = ""
    while P.kind in styleComponents:
      s.add P.text
      P.advance()
    result.add s
    if P.kind == tComma: P.advance()
    else: break

proc atSeparator(P: Parser): bool = P.kind in {tNewline, tSemi, tEof}

proc endStatement(P: var Parser) =
  if P.kind in {tNewline, tSemi}: P.advance()
  elif P.kind == tEof: discard
  else: fail("Parse error: expecting separator, got " & $P.kind & " '" & P.text & "'")

proc parseDocument(P: var Parser, inSubgraph: bool): seq[DocItem]

proc parseStatement(P: var Parser, items: var seq[DocItem]) =
  case P.kind
  of tStyle:
    P.advance()
    P.expect(tSpace, "space")
    let id = P.parseIdString()
    P.expect(tSpace, "space")
    let st = P.parseStyles()
    P.endStatement()
    P.db.addVertex(id, style = st, hasStyle = true)
  of tLinkStyle:
    P.advance()
    P.expect(tSpace, "space")
    var positions: seq[string]
    if P.kind == tDefault:
      positions = @["default"]
      P.advance()
    elif P.kind == tNum:
      positions.add P.text
      P.advance()
      while P.kind == tComma:
        P.advance()
        if P.kind != tNum: fail("Parse error: expecting number")
        positions.add P.text
        P.advance()
    else: fail("Parse error: expecting 'default' or link numbers")
    var hasInterp = false
    var interp = ""
    var styles: seq[string]
    var hasStyles = false
    if P.kind == tSpace:
      P.advance()
      if P.kind == tInterpolate:
        P.advance()
        P.expect(tSpace, "space")
        interp = P.parseAlphaNum()
        hasInterp = true
        if P.kind == tSpace:
          P.advance()
          styles = P.parseStyles()
          hasStyles = true
      else:
        styles = P.parseStyles()
        hasStyles = true
    P.endStatement()
    if hasInterp: P.db.updateLinkInterpolate(positions, interp)
    if hasStyles: P.db.updateLink(positions, styles)
  of tClassDef:
    P.advance()
    P.expect(tSpace, "space")
    let id = P.parseIdString()
    P.expect(tSpace, "space")
    let st = P.parseStyles()
    P.endStatement()
    P.db.addClass(id, st)
  of tClass:
    P.advance()
    P.expect(tSpace, "space")
    let v = P.parseIdString()
    P.expect(tSpace, "space")
    let c = P.parseIdString()
    P.endStatement()
    P.db.setClass(v, c)
  of tClick:
    let id = P.text
    P.advance()
    case P.kind
    of tCallbackName:
      let fn = P.text
      P.advance()
      var args = ""
      if P.kind == tCallbackArgs:
        args = P.text
        P.advance()
      P.db.setClickEvent(id, fn, args)
      if P.kind == tSpace and P.peekKind(1) == tStr:
        P.advance()
        P.db.setTooltip(id, P.text)
        P.advance()
    of tHref, tStr:
      if P.kind == tHref: P.advance()
      if P.kind != tStr: fail("Parse error: expecting link string")
      let link = P.text
      P.advance()
      var tooltip = ""
      var hasTip = false
      var target = ""
      if P.kind == tSpace and P.peekKind(1) == tStr:
        P.advance()
        tooltip = P.text
        hasTip = true
        P.advance()
      if P.kind == tSpace and P.peekKind(1) == tLinkTarget:
        P.advance()
        target = P.text
        P.advance()
      P.db.setLink(id, link, target)
      if hasTip: P.db.setTooltip(id, tooltip)
    else:
      let fn = P.parseAlphaNum()
      P.db.setClickEvent(id, fn)
      if P.kind == tSpace and P.peekKind(1) == tStr:
        P.advance()
        P.db.setTooltip(id, P.text)
        P.advance()
    P.endStatement()
  of tSubgraph:
    P.advance()
    var idText = ""
    var title: TextObj
    var idIsTitle = false
    var hasId = false
    if P.kind == tSpace:
      P.advance()
      let tnt = P.parseTextNoTags()
      if P.kind == tSqs:
        P.advance()
        title = P.parseText()
        P.expect(tSqe, "']'")
        idText = tnt.text
        hasId = true
      else:
        idText = tnt.text
        title = tnt
        idIsTitle = true
        hasId = true
    P.endStatement()
    let body = P.parseDocument(true)
    if P.kind != tEnd: fail("Parse error: expecting 'end', got " & $P.kind)
    P.advance()
    let id = P.db.addSubGraph(if hasId: idText else: "", body, title.text, title.kind, idIsTitle)
    items.add DocItem(kind: dikNode, text: id)
  of tDirection:
    items.add DocItem(kind: dikDir, text: P.text)
    P.advance()
  of tAccTitle:
    P.advance()
    if P.kind != tAccTitleValue: fail("Parse error: expecting accTitle value")
    P.db.setAccTitle(P.text.strip())
    P.advance()
  of tAccDescr:
    P.advance()
    if P.kind != tAccDescrValue: fail("Parse error: expecting accDescr value")
    P.db.setAccDescription(P.text.strip())
    P.advance()
  of tAccDescrMulti:
    P.db.setAccDescription(P.text.strip())
    P.advance()
  else:
    let nodes = P.parseVertexStatement()
    P.endStatement()
    for n in nodes: items.add DocItem(kind: dikNode, text: n)

proc parseDocument(P: var Parser, inSubgraph: bool): seq[DocItem] =
  while true:
    case P.kind
    of tEof:
      if inSubgraph: fail("Parse error: missing 'end' for subgraph")
      return
    of tEnd:
      if inSubgraph: return
      fail("Parse error: unexpected 'end'")
    of tSemi, tNewline, tSpace: P.advance()
    else: P.parseStatement(result)

proc tokenize(src: string, db: FlowDB): seq[Tok] =
  var L = Lexer(src: src, pos: 0, states: @[lsInitial], db: db)
  while true:
    let t = L.nextTok()
    result.add t
    if t.kind == tEof: break

proc parseFlowchart*(textIn: string, db: FlowDB) =
  var text = textIn.replace("\r\n", "\n").replace('\r', '\n')
  let stripped = text.strip(trailing = false)
  if stripped.startsWith("flowchart-v2"):
    text = "flowchart" & stripped[12 .. ^1]
  var P = Parser(toks: tokenize(text, db), db: db)
  # graphConfig: (SPACE|NEWLINE)* GRAPH ( NODIR | DIR FirstStmtSeparator )
  while P.kind in {tSpace, tNewline}: P.advance()
  if P.kind != tGraph: fail("Parse error: expecting 'graph' or 'flowchart', got " & $P.kind)
  P.advance()
  case P.kind
  of tNoDir:
    db.setDirection("TB")
    P.advance()
  of tDir:
    db.setDirection(P.text)
    P.advance()
    if P.kind == tSemi or P.kind == tNewline: P.advance()
    elif P.kind == tSpace and P.peekKind(1) == tNewline:
      P.advance()
      P.advance()
    elif P.kind != tEof:
      fail("Parse error: expecting newline after direction, got " & $P.kind)
  else:
    db.setDirection("TB")
  discard P.parseDocument(false)
