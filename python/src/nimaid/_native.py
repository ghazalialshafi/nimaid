"""Locates and loads the bundled native library and declares its C signatures."""
import ctypes
import os
import sys

ABI_VERSION = 1

_NAMES = {"win32": "nimaid.dll", "cygwin": "nimaid.dll", "darwin": "libnimaid.dylib"}


class Options(ctypes.Structure):  # mirrors nimaid_options in nimaid.h
    _fields_ = [
        ("struct_size", ctypes.c_size_t),
        ("scale", ctypes.c_double),
        ("theme", ctypes.c_char_p),
        ("colors", ctypes.c_int),
        ("svg_text", ctypes.c_int),
        ("legacy_dagre", ctypes.c_int),
    ]


class CImage(ctypes.Structure):  # mirrors nimaid_image
    _fields_ = [("width", ctypes.c_int), ("height", ctypes.c_int), ("pixels", ctypes.POINTER(ctypes.c_ubyte))]


def library_path():
    override = os.environ.get("NIMAID_LIB")
    if override:
        return override
    name = _NAMES.get(sys.platform, "libnimaid.so")
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "_native", name)


def load():
    path = library_path()
    if not os.path.exists(path):
        raise ImportError(
            f"nimaid native library not found at {path!r}. Install a platform wheel from PyPI "
            "(pip install nimaid) or point NIMAID_LIB at libnimaid.so / libnimaid.dylib / nimaid.dll.")
    L = ctypes.CDLL(path)
    c_int, c_void_p, c_char_p, c_size_t = ctypes.c_int, ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t
    ubyte_pp = ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte))
    size_p = ctypes.POINTER(c_size_t)
    opt_p = ctypes.POINTER(Options)

    def sig(name, res, *args):
        fn = getattr(L, name)
        fn.restype, fn.argtypes = res, list(args)

    sig("nimaid_abi_version", c_int)
    sig("nimaid_version", c_char_p)
    sig("nimaid_has_embedded_font", c_int)
    sig("nimaid_status_string", c_char_p, c_int)
    sig("nimaid_theme_count", c_int)
    sig("nimaid_theme_name", c_char_p, c_int)
    sig("nimaid_detect_type", c_char_p, c_char_p)
    sig("nimaid_context_new", c_void_p)
    sig("nimaid_context_free", None, c_void_p)
    sig("nimaid_context_error", c_char_p, c_void_p)
    sig("nimaid_context_set_font_file", c_int, c_void_p, c_char_p)
    sig("nimaid_context_set_font_data", c_int, c_void_p, c_char_p, c_size_t)
    sig("nimaid_context_set_emoji_font_file", c_int, c_void_p, c_char_p)
    sig("nimaid_context_set_emoji_font_data", c_int, c_void_p, c_char_p, c_size_t)
    for fn in ("nimaid_render_png", "nimaid_render_gif", "nimaid_render_svg"):
        sig(fn, c_int, c_void_p, c_char_p, opt_p, ubyte_pp, size_p)
    sig("nimaid_render_rgba", c_int, c_void_p, c_char_p, opt_p, ctypes.POINTER(CImage))
    sig("nimaid_render_file", c_int, c_void_p, c_char_p, c_char_p, opt_p)
    sig("nimaid_encode_png", c_int, c_char_p, c_int, c_int, c_int, ubyte_pp, size_p)
    sig("nimaid_encode_gif", c_int, c_char_p, c_int, c_int, c_int, ubyte_pp, size_p)
    sig("nimaid_free", None, c_void_p)
    if L.nimaid_abi_version() != ABI_VERSION:
        raise ImportError(f"nimaid native library ABI {L.nimaid_abi_version()} != expected {ABI_VERSION}")
    return L
