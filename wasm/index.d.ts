export class NimaidError extends Error {
  /** C status code: 1 invalid argument, 2 font, 3 syntax error, 4 unsupported diagram, 5 i/o, 6 out of memory, 7 internal. */
  status: number;
  constructor(status: number, message: string);
}

export interface RenderOptions {
  /** PNG/GIF pixel scale, 2 = retina (default 2). Must be > 0. */
  scale?: number;
  /** "default" | "dark" | "forest" | "neutral" | "base"; omitted = from the diagram. */
  theme?: string;
  /** 0 = truecolour PNG / 256-colour GIF; 2..256 = palette size. */
  colors?: number;
  /** true (default) = Mermaid-compatible layout ordering. */
  legacyDagre?: boolean;
}

export interface SvgOptions {
  theme?: string;
  /** true = selectable <text> instead of outlined glyphs (default false). */
  liveText?: boolean;
  legacyDagre?: boolean;
}

export interface RgbaImage {
  width: number;
  height: number;
  /** straight-alpha RGBA8; can be passed to `new ImageData(data, width, height)` */
  data: Uint8ClampedArray;
}

export type WasmSource = string | URL | ArrayBuffer | Uint8Array | WebAssembly.Module;

export class Nimaid {
  /** Loads and instantiates nimaid.wasm (default: next to nimaid.mjs). */
  static load(source?: WasmSource): Promise<Nimaid>;
  readonly version: string;
  readonly hasEmbeddedFont: boolean;
  themes(): string[];
  detectType(text: string): "flowchart" | "sequence" | "state" | "er" | "class" | "gantt" | "gitgraph" | "mindmap"
    | "pie" | "xychart" | "timeline" | "quadrant" | "journey" | "packet" | "kanban" | "radar" | "treemap" | "sankey" | "unknown";
  png(text: string, options?: RenderOptions): Uint8Array;
  gif(text: string, options?: RenderOptions): Uint8Array;
  svg(text: string, options?: SvgOptions): string;
  rgba(text: string, options?: RenderOptions): RgbaImage;
  encodePng(rgba: Uint8Array | Uint8ClampedArray, width: number, height: number, colors?: number): Uint8Array;
  encodeGif(rgba: Uint8Array | Uint8ClampedArray, width: number, height: number, colors?: number): Uint8Array;
  /** TrueType (glyf) font; null restores the embedded DejaVu Sans. */
  setFont(bytes: Uint8Array | null): void;
  /** Noto Color Emoji (OpenType-SVG); null disables colour emoji (default). */
  setEmojiFont(bytes: Uint8Array | null): void;
  close(): void;
}
export default Nimaid;
