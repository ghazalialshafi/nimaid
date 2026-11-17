import std/[strutils, options]

type
  FrontMatterMatch* = object
    indent*: string
    body*: string
    length*: int

  FrontMatterResult* = object
    text*: string
    title*: string
    lineOffset*: int

proc isWhitespace(c: char): bool {.inline.} =
  c in {' ', '\t', '\v', '\f', '\r', '\n'}

proc isHorizontalWhitespace(c: char): bool {.inline.} =
  c in {' ', '\t', '\v', '\f'}

proc isLineBreak(c: char): bool {.inline.} =
  c in {'\r', '\n'}

proc stripAnyComments*(text: string): string =
  var outStr = ""
  var consumed = 0
  var searchFrom = 0
  let len = text.len

  while searchFrom < len:
    let marker = text.find("%%", searchFrom)
    if marker == -1:
      break
    let lineEnd = text.find('\n', marker)
    if lineEnd == -1:
      break
    var start = marker
    while start > consumed and isWhitespace(text[start - 1]):
      dec start
    outStr.add text[consumed ..< start]
    outStr.add '\n'
    consumed = lineEnd + 1
    searchFrom = consumed

  outStr.add text[consumed ..< len]
  outStr

proc cleanupComments*(text: string): string =
  var lines = text.splitLines()
  var filtered: seq[string] = @[]
  for line in lines:
    let trimmed = line.strip(leading = true, trailing = false)
    if trimmed.startsWith("%%") and not trimmed.startsWith("%%{"):
      continue
    filtered.add line
  var res = filtered.join("\n")
  res = res.strip(leading = true, trailing = false)
  if text.endsWith("\n") and not res.endsWith("\n"):
    res.add "\n"
  res

proc lastLineBreakInWhitespaceRun(text: string, fromIdx: int): int =
  result = -1
  var i = fromIdx
  while i < text.len and isWhitespace(text[i]):
    if isLineBreak(text[i]):
      result = i
    inc i

proc matchFrontMatter*(text: string): Option[FrontMatterMatch] =
  var cursor = 0
  while cursor < text.len and isHorizontalWhitespace(text[cursor]):
    inc cursor
  let indent = text[0 ..< cursor]

  if not text[cursor .. ^1].startsWith("---"):
    return none(FrontMatterMatch)

  var openingEnds: seq[int] = @[]
  var i = cursor + 3
  while i < text.len and isWhitespace(text[i]):
    if isLineBreak(text[i]):
      openingEnds.add i
    inc i

  if openingEnds.len == 0:
    return none(FrontMatterMatch)

  let closingFence = indent & "---"

  proc closingEnd(pos: int): int =
    if isLineBreak(text[pos]) and text[pos + 1 .. ^1].startsWith(closingFence):
      lastLineBreakInWhitespaceRun(text, pos + 1 + closingFence.len)
    else:
      -1

  let earliestBodyStart = openingEnds[0] + 1
  var lastClosingFence = -1
  for j in earliestBodyStart ..< text.len:
    if closingEnd(j) != -1:
      lastClosingFence = j

  if lastClosingFence == -1:
    return none(FrontMatterMatch)

  var openingEnd = openingEnds[0]
  for candidate in openingEnds:
    if candidate < lastClosingFence:
      openingEnd = candidate

  let bodyStart = openingEnd + 1
  for j in bodyStart .. lastClosingFence:
    let matchEnd = closingEnd(j)
    if matchEnd != -1:
      return some(FrontMatterMatch(
        indent: indent,
        body: text[bodyStart ..< j],
        length: matchEnd + 1
      ))

  none(FrontMatterMatch)

proc extractTitle(body: string): string =
  for line in body.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("title:"):
      var val = trimmed["title:".len .. ^1].strip()
      if (val.startsWith("\"") and val.endsWith("\"")) or (val.startsWith("'") and val.endsWith("'")):
        val = val[1 .. ^2]
      return val
  ""

proc extractFrontMatter*(text: string): FrontMatterResult =
  let matched = matchFrontMatter(text)
  if matched.isNone:
    return FrontMatterResult(text: text, title: "", lineOffset: 0)

  let m = matched.get()
  let title = extractTitle(m.body)
  var lineCount = 0
  for c in text[0 ..< m.length]:
    if c == '\n':
      inc lineCount

  FrontMatterResult(
    text: text[m.length .. ^1],
    title: title,
    lineOffset: lineCount
  )

proc stripDirectives*(text: string): string =
  var res = ""
  var i = 0
  let len = text.len
  while i < len:
    if text[i .. ^1].startsWith("%%{"):
      let endIdx = text.find("}%%", i + 3)
      if endIdx != -1:
        i = endIdx + 3
        continue
    res.add text[i]
    inc i
  res
