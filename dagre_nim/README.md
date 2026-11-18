# dagre-nim

A Nim port of [dagre](https://github.com/dagrejs/dagre) (directed graph layout). Pure Nim, stdlib only (Nim >= 2.0).

Pipeline (same as dagre): self-edge removal -> acyclic (DFS / greedy FAS) -> nesting graph ->
network-simplex ranking -> edge-label proxies -> normalize (dummy nodes) -> border segments
-> crossing minimisation (barycenter sweeps, subgraph + constraint handling) ->
Brandes-Köpf x positioning -> y positioning -> undo/translate/edge intersections.

## Use
```nim
import src/dagre
let g = newGraph(multigraph = true, compound = true)
g.label.rankdir = "LR"                       # nodesep, edgesep, ranksep, marginx/y, acyclicer,
                                             # ranker, align, rankalign are also supported
g.setNode("a", newNodeLabel(50, 30))         # width, height
g.setNode("b", newNodeLabel(50, 30))
g.setEdge("a", "b", newEdgeLabel(minlen = 1, weight = 1, width = 0, height = 0))
g.setParent("b", "cluster")                  # compound graphs
layout(g)                                    # results written back into g
# g.node(v).x/.y, g.edge(e).points / .x / .y, g.label.width / .height
```
See `example.nim`. `LayoutOptions` (`constraints`, `disableOptimalOrderHeuristic`) can be passed to `layout`.

## Features
Everything in the supplied dagre TypeScript fork is implemented:
- full dagre pipeline (acyclic DFS/greedy, network simplex / tight-tree / longest-path rankers,
  compound graphs, edge labels with `labelpos`/`labeloffset`, self-loops, multigraphs, Brandes-Köpf with all `align` modes, `rankalign`),
- **per-cluster `rankdir`** (`g.node("cluster").rankdir = "LR"`): the cluster is laid out in isolation and placed in the parent,
- **`LayoutOptions.corePath`**: align edges along a chosen path first,
- **`LayoutOptions.customOrder`** / `constraints` / `disableOptimalOrderHeuristic`,
- **dynamic re-layout** (`useDynamic`, on by default): calling `layout()` again on the same graph reuses the previous run for stability.

## Layout of the code
- `src/dagre.nim` – public entry; `src/dagre/*.nim` – graphlib, util, acyclic, rank, nesting, normalize, order, position, layout.

## Performance
The hot paths run on flat integer arrays instead of string-keyed graphs: network simplex (incremental cut values,
subtree-only renumbering, boundary-only entering-edge search), ordering (layer graphs on ids) and
Brandes-Köpf. The graph core uses O(1) child removal. Benchmarks vs the supplied TS (same output, checked):

| graph | JS | Nim |
|---|---|---|
| 1,500 nodes / 3,000 edges | 18.3 s | 0.16 s (~115x) |
| 6,000 nodes / 12,000 edges | (minutes) | ~1.0 s |

Build with `-d:release` (or `-d:danger` for ~10% more, no bounds checks).
`-d:dagreProfile` + `dumpProfile()` prints per-phase timings; `-d:dagreVerifyNS` cross-checks the incremental
network-simplex updates against a full recompute.

## Verification
`tests/fuzz.py` generates random graphs (clusters incl. per-cluster rankdir, self-loops, multi-edges, edge labels,
all rankdirs, greedy acyclicer, all rankers, alignments, corePath, customOrder, re-layout after edits, up to 80 nodes)
and diffs the Nim output against the supplied TS dagre (bundled with esbuild). ~6,000 random graphs and the large
benchmarks match to 1e-6.

Setup for the test:
```
mkdir ref && cd ref && npm i @dagrejs/graphlib esbuild && cp -r <dagre lib dir> src
cp ../tests/entry.ts . && npx esbuild entry.ts --bundle --platform=node --outfile=ref.js
cd ../tests && nim c -d:release driver.nim && python3 fuzz.py 0 300
```

## Known differences from JS
- Node ids are kept in insertion order. JS objects iterate integer-like ids ("1","2") in numeric order, so purely
  numeric ids can order ties differently. Use non-numeric ids to get identical results.
- Weights are floats, minlen is int. Nodes a cluster layout leaves unpositioned report 0 instead of undefined.
