// Delta-debugs a failing graph spec (from fuzz.mjs) down to a minimal reproduction.
import fs from 'fs';
import { execFileSync } from 'child_process';
import * as graphlib from 'dagre-d3-es/src/graphlib/index.js';
import { layout } from 'dagre-d3-es/src/dagre/index.js';
function run(spec) {
  const g = new graphlib.Graph({ multigraph: true, compound: true });
  g.setGraph({ ...spec.graph }); g.setDefaultEdgeLabel(() => ({}));
  for (const n of spec.nodes) g.setNode(n.id, { width: n.width, height: n.height });
  for (const n of spec.nodes) if (n.parent) g.setParent(n.id, n.parent);
  for (const e of spec.edges) g.setEdge(e.v, e.w, { minlen: e.minlen, weight: e.weight, width: e.width, height: e.height, labelpos: e.labelpos }, e.name);
  try { layout(g); } catch (e) { return null; }
  fs.writeFileSync('/tmp/shrink_in.json', JSON.stringify(spec));
  let out;
  try { out = JSON.parse(execFileSync('/home/claude/proj/bin/dagrerun', ['/tmp/shrink_in.json'], { timeout: 10000 }).toString()); } catch (e) { return true; }
  for (const n of out.nodes) { const r = g.node(n.id); if (r && (Math.abs(r.x - n.x) > .01 || Math.abs(r.y - n.y) > .01)) return true; }
  for (const e of out.edges) {
    const se = spec.edges.find(x => x.name === e.name); const r = g.edge(se.v, se.w, e.name);
    if (!r.points) continue;
    if (r.points.length !== e.points.length) return true;
    for (let k = 0; k < r.points.length; k++) if (Math.abs(r.points[k].x - e.points[k].x) > .01 || Math.abs(r.points[k].y - e.points[k].y) > .01) return true;
  }
  return false;
}
let spec = JSON.parse(fs.readFileSync(process.argv[2]));
if (run(spec) !== true) { console.log('input does not fail'); process.exit(0); }
let changed = true;
while (changed) {
  changed = false;
  for (let i = spec.edges.length - 1; i >= 0; i--) { const t = structuredClone(spec); t.edges.splice(i, 1); if (run(t) === true) { spec = t; changed = true; } }
  for (let i = spec.nodes.length - 1; i >= 0; i--) {
    const id = spec.nodes[i].id; if (spec.nodes.some(n => n.parent === id)) continue;
    const t = structuredClone(spec); t.nodes.splice(i, 1); t.edges = t.edges.filter(e => e.v !== id && e.w !== id);
    if (run(t) === true) { spec = t; changed = true; }
  }
  for (const e of spec.edges) { if (e.width || e.height || e.minlen !== 1) { const t = structuredClone(spec); const te = t.edges.find(x => x.name === e.name); te.width = 0; te.height = 0; te.minlen = 1; if (run(t) === true) { spec = t; changed = true; } } }
  for (const n of spec.nodes) if (n.width) { const t = structuredClone(spec); const tn = t.nodes.find(x => x.id === n.id); tn.width = 50; tn.height = 30; if (JSON.stringify(tn) !== JSON.stringify(n) && run(t) === true) { spec = t; changed = true; } }
}
fs.writeFileSync('/tmp/min.json', JSON.stringify(spec));
console.log(JSON.stringify({ rankdir: spec.graph.rankdir, nodes: spec.nodes.map(n => n.id + (n.parent ? '<' + n.parent : '')), edges: spec.edges.map(e => `${e.v}->${e.w}${e.minlen > 1 ? ' minlen' + e.minlen : ''}${e.width ? ' lbl' : ''}`) }));
