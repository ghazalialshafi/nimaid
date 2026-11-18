import fs from 'fs';
const out = {};
const keys = ['background','mainBkg','nodeBkg','nodeBorder','border1','border2','secondBkg','clusterBkg','clusterBorder','lineColor','arrowheadColor','textColor','titleColor','edgeLabelBackground','primaryColor','primaryBorderColor','primaryTextColor','secondaryColor','tertiaryColor','nodeTextColor','noteBkgColor','noteBorderColor','noteTextColor','actorBkg','actorBorder','actorTextColor','actorLineColor','signalColor','signalTextColor','labelBoxBkgColor','labelBoxBorderColor','labelTextColor','loopTextColor','activationBkgColor','activationBorderColor','sequenceNumberColor','fontSize','fontFamily'];
for (const t of ['default','dark','forest','neutral','base']) {
  const m = await import(`./theme-${t}.js`);
  const th = m.getThemeVariables ? m.getThemeVariables() : m.default.getThemeVariables();
  out[t] = {};
  for (const k of keys) if (th[k] !== undefined) out[t][k] = th[k];
}
fs.writeFileSync('themes.json', JSON.stringify(out, null, 1));
console.log(JSON.stringify(out.dark, null, 0).slice(0, 700));
