# Tutorial 8 — Calling nimaid from other languages

**You will learn:** how to use the shared library from Python and C++. The same pattern (load the library, declare ~6 functions, always `nimaid_free`) works for Rust, Go (cgo), C#, Java (Panama), Swift, Zig, Lua, …

## Python (`ctypes`, no packages)

`examples/nimaid.py`:

```python
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
```

```python
from nimaid import Nimaid
n = Nimaid("lib/libnimaid.so")
open("a.png", "wb").write(n.png("flowchart LR\n A[Python] --> B[nimaid]", theme="dark"))
print(n.svg("sequenceDiagram\n A->>B: hi")[:40])
try: n.png("flowchart LR\n A --> ")
except ValueError as e: print("error:", e)
```

## C++ (RAII wrapper)

`include/nimaid.hpp` is a header-only wrapper over the C API: `nimaid::Context` owns the context, errors become `nimaid::Error` exceptions, outputs are `std::vector<uint8_t>` / `std::string` (no manual `nimaid_free`).

```cpp
#include "nimaid.hpp"
int main() {
  nimaid::Context ctx;
  nimaid::Options o; o.theme = "dark";
  auto png = ctx.png("flowchart LR\n A[C++] --> B[nimaid]", o);   // std::vector<uint8_t>
  std::string svg = ctx.svg("flowchart LR\n A --> B");
  ctx.render_file("flowchart LR\n A --> B", "out.svg");
}
```

Compile with `c++ -std=c++11 app.cpp -Iinclude lib/libnimaid.a -lm`.

## Other languages — the recipe

1. Load `libnimaid.so` / `libnimaid.dylib` / `nimaid.dll`.
2. Declare `nimaid_context_new`, `nimaid_render_png`, `nimaid_context_error`, `nimaid_free` (add what you need). Pointers are `void*` / `const char*`; sizes are `size_t`; statuses are `int`.
3. Mirror `nimaid_options` as a struct **with `struct_size` filled in** (or pass a null pointer for defaults).
4. Copy the returned bytes into your language's own memory, then call `nimaid_free`.

## Next

[C API reference](../reference/c-api.md) · [Cross-compiling](../cross-compiling.md)
