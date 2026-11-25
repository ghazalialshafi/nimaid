// Regenerates src/nimaid/data/chart_themes.json (all variables of Mermaid's five themes, nested xyChart flattened).
//
//   1. mkdir /tmp/thm && cd /tmp/thm && npm init -y && npm i khroma && echo '{"type":"module"}' > package.json
//   2. cp <mermaid>/packages/mermaid/src/themes/theme-{default,dark,forest,neutral,base,helpers}.js .
//      cp <this repo>/tools/themes/erDiagram-oldHardcodedValues.js .
//   3. cp <this repo>/tools/themes/dump_chart_themes.mjs . && node dump_chart_themes.mjs
//   4. copy the resulting chart_themes.json to <this repo>/src/nimaid/data/
import fs from 'fs';
const out = {};
for (const t of ['default', 'dark', 'forest', 'neutral', 'base']) {
  const m = await import(`./theme-${t}.js`);
  const vars = (m.getThemeVariables ?? m.default?.getThemeVariables)();
  const o = {};
  const put = (k, v) => {
    if (v === null || v === undefined || k.endsWith('dropShadow')) return;
    if (['string', 'number', 'boolean'].includes(typeof v)) o[k] = String(v);
    else if (Array.isArray(v)) o[k] = v.join(',');
    else if (typeof v === 'object') for (const [kk, vv] of Object.entries(v)) put(`${k}.${kk}`, vv);   // nested groups: xyChart.*, radar.*, packet.*, ...
  };
  for (const [k, v] of Object.entries(vars)) put(k, v);
  out[t] = o;
}
fs.writeFileSync('chart_themes.json', JSON.stringify(out));
console.log('wrote chart_themes.json:', Object.keys(out.default).length, 'variables per theme');
