// Re-runs each pre-layout graph dumped by nimaid through the real dagre-d3-es and diffs positions.
import fs from 'fs';
import * as graphlib from 'dagre-d3-es/src/graphlib/index.js';
import { layout } from 'dagre-d3-es/src/dagre/index.js';
const lines = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(l => JSON.parse(l));
let worst = 0, bad = 0, total = 0;
for (let i = 0; i < lines.length; i += 2) {
  const pre = lines[i], post = lines[i + 1];
  const g = new graphlib.Graph({ multigraph: true, compound: true });
  g.setGraph({ ...pre.graph });
  g.setDefaultEdgeLabel(() => ({}));
  for (const n of pre.nodes) g.setNode(n.id, { width: n.width, height: n.height });
  for (const n of pre.nodes) if (n.parent) g.setParent(n.id, n.parent);
  for (const e of pre.edges)
    g.setEdge(e.v, e.w, { minlen: e.minlen, weight: e.weight, width: e.width, height: e.height, labelpos: e.labelpos }, e.name);
  layout(g);
  for (const n of post.nodes) {
    const r = g.node(n.id); total++;
    const d = Math.max(Math.abs(r.x - n.x), Math.abs(r.y - n.y), Math.abs(r.width - n.width), Math.abs(r.height - n.height));
    worst = Math.max(worst, d);
    if (d > 0.01) { bad++; if (bad <= 12) console.log(`[${pre.tag}] ${n.id}: ref (${r.x.toFixed(1)},${r.y.toFixed(1)} ${r.width.toFixed(1)}x${r.height.toFixed(1)}) ours (${n.x.toFixed(1)},${n.y.toFixed(1)} ${n.width.toFixed(1)}x${n.height.toFixed(1)})`); }
  }
}
console.log(`graphs=${lines.length/2} nodes=${total} mismatching=${bad} worstDelta=${worst.toFixed(3)}`);
