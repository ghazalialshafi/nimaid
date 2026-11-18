// Differential fuzz: random (compound) graphs through dagre-d3-es vs dagre_nim.
import fs from 'fs';
import { execFileSync } from 'child_process';
import * as graphlib from 'dagre-d3-es/src/graphlib/index.js';
import { layout } from 'dagre-d3-es/src/dagre/index.js';

let seed = Number(process.argv[2] ?? 1);
const N = Number(process.argv[3] ?? 200);
const compound = (process.argv[4] ?? 'c') === 'c';
const verbose = process.argv.includes('-v');
function rnd() { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; }
const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));

function makeGraph() {
  const nn = ri(2, 9);
  const nodes = [];
  const rankdir = ['TB', 'LR', 'BT', 'RL'][ri(0, 3)];
  const groups = [];
  if (compound) { const ng = ri(0, 3); for (let i = 0; i < ng; i++) groups.push('G' + i); }
  for (const g of groups) nodes.push({ id: g, parent: '', width: 0, height: 0 });
  // nest some groups
  for (let i = 1; i < groups.length; i++) if (rnd() < 0.4) nodes[i].parent = groups[ri(0, i - 1)];
  const leaves = [];
  for (let i = 0; i < nn; i++) {
    const id = 'n' + i;
    const parent = groups.length && rnd() < 0.7 ? groups[ri(0, groups.length - 1)] : '';
    nodes.push({ id, parent, width: ri(30, 120), height: ri(20, 60) });
    leaves.push(id);
  }
  const edges = [];
  const ne = ri(1, nn * 2);
  for (let i = 0; i < ne; i++) {
    const v = leaves[ri(0, nn - 1)], w = leaves[ri(0, nn - 1)];
    if (v === w) continue;
    const lbl = rnd() < 0.3;
    edges.push({ v, w, name: 'e' + i, minlen: rnd() < 0.15 ? 2 : 1, weight: 1,
      width: lbl ? ri(20, 80) : 0, height: lbl ? ri(14, 24) : 0, labelpos: 'c' });
  }
  return { graph: { rankdir, nodesep: 50, ranksep: 50, marginx: 8, marginy: 8 }, nodes, edges };
}

let fails = 0, firstFail = null;
for (let it = 0; it < N; it++) {
  const spec = makeGraph();
  const g = new graphlib.Graph({ multigraph: true, compound: true });
  g.setGraph({ ...spec.graph });
  g.setDefaultEdgeLabel(() => ({}));
  for (const n of spec.nodes) g.setNode(n.id, { width: n.width, height: n.height });
  for (const n of spec.nodes) if (n.parent) g.setParent(n.id, n.parent);
  for (const e of spec.edges) g.setEdge(e.v, e.w, { minlen: e.minlen, weight: e.weight, width: e.width, height: e.height, labelpos: e.labelpos }, e.name);
  let ok = true, msg = '';
  try { layout(g); } catch (e) { continue; }
  fs.writeFileSync('/tmp/fuzz_in.json', JSON.stringify(spec));
  let out;
  try { out = JSON.parse(execFileSync('/home/claude/proj/bin/dagrerun', ['/tmp/fuzz_in.json'], { timeout: 10000 }).toString()); }
  catch (e) { ok = false; msg = 'nim crashed/timeout'; }
  if (ok) {
    for (const n of out.nodes) {
      const r = g.node(n.id);
      if (!r) continue;
      const d = Math.max(Math.abs(r.x - n.x), Math.abs(r.y - n.y), Math.abs(r.width - n.width), Math.abs(r.height - n.height));
      if (d > 0.01) { ok = false; msg = `node ${n.id}: ref (${r.x.toFixed(1)},${r.y.toFixed(1)}) ours (${n.x.toFixed(1)},${n.y.toFixed(1)})`; break; }
    }
  }
  if (ok) for (const e of out.edges) {
    const r = g.edge(e.name ? { v: spec.edges.find(x => x.name === e.name).v, w: spec.edges.find(x => x.name === e.name).w, name: e.name } : null);
    if (!r || !r.points) continue;
    if (r.points.length !== e.points.length) { ok = false; msg = `edge ${e.name}: ${r.points.length} vs ${e.points.length} points`; break; }
    for (let k = 0; k < r.points.length; k++) {
      if (Math.abs(r.points[k].x - e.points[k].x) > 0.01 || Math.abs(r.points[k].y - e.points[k].y) > 0.01) { ok = false; msg = `edge ${e.name} pt ${k}: ref (${r.points[k].x.toFixed(1)},${r.points[k].y.toFixed(1)}) ours (${e.points[k].x.toFixed(1)},${e.points[k].y.toFixed(1)})`; break; }
    }
    if (!ok) break;
  }
  if (!ok) { fails++; if (!firstFail) { firstFail = spec; fs.writeFileSync('/tmp/fuzz_fail.json', JSON.stringify(spec, null, 1)); } if (verbose && fails <= 8) console.log(`#${it}: ${msg}  (nodes=${spec.nodes.length} edges=${spec.edges.length} dir=${spec.graph.rankdir})`); }
}
console.log(`${compound ? 'compound' : 'flat'} graphs=${N} failures=${fails}`);
