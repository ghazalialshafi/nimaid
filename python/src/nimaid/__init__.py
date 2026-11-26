"""nimaid - Mermaid diagrams to PNG / GIF / SVG / RGBA pixels. Pure Nim core, no dependencies.

    import nimaid
    open("a.png", "wb").write(nimaid.png("flowchart LR\\n A[Hello] --> B[World]"))
    svg = nimaid.svg("sequenceDiagram\\n A->>B: hi", theme="dark")

For repeated work with your own fonts use a :class:`Context`; for notebooks use :class:`Diagram`.
"""
from __future__ import annotations

import ctypes
import os
import re
import threading
from typing import List, NamedTuple, Optional, Union

from . import _native

__version__ = "0.6.1"
__all__ = [
    "Context", "Diagram", "Image", "png", "gif", "svg", "rgba", "render_file", "detect_type", "themes",
    "encode_png", "encode_gif", "native_version", "NimaidError", "InvalidArgumentError", "FontError",
    "ParseError", "UnsupportedDiagramError", "RenderIOError", "InternalError", "__version__",
]

_L = _native.load()
BytesLike = Union[bytes, bytearray, memoryview]
PathLike = Union[str, "os.PathLike[str]"]


# ----------------------------------------------------------------------------- errors
class NimaidError(Exception):
    """Base class of every error raised by nimaid. `.status` is the C status code."""
    status = 7


class InvalidArgumentError(NimaidError, ValueError):
    status = 1


class FontError(NimaidError):
    status = 2


class ParseError(NimaidError, ValueError):
    """The Mermaid text has a syntax error (the message says where)."""
    status = 3


class UnsupportedDiagramError(NimaidError, ValueError):
    """Valid-looking Mermaid, but a diagram type nimaid does not implement (pie, timeline, ...)."""
    status = 4


class RenderIOError(NimaidError, OSError):
    status = 5


class InternalError(NimaidError):
    status = 7


_ERRORS = {1: InvalidArgumentError, 2: FontError, 3: ParseError, 4: UnsupportedDiagramError,
           5: RenderIOError, 6: MemoryError, 7: InternalError}


def _raise(status: int, message: str):
    cls = _ERRORS.get(status, InternalError)
    raise cls(message or _L.nimaid_status_string(status).decode())


# ----------------------------------------------------------------------------- helpers
class Image(NamedTuple):
    """Straight-alpha RGBA8 pixels, row-major, ``len(data) == width * height * 4``."""
    width: int
    height: int
    data: bytes

    def to_pil(self):
        """Return a Pillow image (requires ``pip install pillow``)."""
        from PIL import Image as PILImage
        return PILImage.frombytes("RGBA", (self.width, self.height), self.data)


_EMOJI_RE = re.compile("[\u2190-\u21ff\u2300-\u23ff\u2600-\u27bf\u2b00-\u2bff\u200d\u20e3\ufe0f\U0001f000-\U0001ffff]")


def _text(text: str) -> bytes:
    if not isinstance(text, str):
        raise TypeError("Mermaid text must be str")
    if "\0" in text:
        raise InvalidArgumentError("Mermaid text must not contain NUL characters")
    return text.encode("utf-8")


def _opts(scale, theme, colors, svg_text, legacy_dagre) -> _native.Options:
    return _native.Options(ctypes.sizeof(_native.Options), float(scale), theme.encode() if theme else None,
                           int(colors), int(bool(svg_text)), int(bool(legacy_dagre)))


def _emoji_font_path() -> Optional[str]:
    try:
        import nimaid_emoji
        return nimaid_emoji.font_path()
    except ImportError:
        return None


def native_version() -> str:
    """Version of the bundled native library."""
    return _L.nimaid_version().decode()


def detect_type(text: str) -> str:
    """'flowchart' 'sequence' 'state' 'er' 'class' 'gantt' 'gitgraph' 'mindmap' 'pie' 'xychart' 'timeline'
    'quadrant' 'journey' 'packet' 'kanban' 'radar' 'treemap' 'sankey' or 'unknown'."""
    return _L.nimaid_detect_type(_text(text)).decode()


def themes() -> List[str]:
    """Built-in theme names."""
    return [_L.nimaid_theme_name(i).decode() for i in range(_L.nimaid_theme_count())]


def _take(buf, n) -> bytes:
    try:
        return ctypes.string_at(buf, n.value) if buf else b""
    finally:
        _L.nimaid_free(ctypes.cast(buf, ctypes.c_void_p))


def _encode(fn, pixels: BytesLike, width: int, height: int, colors: int) -> bytes:
    data = bytes(pixels)
    if len(data) != width * height * 4:
        raise InvalidArgumentError("pixel buffer must be width*height*4 bytes of RGBA")
    buf = ctypes.POINTER(ctypes.c_ubyte)()
    n = ctypes.c_size_t()
    st = fn(data, width, height, int(colors), ctypes.byref(buf), ctypes.byref(n))
    if st:
        _raise(st, "")
    return _take(buf, n)


def encode_png(pixels: BytesLike, width: int, height: int, colors: int = 0) -> bytes:
    """PNG-encode RGBA8 pixels (colors: 0 = truecolour, 2..256 = palette)."""
    return _encode(_L.nimaid_encode_png, pixels, width, height, colors)


def encode_gif(pixels: BytesLike, width: int, height: int, colors: int = 0) -> bytes:
    """GIF-encode RGBA8 pixels (colors: 0 = 256, or 2..256)."""
    return _encode(_L.nimaid_encode_gif, pixels, width, height, colors)


# ----------------------------------------------------------------------------- context
class Context:
    """Owns the fonts. Create one and reuse it; fonts are parsed once, not per render.

    ``font``: path or bytes of a TrueType (glyf) font; default is the embedded DejaVu Sans.
    ``emoji``: ``"auto"`` (default) uses the ``nimaid-noto-emoji`` package when installed (``pip install nimaid[emoji]``),
    loading it lazily the first time a diagram contains emoji; ``None``/``False`` disables; a path or bytes sets it.
    Calls are serialised by a lock inside the library, so a Context may be shared between threads.
    """

    def __init__(self, font: Union[None, PathLike, BytesLike] = None, emoji: Union[None, bool, str, PathLike, BytesLike] = "auto"):
        self._ptr = _L.nimaid_context_new()
        if not self._ptr:
            raise MemoryError("nimaid_context_new failed")
        self._pending_emoji: Optional[str] = None
        if font is not None:
            self.set_font(font)
        if emoji == "auto":
            self._pending_emoji = _emoji_font_path()
        elif emoji:
            self.set_emoji_font(emoji)  # type: ignore[arg-type]

    # -- lifecycle
    def close(self) -> None:
        ptr, self._ptr = self._ptr, None
        if ptr:
            _L.nimaid_context_free(ptr)

    def __enter__(self) -> "Context":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

    def _c(self):
        if not self._ptr:
            raise ValueError("Context is closed")
        return self._ptr

    def _check(self, st: int):
        if st:
            _raise(st, _L.nimaid_context_error(self._c()).decode("utf-8", "replace"))

    # -- fonts
    def set_font(self, font: Union[None, PathLike, BytesLike]) -> None:
        """TrueType font (path or bytes). ``None`` restores the embedded DejaVu Sans."""
        if font is None:
            self._check(_L.nimaid_context_set_font_data(self._c(), None, 0))
        elif isinstance(font, (bytes, bytearray, memoryview)):
            b = bytes(font)
            self._check(_L.nimaid_context_set_font_data(self._c(), b, len(b)))
        else:
            self._check(_L.nimaid_context_set_font_file(self._c(), os.fsencode(font)))

    def set_emoji_font(self, font: Union[None, bool, PathLike, BytesLike]) -> None:
        """Noto Color Emoji (OpenType-SVG), path or bytes. ``None``/``False`` disables colour emoji."""
        self._pending_emoji = None
        if font is None or font is False:
            self._check(_L.nimaid_context_set_emoji_font_file(self._c(), None))
        elif font is True:
            p = _emoji_font_path()
            if not p:
                raise FontError("emoji=True needs the nimaid-noto-emoji package: pip install nimaid[emoji]")
            self._check(_L.nimaid_context_set_emoji_font_file(self._c(), os.fsencode(p)))
        elif isinstance(font, (bytes, bytearray, memoryview)):
            b = bytes(font)
            self._check(_L.nimaid_context_set_emoji_font_data(self._c(), b, len(b)))
        else:
            self._check(_L.nimaid_context_set_emoji_font_file(self._c(), os.fsencode(font)))

    def _prepare(self, text: str) -> bytes:
        if self._pending_emoji and _EMOJI_RE.search(text):
            path, self._pending_emoji = self._pending_emoji, None
            self._check(_L.nimaid_context_set_emoji_font_file(self._c(), os.fsencode(path)))
        return _text(text)

    # -- rendering
    def _bytes(self, fn, text, o) -> bytes:
        t = self._prepare(text)
        buf = ctypes.POINTER(ctypes.c_ubyte)()
        n = ctypes.c_size_t()
        st = fn(self._c(), t, ctypes.byref(o), ctypes.byref(buf), ctypes.byref(n))
        if st:
            self._check(st)
        return _take(buf, n)

    def png(self, text: str, *, scale: float = 2.0, theme: Optional[str] = None, colors: int = 0,
            legacy_dagre: bool = True) -> bytes:
        """PNG bytes. ``colors`` 2..256 gives a smaller palette PNG."""
        return self._bytes(_L.nimaid_render_png, text, _opts(scale, theme, colors, False, legacy_dagre))

    def gif(self, text: str, *, scale: float = 2.0, theme: Optional[str] = None, colors: int = 0,
            legacy_dagre: bool = True) -> bytes:
        """GIF bytes (still image)."""
        return self._bytes(_L.nimaid_render_gif, text, _opts(scale, theme, colors, False, legacy_dagre))

    def svg(self, text: str, *, theme: Optional[str] = None, live_text: bool = False, legacy_dagre: bool = True) -> str:
        """SVG document. ``live_text=True`` keeps selectable <text> instead of outlined glyphs."""
        raw = self._bytes(_L.nimaid_render_svg, text, _opts(1.0, theme, 0, live_text, legacy_dagre))
        return raw.rstrip(b"\0").decode("utf-8")

    def rgba(self, text: str, *, scale: float = 2.0, theme: Optional[str] = None, legacy_dagre: bool = True) -> Image:
        """Raw straight-alpha RGBA8 pixels."""
        t = self._prepare(text)
        o = _opts(scale, theme, 0, False, legacy_dagre)
        img = _native.CImage()
        st = _L.nimaid_render_rgba(self._c(), t, ctypes.byref(o), ctypes.byref(img))
        if st:
            self._check(st)
        try:
            return Image(img.width, img.height, ctypes.string_at(img.pixels, img.width * img.height * 4))
        finally:
            _L.nimaid_free(ctypes.cast(img.pixels, ctypes.c_void_p))

    def render_file(self, text: str, path: PathLike, *, scale: float = 2.0, theme: Optional[str] = None,
                    colors: int = 0, live_text: bool = False, legacy_dagre: bool = True) -> None:
        """Write ``path``; the format comes from the extension (.svg, .gif, anything else = PNG)."""
        t = self._prepare(text)
        o = _opts(scale, theme, colors, live_text, legacy_dagre)
        self._check(_L.nimaid_render_file(self._c(), t, os.fsencode(path), ctypes.byref(o)))


# ----------------------------------------------------------------------------- module-level convenience
_default: Optional[Context] = None
_default_lock = threading.Lock()


def _ctx() -> Context:
    global _default
    if _default is None:
        with _default_lock:
            if _default is None:
                _default = Context()
    return _default


def png(text: str, **kw) -> bytes:
    """Render to PNG bytes with the default context. See :meth:`Context.png`."""
    return _ctx().png(text, **kw)


def gif(text: str, **kw) -> bytes:
    """See :meth:`Context.gif`."""
    return _ctx().gif(text, **kw)


def svg(text: str, **kw) -> str:
    """See :meth:`Context.svg`."""
    return _ctx().svg(text, **kw)


def rgba(text: str, **kw) -> Image:
    """See :meth:`Context.rgba`."""
    return _ctx().rgba(text, **kw)


def render_file(text: str, path: PathLike, **kw) -> None:
    """See :meth:`Context.render_file`."""
    _ctx().render_file(text, path, **kw)


class Diagram:
    """A Mermaid diagram that displays itself in Jupyter / IPython (``_repr_svg_``) and can be saved.

        Diagram("flowchart LR\\n A --> B", theme="forest")      # last expression of a cell shows the SVG
        Diagram(text).save("out.png")
    """

    def __init__(self, text: str, *, theme: Optional[str] = None, context: Optional[Context] = None):
        self.text, self.theme, self._context = text, theme, context

    def _c(self) -> Context:
        return self._context or _ctx()

    def png(self, **kw) -> bytes:
        return self._c().png(self.text, theme=kw.pop("theme", self.theme), **kw)

    def gif(self, **kw) -> bytes:
        return self._c().gif(self.text, theme=kw.pop("theme", self.theme), **kw)

    def svg(self, **kw) -> str:
        return self._c().svg(self.text, theme=kw.pop("theme", self.theme), **kw)

    def save(self, path: PathLike, **kw) -> None:
        self._c().render_file(self.text, path, theme=kw.pop("theme", self.theme), **kw)

    def _repr_svg_(self) -> str:
        return self.svg()

    def _repr_png_(self) -> bytes:
        return self.png()

    def __repr__(self) -> str:
        return f"Diagram({detect_type(self.text)}, {len(self.text)} chars)"
