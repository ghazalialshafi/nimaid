// Renders one example per diagram type to SVG for the landing page.
// usage (next to nimaid.mjs / nimaid.wasm):  node gen_gallery.mjs ../examples gallery
import fs from "node:fs";
import { Nimaid } from "./nimaid.mjs";

const [dir, out] = process.argv.slice(2);
const MAP = { flowchart: "complex", sequence: "sequence", state: "state", er: "er", class: "class", gantt: "gantt", gitgraph: "gitgraph",
  mindmap: "mindmap", pie: "pie", xychart: "xychart", timeline: "timeline", quadrant: "quadrant", journey: "journey", packet: "packet",
  kanban: "kanban", radar: "radar", treemap: "treemap", sankey: "sankey" };
const n = await Nimaid.load();
fs.mkdirSync(out, { recursive: true });
for (const [kind, file] of Object.entries(MAP)) {
  const text = fs.readFileSync(`${dir}/${file}.mmd`, "utf8");
  if (n.detectType(text) !== kind) throw new Error(`${file}.mmd is ${n.detectType(text)}, expected ${kind}`);
  fs.writeFileSync(`${out}/${kind}.svg`, n.svg(text));
}
console.log(`rendered ${Object.keys(MAP).length} gallery images into ${out}`);
