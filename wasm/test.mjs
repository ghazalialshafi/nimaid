// node wasm/test.mjs [path/to/native_reference.png]   - exercises the wasm build end to end
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { Nimaid, NimaidError } from "./nimaid.mjs";

const FLOW = "flowchart LR\n  A[Hello] --> B{Ok?}\n  B -->|yes| C[World]\n  B -->|no| A\n";
const n = await Nimaid.load();
const sig = (b, s) => Buffer.from(b.subarray(0, s.length)).toString("latin1") === s;
let t0 = performance.now();

assert.match(n.version, /^\d+\.\d+\.\d+$/); assert.ok(n.hasEmbeddedFont);
assert.deepEqual(n.themes(), ["default", "dark", "forest", "neutral", "base"]);
assert.equal(n.detectType("sequenceDiagram\nA->>B: x"), "sequence"); assert.equal(n.detectType("sankey-beta\n\nA,B,1"), "sankey"); assert.equal(n.detectType("???"), "unknown");
assert.ok(sig(n.png(FLOW), "\x89PNG")); assert.ok(sig(n.gif(FLOW), "GIF8"));
assert.ok(n.png(FLOW, { colors: 16 }).length < n.png(FLOW).length);
const svg = n.svg(FLOW); assert.ok(svg.startsWith("<svg") && !svg.includes("<text") && !svg.includes("\0"));
assert.ok(n.svg(FLOW, { liveText: true, theme: "dark" }).includes("<text"));
const a = n.rgba(FLOW, { scale: 1 }), b = n.rgba(FLOW, { scale: 2 });
assert.equal(a.data.length, a.width * a.height * 4); assert.ok(Math.abs(b.width - 2 * a.width) <= 1);
assert.ok(sig(n.encodePng(a.data, a.width, a.height), "\x89PNG"));
assert.throws(() => n.png("banana"), (e) => e instanceof NimaidError && e.status === 4);
assert.throws(() => n.png("flowchart LR\n A --> "), (e) => e.status === 3 && e.message.length > 0);
assert.throws(() => n.png(FLOW, { scale: -1 }), (e) => e.status === 1);
assert.throws(() => n.png("a\0b"), (e) => e.status === 1);
assert.ok(sig(n.png("flowchart LR\n  A[Grüße — 日本] --> B"), "\x89PNG"));
assert.throws(() => n.setFont(new Uint8Array([1, 2, 3])) || n.png(FLOW), (e) => e.status === 2);
n.setFont(null); assert.ok(n.png(FLOW).length > 100);                    // back to the embedded font
for (let i = 0; i < 30; i++) n.png(FLOW);                                // memory stays stable across calls

// every diagram type
for (const t of ["sequenceDiagram\n A->>B: hi", "stateDiagram-v2\n [*] --> S\n S --> [*]", "erDiagram\n C ||--o{ O : places",
  "classDiagram\n class A\n A <|-- B", "gantt\n dateFormat YYYY-MM-DD\n section S\n T :a, 2024-01-01, 3d",
  "gitGraph\n commit\n branch d\n commit\n checkout main\n merge d", "mindmap\n root((R))\n  A\n  B",
  'pie\n "A" : 1\n "B" : 2', "xychart-beta\n bar [1, 2]", "timeline\n 2020 : x", "quadrantChart\n P: [0.3, 0.6]",
  "journey\n section S\n T: 3: Me", 'packet\n 0-7: "a"', "kanban\n Todo\n  t[Task]", "radar-beta\n axis a, b, c\n curve x{1, 2, 3}",
  'treemap-beta\n "R"\n  "A": 1', "sankey-beta\n\nA,B,1"]) assert.ok(sig(n.png(t), "\x89PNG"), t);

// emoji (optional font path as 2nd argument)
const emojiFont = process.argv[3];
if (emojiFont && existsSync(emojiFont)) {
  const text = "flowchart LR\n  A[😀 Happy] --> B[🚀]";
  const plain = n.png(text); n.setEmojiFont(readFileSync(emojiFont)); const withEmoji = n.png(text);
  assert.notDeepEqual(plain, withEmoji); n.setEmojiFont(null); assert.deepEqual(n.png(text), plain);
  console.log("emoji font from memory: ok");
}

// determinism, and byte-equality with the native build when a reference is given
assert.deepEqual(n.png(FLOW), n.png(FLOW));
const ref = process.argv[2];
if (ref && existsSync(ref)) {
  const seq = readFileSync(new URL("../docs/examples/07-sequence.mmd", import.meta.url), "utf8");
  const same = Buffer.compare(Buffer.from(n.png(seq)), readFileSync(ref)) === 0;
  console.log(same ? "wasm PNG is byte-identical to the native build" : "NOTE: wasm PNG differs from native (floating-point rounding)");
  assert.ok(same);
}
n.close();
console.log(`wasm tests passed in ${(performance.now() - t0).toFixed(0)} ms`);
