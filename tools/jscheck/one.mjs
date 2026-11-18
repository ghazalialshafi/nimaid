import fs from 'fs';
import { execFileSync } from 'child_process';
import * as graphlib from 'dagre-d3-es/src/graphlib/index.js';
import { layout } from 'dagre-d3-es/src/dagre/index.js';
const spec = JSON.parse(fs.readFileSync(process.argv[2]));
const g = new graphlib.Graph({ multigraph: true, compound: true });
g.setGraph({ ...spec.graph }); g.setDefaultEdgeLabel(() => ({}));
for (const n of spec.nodes) g.setNode(n.id, { width: n.width, height: n.height });
for (const n of spec.nodes) if (n.parent) g.setParent(n.id, n.parent);
for (const e of spec.edges) g.setEdge(e.v, e.w, { minlen: e.minlen, weight: e.weight, width: e.width, height: e.height, labelpos: e.labelpos }, e.name);
layout(g);
const out = JSON.parse(execFileSync('/home/claude/proj/bin/dagrerun', [process.argv[2]]).toString());
for (const n of out.nodes) { const r = g.node(n.id); console.log(n.id.padEnd(4), 'ref', r.x.toFixed(1), r.y.toFixed(1), '| ours', n.x.toFixed(1), n.y.toFixed(1)); }
for (const e of out.edges) { const r = g.edge(spec.edges.find(x=>x.name===e.name).v, spec.edges.find(x=>x.name===e.name).w, e.name); console.log(e.name, 'ref', JSON.stringify(r.points.map(p=>[+p.x.toFixed(1),+p.y.toFixed(1)])), 'ours', JSON.stringify(e.points.map(p=>[+p.x.toFixed(1),+p.y.toFixed(1)]))); }
