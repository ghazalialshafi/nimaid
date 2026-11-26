# nimaid (WebAssembly)

**Mermaid diagrams to PNG, GIF, SVG or raw pixels — in Node, Deno, Bun and browsers. No dependencies, no headless browser.**
The renderer is [nimaid](https://github.com/ghazalialshafi/nimaid) (pure Nim) compiled to a 2 MB WebAssembly module (≈ 0.8 MB gzipped).
DejaVu Sans is built in; colour emoji are opt-in.

**[Try it in your browser](https://ghazalialshafi.github.io/nimaid/playground/)** · [Website](https://ghazalialshafi.github.io/nimaid/) · [Source and docs](https://github.com/ghazalialshafi/nimaid)

```sh
npm install nimaid
```

```js
import { Nimaid } from "nimaid";
import { writeFileSync } from "node:fs";

const nimaid = await Nimaid.load();                       // loads nimaid.wasm next to nimaid.mjs
writeFileSync("a.png", nimaid.png("flowchart LR\n A[Hello] --> B[World]", { theme: "dark", scale: 2 }));
const svg = nimaid.svg("sequenceDiagram\n Alice->>Bob: Hi");           // string
```

In a browser, serve `nimaid.mjs` and `nimaid.wasm` (content-type `application/wasm`) and `Nimaid.load("/path/nimaid.wasm")`;
see `demo.html` (open it through any static file server). Draw pixels with
`const {width, height, data} = nimaid.rgba(text); ctx.putImageData(new ImageData(data, width, height), 0, 0);`.

| Method | Result |
|---|---|
| `png(text, {scale, theme, colors})` / `gif(...)` | `Uint8Array` |
| `svg(text, {theme, liveText})` | `string` |
| `rgba(text, {scale, theme})` | `{width, height, data}` straight-alpha RGBA8 |
| `encodePng/encodeGif(rgba, w, h, colors)` | encode your own pixels |
| `setFont(bytes)` / `setEmojiFont(bytes)` | TrueType (glyf) font / Noto Color Emoji (OpenType-SVG); `null` resets |
| `detectType(text)`, `themes()`, `version` | info |

Errors are `NimaidError` with a numeric `status` (3 = syntax error, 4 = unsupported diagram type, …) and a message that says what is wrong.
Output is deterministic and byte-identical to the native nimaid build. There is no file-system access in the wasm sandbox: input and output are memory buffers.

MIT licensed; embeds DejaVu Sans (see THIRD_PARTY.md). Source, docs and the native C API / CLI / Python package: <https://github.com/ghazalialshafi/nimaid>.
