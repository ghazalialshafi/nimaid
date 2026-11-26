// nimaid.mjs - Mermaid diagrams to PNG / GIF / SVG / RGBA in WebAssembly (Node >= 16, Deno, Bun, browsers).
// Pure JS wrapper over nimaid.wasm (the nimaid C API compiled for wasm32-wasi). No dependencies.
//
//   import { Nimaid } from "./nimaid.mjs";
//   const nimaid = await Nimaid.load();                       // finds nimaid.wasm next to this file
//   const png = nimaid.png("flowchart LR\n A --> B", { theme: "dark" });   // Uint8Array
//   const svg = nimaid.svg("sequenceDiagram\n A->>B: hi");                 // string

export class NimaidError extends Error {
  constructor(status, message) { super(message); this.name = "NimaidError"; this.status = status; }
}

const STATUS = ["ok", "invalid argument", "font error", "diagram syntax error", "unsupported diagram type", "i/o error", "out of memory", "internal error"];
const OPTIONS_SIZE = 32; // sizeof(nimaid_options) on wasm32: size_t@0 double@8 char*@16 int@20 int@24 int@28
const enc = new TextEncoder(), dec = new TextDecoder();

function wasiImports(getMemory) {
  const ENOSYS = 52, EBADF = 8;
  const dv = () => new DataView(getMemory().buffer);
  return {
    proc_exit: (code) => { throw new Error(`nimaid.wasm called exit(${code})`); },
    environ_sizes_get: (countPtr, sizePtr) => { dv().setUint32(countPtr, 0, true); dv().setUint32(sizePtr, 0, true); return 0; },
    environ_get: () => 0,
    fd_write: (fd, iovs, iovsLen, nwrittenPtr) => {          // stdout/stderr are discarded
      let n = 0; const v = dv();
      for (let i = 0; i < iovsLen; i++) n += v.getUint32(iovs + i * 8 + 4, true);
      v.setUint32(nwrittenPtr, n, true); return 0;
    },
    fd_prestat_get: () => EBADF, fd_prestat_dir_name: () => EBADF,   // no preopened directories: no file system
    fd_close: () => 0, fd_fdstat_get: () => EBADF, fd_fdstat_set_flags: () => ENOSYS, fd_filestat_get: () => EBADF,
    fd_read: () => EBADF, fd_seek: () => EBADF, path_open: () => ENOSYS, path_filestat_get: () => ENOSYS, poll_oneoff: () => ENOSYS,
  };
}

async function fetchWasm(source) {
  if (source instanceof WebAssembly.Module) return source;
  if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) return WebAssembly.compile(source);
  const url = source ?? new URL("./nimaid.wasm", import.meta.url);
  if (typeof process !== "undefined" && process.versions && process.versions.node && (url instanceof URL ? url.protocol === "file:" : !/^https?:/.test(url))) {
    const { readFile } = await import("node:fs/promises");
    const { fileURLToPath } = await import("node:url");
    return WebAssembly.compile(await readFile(url instanceof URL ? fileURLToPath(url) : url));
  }
  const res = await fetch(url);
  if (WebAssembly.compileStreaming && (res.headers.get("content-type") || "").includes("application/wasm")) return WebAssembly.compileStreaming(res);
  return WebAssembly.compile(await res.arrayBuffer());
}

export class Nimaid {
  /** @param {string|URL|ArrayBuffer|Uint8Array|WebAssembly.Module} [source] where to get nimaid.wasm (default: next to this file) */
  static async load(source) {
    let memory;
    const module = await fetchWasm(source);
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasiImports(() => memory) });
    memory = instance.exports.memory;
    if (instance.exports._initialize) instance.exports._initialize();
    return new Nimaid(instance);
  }

  constructor(instance) {
    this.x = instance.exports;
    this.ctx = this.x.nimaid_context_new();
    if (!this.ctx) throw new NimaidError(6, "out of memory");
    this._opts = this.x.nimaid_alloc(OPTIONS_SIZE);
    this._out = this.x.nimaid_alloc(16);
  }

  get version() { return this._cstr(this.x.nimaid_version()); }
  get hasEmbeddedFont() { return !!this.x.nimaid_has_embedded_font(); }
  themes() { const n = this.x.nimaid_theme_count(); return Array.from({ length: n }, (_, i) => this._cstr(this.x.nimaid_theme_name(i))); }
  detectType(text) { return this._withString(text, (p) => this._cstr(this.x.nimaid_detect_type(p))); }

  /** Free the context. The instance must not be used afterwards. */
  close() { if (this.ctx) { this.x.nimaid_free(this._opts); this.x.nimaid_free(this._out); this.x.nimaid_context_free(this.ctx); this.ctx = 0; } }

  /** TrueType (glyf) font bytes; null restores the embedded DejaVu Sans. */
  setFont(bytes) { this._setFont(bytes, this.x.nimaid_context_set_font_data); }
  /** Noto Color Emoji (OpenType-SVG) bytes; null disables colour emoji (the default). */
  setEmojiFont(bytes) { this._setFont(bytes, this.x.nimaid_context_set_emoji_font_data); }

  /** @returns {Uint8Array} PNG. options: { scale = 2, theme, colors = 0, legacyDagre = true } */
  png(text, options) { return this._bytes(this.x.nimaid_render_png, text, options); }
  /** @returns {Uint8Array} GIF (still image). */
  gif(text, options) { return this._bytes(this.x.nimaid_render_gif, text, options); }
  /** @returns {string} SVG document. options: { theme, liveText = false, legacyDagre = true } */
  svg(text, options = {}) {
    const raw = this._bytes(this.x.nimaid_render_svg, text, { ...options, scale: 1, colors: 0, svgText: !!options.liveText });
    return dec.decode(raw.subarray(0, raw.length - (raw[raw.length - 1] === 0 ? 1 : 0)));
  }
  /** @returns {{width:number,height:number,data:Uint8ClampedArray}} straight-alpha RGBA8 (usable with ImageData) */
  rgba(text, options) {
    const x = this.x, img = x.nimaid_alloc(12);
    try {
      this._call(() => this._withString(text, (t) => this._withOptions(options, (o) => x.nimaid_render_rgba(this.ctx, t, o, img))));
      const v = new DataView(x.memory.buffer), w = v.getInt32(img, true), h = v.getInt32(img + 4, true), p = v.getUint32(img + 8, true);
      const data = new Uint8ClampedArray(x.memory.buffer.slice(p, p + w * h * 4));
      x.nimaid_free(p);
      return { width: w, height: h, data };
    } finally { x.nimaid_free(img); }
  }
  /** Encode your own RGBA pixels. colors: 0 = truecolour PNG / 256-colour GIF, or 2..256. */
  encodePng(rgba, width, height, colors = 0) { return this._encode(this.x.nimaid_encode_png, rgba, width, height, colors); }
  encodeGif(rgba, width, height, colors = 0) { return this._encode(this.x.nimaid_encode_gif, rgba, width, height, colors); }

  // ---- internals
  _cstr(ptr) { if (!ptr) return null; const m = new Uint8Array(this.x.memory.buffer); let e = ptr; while (m[e]) e++; return dec.decode(m.subarray(ptr, e)); }
  _withString(s, fn) {
    const b = enc.encode(String(s));
    if (b.includes(0)) throw new NimaidError(1, "text must not contain NUL characters");
    const p = this.x.nimaid_alloc(b.length + 1);
    if (!p) throw new NimaidError(6, "out of memory");
    try { const m = new Uint8Array(this.x.memory.buffer); m.set(b, p); m[p + b.length] = 0; return fn(p); } finally { this.x.nimaid_free(p); }
  }
  _withOptions(o = {}, fn) {
    const x = this.x, p = this._opts;
    const theme = o.theme ? enc.encode(o.theme + "\0") : null;
    const tp = theme ? x.nimaid_alloc(theme.length) : 0;
    try {
      if (theme) new Uint8Array(x.memory.buffer).set(theme, tp);
      const v = new DataView(x.memory.buffer);
      v.setUint32(p, OPTIONS_SIZE, true); v.setFloat64(p + 8, o.scale ?? 2, true); v.setUint32(p + 16, tp, true);
      v.setInt32(p + 20, o.colors ?? 0, true); v.setInt32(p + 24, o.svgText ? 1 : 0, true); v.setInt32(p + 28, (o.legacyDagre ?? true) ? 1 : 0, true);
      return fn(p);
    } finally { if (tp) x.nimaid_free(tp); }
  }
  _call(fn) {
    const st = fn();
    if (st) throw new NimaidError(st, this._cstr(this.x.nimaid_context_error(this.ctx)) || STATUS[st] || "error");
  }
  _take(outPtr) {
    const v = new DataView(this.x.memory.buffer), p = v.getUint32(outPtr, true), n = v.getUint32(outPtr + 4, true);
    const bytes = new Uint8Array(this.x.memory.buffer).slice(p, p + n);
    this.x.nimaid_free(p);
    return bytes;
  }
  _bytes(fn, text, options) {
    const out = this._out;
    this._call(() => this._withString(text, (t) => this._withOptions(options, (o) => fn(this.ctx, t, o, out, out + 4))));
    return this._take(out);
  }
  _encode(fn, rgba, width, height, colors) {
    const x = this.x, n = width * height * 4;
    if (rgba.length !== n) throw new NimaidError(1, "pixel buffer must be width*height*4 bytes");
    const buf = x.nimaid_alloc(n);
    try {
      new Uint8Array(x.memory.buffer).set(rgba, buf);
      this._call(() => fn(buf, width, height, colors, this._out, this._out + 4));
      return this._take(this._out);
    } finally { x.nimaid_free(buf); }
  }
  _setFont(bytes, fn) {
    if (bytes == null) return this._call(() => fn(this.ctx, 0, 0));
    const p = this.x.nimaid_alloc(bytes.length);
    try { new Uint8Array(this.x.memory.buffer).set(bytes, p); this._call(() => fn(this.ctx, p, bytes.length)); } finally { this.x.nimaid_free(p); }
  }
}

export default Nimaid;
