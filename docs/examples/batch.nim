## Convert every .mmd file in a folder to PNG + SVG with one theme.
import std/[os, strformat]
import nimaid

proc main() =
  let dir = if paramCount() >= 1: paramStr(1) else: "examples"
  let outDir = "out"
  createDir(outDir)
  for path in walkFiles(dir / "*.mmd"):
    let name = splitFile(path).name
    let text = readFile(path)
    try:
      renderMermaidToFile(text, outDir / (name & ".png"), "fonts/DejaVuSans.ttf",
                          emojiFontPath = "fonts/NotoColorEmoji-Regular.ttf", themeName = "neutral")
      renderMermaidToFile(text, outDir / (name & ".svg"), "fonts/DejaVuSans.ttf",
                          emojiFontPath = "fonts/NotoColorEmoji-Regular.ttf", themeName = "neutral")
      echo &"ok    {name}"
    except CatchableError as e:
      echo &"FAIL  {name}: {e.msg}"

main()
