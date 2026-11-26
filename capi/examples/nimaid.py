"""ctypes binding for the nimaid C API (see docs/tutorials/08-other-languages.md)."""
import ctypes, ctypes.util, os, sys

def _load(path=None):
    names = {"win32": "nimaid.dll", "darwin": "libnimaid.dylib"}.get(sys.platform, "libnimaid.so")
    return ctypes.CDLL(path or os.environ.get("NIMAID_LIB", names))

class Options(ctypes.Structure):               # mirrors nimaid_options
    _fields_ = [("struct_size", ctypes.c_size_t), ("scale", ctypes.c_double), ("theme", ctypes.c_char_p),
                ("colors", ctypes.c_int), ("svg_text", ctypes.c_int), ("legacy_dagre", ctypes.c_int)]

class Nimaid:
    def __init__(self, lib=None):
        L = self._lib = _load(lib)
        L.nimaid_context_new.restype = ctypes.c_void_p
        L.nimaid_context_free.argtypes = [ctypes.c_void_p]
        L.nimaid_context_error.restype = ctypes.c_char_p; L.nimaid_context_error.argtypes = [ctypes.c_void_p]
        L.nimaid_free.argtypes = [ctypes.c_void_p]
        P = ctypes.POINTER(ctypes.c_ubyte)
        for fn in (L.nimaid_render_png, L.nimaid_render_gif):
            fn.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(Options),
                           ctypes.POINTER(P), ctypes.POINTER(ctypes.c_size_t)]
        L.nimaid_render_svg.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.POINTER(Options),
                                        ctypes.POINTER(P), ctypes.POINTER(ctypes.c_size_t)]
        self._ctx = L.nimaid_context_new()

    def _render(self, fn, text, scale, theme, colors, svg_text):
        o = Options(ctypes.sizeof(Options), scale, theme.encode() if theme else None, colors, int(svg_text), 1)
        buf = ctypes.POINTER(ctypes.c_ubyte)(); n = ctypes.c_size_t()
        if fn(self._ctx, text.encode(), ctypes.byref(o), ctypes.byref(buf), ctypes.byref(n)):
            raise ValueError(self._lib.nimaid_context_error(self._ctx).decode())
        try:    return ctypes.string_at(buf, n.value)
        finally: self._lib.nimaid_free(buf)

    def png(self, text, scale=2.0, theme=None, colors=0):  return self._render(self._lib.nimaid_render_png, text, scale, theme, colors, False)
    def gif(self, text, scale=2.0, theme=None, colors=0):  return self._render(self._lib.nimaid_render_gif, text, scale, theme, colors, False)
    def svg(self, text, theme=None, svg_text=False):       return self._render(self._lib.nimaid_render_svg, text, 1.0, theme, 0, svg_text).decode()

    def __del__(self):
        if getattr(self, "_ctx", None): self._lib.nimaid_context_free(self._ctx); self._ctx = None
