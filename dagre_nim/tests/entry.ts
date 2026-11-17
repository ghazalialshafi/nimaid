import {Graph} from "@dagrejs/graphlib";
import {layout} from "./src/layout";
import * as fs from "fs";
const spec = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const g: any = new Graph({multigraph: true, compound: true});
g.setGraph(Object.assign({}, spec.graph));
g.setDefaultEdgeLabel(() => ({}));
for (const n of spec.nodes) { const nl: any = {width: n.width || 0, height: n.height || 0}; if (n.rankdir) nl.rankdir = n.rankdir; g.setNode(n.id, nl); }
for (const n of spec.nodes) if (n.parent) g.setParent(n.id, n.parent);
const addEdge = (e: any) => {
  const l: any = {};
  for (const k of ["minlen","weight","width","height","labelpos","labeloffset"]) if (e[k] !== undefined) l[k] = e[k];
  g.setEdge(e.v, e.w, l, e.name);
};
for (const e of spec.edges) addEdge(e);
const opts: any = {};
if (spec.corePath) opts.corePath = spec.corePath;
if (spec.customOrder) opts.customOrder = (gr: any, order: any) => order(gr, {disableOptimalOrderHeuristic: true});
if (spec.useDynamic !== undefined) opts.useDynamic = spec.useDynamic;
layout(g, opts);
if (spec.second) { for (const e of spec.second) addEdge(e); layout(g, opts); }
const o: any = {width: g.graph().width, height: g.graph().height, nodes: {}, edges: []};
for (const v of g.nodes()) { const n = g.node(v); o.nodes[v] = {x: n.x, y: n.y, w: n.width, h: n.height}; }
for (const e of g.edges()) { const l = g.edge(e); const ej: any = {v: e.v, w: e.w, name: e.name || "", points: (l.points||[]).map((p: any) => [p.x, p.y])}; if (l.x !== undefined) {ej.x = l.x; ej.y = l.y;} o.edges.push(ej); }
console.log(JSON.stringify(o));
