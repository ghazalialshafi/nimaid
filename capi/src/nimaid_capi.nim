## nimaid C API  --  stable C ABI over the pure-Nim nimaid library.
## Build: see capi/build.py (zig cross compiler) or capi/README.md. Public header: include/nimaid.h
import std/[os, strutils, math]
import nimaid
import nimaid/purevg as pvgEngine except pvg_font_load_data   # engine init/term + font registry (qualified use only)

const
  OK = 0.cint
  ErrInvalid = 1.cint
  ErrFont = 2.cint
  ErrParse = 3.cint
  ErrUnsupported = 4.cint
  ErrIo = 5.cint
  ErrOom = 6.cint
  ErrInternal = 7.cint
  AbiVersion = 1.cint
  MaxPixels = when sizeof(int) == 4: 0x1FFFFFF'i64 else: 0x1FFFFFFF'i64   # keeps width*height*4 inside `int`
  embeddedFont = when defined(nimaidNoEmbeddedFont): "" else: staticRead("../../fonts/DejaVuSans.ttf")

# ------------------------------------------------------------------ process-wide lock + one-time runtime init
# (in C so that it works before Nim's own module initialisation has run)
{.emit: "/*TYPESECTION*/\n#include <stdatomic.h>\nstatic atomic_flag nimaid__lk = ATOMIC_FLAG_INIT;\nstatic int nimaid__inited = 0;\nstatic int nimaid__try_lock(void) { return !atomic_flag_test_and_set_explicit(&nimaid__lk, memory_order_acquire); }\nstatic void nimaid__unlock(void) { atomic_flag_clear_explicit(&nimaid__lk, memory_order_release); }\nstatic int nimaid__is_inited(void) { return nimaid__inited; }\nstatic void nimaid__set_inited(void) { nimaid__inited = 1; }\nvoid NimMain(void);\n".}
proc cTryLock(): cint {.importc: "nimaid__try_lock", nodecl.}
proc cUnlock() {.importc: "nimaid__unlock", nodecl.}
proc cIsInited(): cint {.importc: "nimaid__is_inited", nodecl.}
proc cSetInited() {.importc: "nimaid__set_inited", nodecl.}
proc nimMain() {.importc: "NimMain", nodecl, cdecl.}
proc cMalloc(n: csize_t): pointer {.importc: "malloc", header: "<stdlib.h>".}
proc cFree(p: pointer) {.importc: "free", header: "<stdlib.h>".}

proc lockLib() =
  while cTryLock() == 0: sleep(1)
proc ensureInit() =
  if cIsInited() == 0:
    nimMain()
    cSetInited()

# ------------------------------------------------------------------ types
type
  Ctx = ref object
    id, gen: int
    fontData: string      ## "" = embedded DejaVu Sans
    emojiPath: string
    emojiData: string
    err: string
  COptions {.bycopy.} = object
    structSize: csize_t
    scale: cdouble
    theme: cstring
    colors: cint
    svgText: cint
    legacyDagre: cint
  CImage {.bycopy.} = object
    width, height: cint
    pixels: ptr uint8
  Opts = object
    scale: float
    theme: string
    colors: int
    svgText, legacy: bool
  Fail = object of CatchableError
    code: cint

var nextId = 0
var loadedId = -1
var loadedGen = -1
var loadedFont = ""

proc fail(code: cint, msg: string) {.noreturn.} =
  let e = newException(Fail, msg)
  e.code = code
  raise e

proc classify(e: ref Exception): (cint, string) =
  if e of Fail: ((ref Fail)(e).code, e.msg)
  elif e of OutOfMemDefect: (ErrOom, "out of memory")
  elif e of IOError or e of OSError: (ErrIo, e.msg)
  elif e of ValueError and e.msg.startsWith("unsupported diagram type"): (ErrUnsupported, e.msg)
  elif e of CatchableError: (ErrParse, e.msg)
  else: (ErrInternal, e.msg)

template entry(c: Ctx, body: untyped): cint =
  var rc: cint = OK
  lockLib()
  try:
    ensureInit()
    if c != nil: c.err = ""
    try:
      body
    except Exception as e:
      let (code, msg) = classify(e)
      if c != nil: c.err = msg
      rc = code
  finally:
    cUnlock()
  rc

proc dupBytes(src: pointer, n: int, extra = 0): pointer =
  result = cMalloc(csize_t(n + extra))
  if result == nil: fail(ErrOom, "out of memory")
  if n > 0: copyMem(result, src, n)
  if extra > 0: cast[ptr UncheckedArray[byte]](result)[n] = 0

proc readOpts(p: ptr COptions): Opts =
  result = Opts(scale: 2.0, theme: "", colors: 0, svgText: false, legacy: true)
  if p != nil:
    let sz = int(p.structSize)
    if sz >= offsetOf(COptions, scale) + sizeof(cdouble): result.scale = p.scale
    if sz >= offsetOf(COptions, theme) + sizeof(cstring) and p.theme != nil: result.theme = $p.theme
    if sz >= offsetOf(COptions, colors) + sizeof(cint): result.colors = p.colors
    if sz >= offsetOf(COptions, svgText) + sizeof(cint): result.svgText = p.svgText != 0
    if sz >= offsetOf(COptions, legacyDagre) + sizeof(cint): result.legacy = p.legacyDagre != 0
  if not (result.scale > 0.0) or result.scale.classify in {fcInf, fcNan}:
    fail(ErrInvalid, "scale must be a finite number > 0")
  if result.colors != 0 and (result.colors < 2 or result.colors > 256):
    fail(ErrInvalid, "colors must be 0 or in 2..256")

proc unloadActive() =
  if loadedFont.len > 0: discard pvgEngine.pvg_font_unload(loadedFont.cstring)
  unloadEmojiFont()
  loadedFont = ""; loadedId = -1; loadedGen = -1

proc activate(c: Ctx) =
  ## Loads this context's fonts into the (global) engine unless they already are.
  if loadedId == c.id and loadedGen == c.gen: return
  unloadActive()
  let name = "nimaid_font_" & $c.id & "_" & $c.gen
  let data = if c.fontData.len > 0: c.fontData else: embeddedFont
  if data.len == 0: fail(ErrFont, "no font configured (embedded font disabled): call nimaid_context_set_font_*")
  if not initTextMetricsData(name, data): fail(ErrFont, "unsupported text font (need a TrueType font with glyf outlines)")
  loadedFont = name
  if c.emojiData.len > 0:
    if not loadEmojiFontData(c.emojiData): fail(ErrFont, "unsupported emoji font (need Noto Color Emoji, OpenType-SVG)")
  elif c.emojiPath.len > 0:
    if not loadEmojiFont(c.emojiPath): fail(ErrFont, "cannot load emoji font '" & c.emojiPath & "'")
  loadedId = c.id; loadedGen = c.gen

proc buildScene(c: Ctx, text: cstring, o: Opts): Composed =
  if c == nil: fail(ErrInvalid, "context is NULL")
  if text == nil: fail(ErrInvalid, "text is NULL")
  activate(c)
  useLegacyDagre = o.legacy
  buildMermaidSceneLoaded($text, o.scale, o.theme)

template withEngine(body: untyped) =
  discard pvgEngine.pvg_engine_init(0)
  try: body
  finally: discard pvgEngine.pvg_engine_term()

template needOut(p: untyped) =
  if p == nil: fail(ErrInvalid, "output pointer is NULL")

proc sceneToSvg(c: Ctx, text: cstring, o: Opts): string =
  withEngine:
    let sc = buildScene(c, text, Opts(scale: 1.0, theme: o.theme, legacy: o.legacy))
    let b = themeFor($text, o.theme).background
    result = toSvg(sc.root, sc.width, sc.height, [b.r, b.g, b.b, b.a],
                   textMode = (if o.svgText: stText else: stPaths))

proc renderBitmap(c: Ctx, text: cstring, o: Opts): RenderedImage =
  withEngine:
    let sc = buildScene(c, text, o)
    result = RenderedImage(width: sc.width, height: sc.height, rgba: renderRgba(sc.root, sc.width, sc.height))

proc encodeBitmap(img: RenderedImage, gif: bool, o: Opts): seq[byte] =
  if gif: encodeGif(img.rgba, img.width, img.height, (if o.colors >= 2: o.colors else: 256))
  else: encodePng(img.rgba, img.width, img.height, o.colors)

# ------------------------------------------------------------------ version / info
proc nimaid_abi_version*(): cint {.exportc, cdecl, dynlib.} = AbiVersion
proc nimaid_version*(): cstring {.exportc, cdecl, dynlib.} = nimaidVersion
proc nimaid_has_embedded_font*(): cint {.exportc, cdecl, dynlib.} = (if embeddedFont.len > 0: 1 else: 0)

proc nimaid_status_string*(status: cint): cstring {.exportc, cdecl, dynlib.} =
  case status
  of 0: "ok"
  of 1: "invalid argument"
  of 2: "font error"
  of 3: "diagram syntax error"
  of 4: "unsupported diagram type"
  of 5: "i/o error"
  of 6: "out of memory"
  else: "internal error"

const themeNamesC = [cstring "default", "dark", "forest", "neutral", "base"]
proc nimaid_theme_count*(): cint {.exportc, cdecl, dynlib.} = themeNamesC.len.cint
proc nimaid_theme_name*(index: cint): cstring {.exportc, cdecl, dynlib.} =
  if index < 0 or index >= themeNamesC.len: nil else: themeNamesC[index]

proc nimaid_detect_type*(text: cstring): cstring {.exportc, cdecl, dynlib.} =
  ## "flowchart" "sequence" "state" "er" "class" "gantt" "gitgraph" "mindmap" "pie" "xychart" "timeline"
  ## "quadrant" "journey" "packet" "kanban" "radar" "treemap" "sankey" or "unknown". Never NULL.
  if text == nil: return "unknown"
  var t = ""
  lockLib()
  try:
    ensureInit()
    try: t = detectDiagramType($text) except Exception: t = "unknown"
  finally: cUnlock()
  case t
  of "flowchart": "flowchart"
  of "sequence": "sequence"
  of "state": "state"
  of "er": "er"
  of "class": "class"
  of "gantt": "gantt"
  of "gitgraph": "gitgraph"
  of "mindmap": "mindmap"
  of "pie": "pie"
  of "xychart": "xychart"
  of "timeline": "timeline"
  of "quadrant": "quadrant"
  of "journey": "journey"
  of "packet": "packet"
  of "kanban": "kanban"
  of "radar": "radar"
  of "treemap": "treemap"
  of "sankey": "sankey"
  else: "unknown"

# ------------------------------------------------------------------ context
proc nimaid_context_new*(): pointer {.exportc, cdecl, dynlib.} =
  lockLib()
  try:
    ensureInit()
    try:
      let c = Ctx(id: nextId)
      inc nextId
      GC_ref(c)
      result = cast[pointer](c)
    except Exception: result = nil
  finally: cUnlock()

proc nimaid_context_free*(ctx: pointer) {.exportc, cdecl, dynlib.} =
  if ctx == nil: return
  lockLib()
  try:
    ensureInit()
    let c = cast[Ctx](ctx)
    if loadedId == c.id: unloadActive()
    GC_unref(c)
  finally: cUnlock()

proc nimaid_context_error*(ctx: pointer): cstring {.exportc, cdecl, dynlib.} =
  ## Message of the last failed call on this context ("" if none). Valid until the next call on it.
  if ctx == nil: return ""
  cast[Ctx](ctx).err.cstring

proc nimaid_context_set_font_data*(ctx: pointer, data: pointer, size: csize_t): cint {.exportc, cdecl, dynlib.} =
  ## data == NULL (or size 0) restores the embedded font. The bytes are copied.
  let c = cast[Ctx](ctx)
  entry(c):
    if c == nil: fail(ErrInvalid, "context is NULL")
    if data == nil or size == 0: c.fontData = ""
    else:
      var s = newString(int(size))
      copyMem(addr s[0], data, int(size))
      c.fontData = s
    inc c.gen

proc nimaid_context_set_font_file*(ctx: pointer, path: cstring): cint {.exportc, cdecl, dynlib.} =
  let c = cast[Ctx](ctx)
  entry(c):
    if c == nil or path == nil: fail(ErrInvalid, "context or path is NULL")
    var s: string
    try: s = readFile($path)
    except IOError: fail(ErrFont, "cannot read font file '" & $path & "'")
    c.fontData = s
    inc c.gen

proc nimaid_context_set_emoji_font_data*(ctx: pointer, data: pointer, size: csize_t): cint {.exportc, cdecl, dynlib.} =
  ## data == NULL (or size 0) disables colour emoji. The bytes are copied.
  let c = cast[Ctx](ctx)
  entry(c):
    if c == nil: fail(ErrInvalid, "context is NULL")
    c.emojiPath = ""
    if data == nil or size == 0: c.emojiData = ""
    else:
      var s = newString(int(size))
      copyMem(addr s[0], data, int(size))
      c.emojiData = s
    inc c.gen

proc nimaid_context_set_emoji_font_file*(ctx: pointer, path: cstring): cint {.exportc, cdecl, dynlib.} =
  ## path == NULL disables colour emoji. The file is read lazily on the first render that needs it.
  let c = cast[Ctx](ctx)
  entry(c):
    if c == nil: fail(ErrInvalid, "context is NULL")
    c.emojiData = ""
    if path == nil: c.emojiPath = ""
    else:
      if not fileExists($path): fail(ErrFont, "cannot find emoji font file '" & $path & "'")
      c.emojiPath = $path
    inc c.gen

# ------------------------------------------------------------------ rendering
proc nimaid_render_svg*(ctx: pointer, text: cstring, opts: ptr COptions,
                        outStr: ptr ptr char, outSize: ptr csize_t): cint {.exportc, cdecl, dynlib.} =
  let c = cast[Ctx](ctx)
  if outStr != nil: outStr[] = nil
  if outSize != nil: outSize[] = 0
  entry(c):
    needOut(outStr)
    let svg = sceneToSvg(c, text, readOpts(opts))
    outStr[] = cast[ptr char](dupBytes(unsafeAddr svg[0], svg.len, 1))
    if outSize != nil: outSize[] = csize_t(svg.len)

proc nimaid_render_rgba*(ctx: pointer, text: cstring, opts: ptr COptions,
                         outImage: ptr CImage): cint {.exportc, cdecl, dynlib.} =
  let c = cast[Ctx](ctx)
  if outImage != nil: outImage[] = CImage()
  entry(c):
    needOut(outImage)
    let img = renderBitmap(c, text, readOpts(opts))
    outImage.pixels = cast[ptr uint8](dupBytes(unsafeAddr img.rgba[0], img.rgba.len))
    outImage.width = img.width.cint
    outImage.height = img.height.cint

proc renderEncoded(ctx: pointer, text: cstring, opts: ptr COptions, outBuf: ptr ptr uint8,
                   outSize: ptr csize_t, gif: bool): cint =
  let c = cast[Ctx](ctx)
  if outBuf != nil: outBuf[] = nil
  if outSize != nil: outSize[] = 0
  entry(c):
    needOut(outBuf); needOut(outSize)
    let o = readOpts(opts)
    let data = encodeBitmap(renderBitmap(c, text, o), gif, o)
    outBuf[] = cast[ptr uint8](dupBytes(unsafeAddr data[0], data.len))
    outSize[] = csize_t(data.len)

proc nimaid_render_png*(ctx: pointer, text: cstring, opts: ptr COptions, outBuf: ptr ptr uint8,
                        outSize: ptr csize_t): cint {.exportc, cdecl, dynlib.} =
  renderEncoded(ctx, text, opts, outBuf, outSize, false)

proc nimaid_render_gif*(ctx: pointer, text: cstring, opts: ptr COptions, outBuf: ptr ptr uint8,
                        outSize: ptr csize_t): cint {.exportc, cdecl, dynlib.} =
  renderEncoded(ctx, text, opts, outBuf, outSize, true)

proc nimaid_render_file*(ctx: pointer, text: cstring, outputPath: cstring,
                         opts: ptr COptions): cint {.exportc, cdecl, dynlib.} =
  ## Format from the extension: .svg, .gif, otherwise PNG (same rule as the nimaid CLI).
  let c = cast[Ctx](ctx)
  entry(c):
    if outputPath == nil: fail(ErrInvalid, "output path is NULL")
    let o = readOpts(opts)
    let path = $outputPath
    let ext = path.toLowerAscii
    var data: string
    if ext.endsWith(".svg"): data = sceneToSvg(c, text, o)
    else:
      let b = encodeBitmap(renderBitmap(c, text, o), ext.endsWith(".gif"), o)
      data = newString(b.len)
      if b.len > 0: copyMem(addr data[0], unsafeAddr b[0], b.len)
    try: writeFile(path, data)
    except IOError: fail(ErrIo, "cannot write '" & path & "'")

# ------------------------------------------------------------------ encoders for caller-supplied pixels
proc encodeRaw(rgba: pointer, width, height, colors: cint, outBuf: ptr ptr uint8, outSize: ptr csize_t,
               gif: bool): cint =
  if outBuf != nil: outBuf[] = nil
  if outSize != nil: outSize[] = 0
  entry(Ctx(nil)):
    needOut(outBuf); needOut(outSize)
    if rgba == nil or width <= 0 or height <= 0 or int64(width) * int64(height) > MaxPixels:
      fail(ErrInvalid, "bad pixel buffer or dimensions")
    if colors != 0 and (colors < 2 or colors > 256): fail(ErrInvalid, "colors must be 0 or in 2..256")
    let px = cast[ptr UncheckedArray[byte]](rgba)
    let n = width * height * 4 - 1
    let data = if gif: encodeGif(toOpenArray(px, 0, n), width, height, (if colors >= 2: colors else: 256))
               else: encodePng(toOpenArray(px, 0, n), width, height, colors)
    outBuf[] = cast[ptr uint8](dupBytes(unsafeAddr data[0], data.len))
    outSize[] = csize_t(data.len)

proc nimaid_encode_png*(rgba: pointer, width, height, colors: cint, outBuf: ptr ptr uint8,
                        outSize: ptr csize_t): cint {.exportc, cdecl, dynlib.} =
  encodeRaw(rgba, width, height, colors, outBuf, outSize, false)

proc nimaid_encode_gif*(rgba: pointer, width, height, colors: cint, outBuf: ptr ptr uint8,
                        outSize: ptr csize_t): cint {.exportc, cdecl, dynlib.} =
  encodeRaw(rgba, width, height, colors, outBuf, outSize, true)

proc nimaid_free*(p: pointer) {.exportc, cdecl, dynlib.} = cFree(p)
proc nimaid_alloc*(size: csize_t): pointer {.exportc, cdecl, dynlib.} = cMalloc(if size == 0: 1.csize_t else: size)
