#!/usr/bin/env node
// tools/webkit-measure.mjs
//
// 在 WebKit（或 Chromium）量指定 selector 的座標尺寸，並算相鄰 selector 的垂直間距。
// 用來驗「照片到名字 20px」「副標到內文 48px」這類設計稿數值有沒有真的落在 iOS 上，
// 以及輪播卡「一張滿寬置中」之類的定位。
//
// 用法：
//   node tools/webkit-measure.mjs <url> --width=375 [--engine=webkit|chromium|both] [--all] [--style=font-size,gap] <selector> [<selector> …]
//   例：node tools/webkit-measure.mjs http://<站>.local/team/ --width=375 ".st-card__photo" ".st-card__name"
//
// 輸出每個 selector 第一個符合元素的 x／y／w／h（--all 則列全部符合的元素），
// 相鄰兩個 selector 之間印「上一個的 bottom → 這一個的 top」的間距。
// --style 附帶列出指定的 computed style（逗號分隔屬性名）。
// --engine=both 時兩個引擎各印一份，數值不同的地方就是引擎差異。
//
// exit code：0=量到　1=有 selector 找不到元素　2=環境/執行錯誤

import { parseArgs, enginesFrom, launch, openPage, describeElementFn } from './_webkit-lib.mjs';

const { positional, opts } = parseArgs(process.argv.slice(2));
const [url, ...selectors] = positional;
if (!url || !selectors.length) {
  console.error('用法：node tools/webkit-measure.mjs <url> --width=375 [--engine=…] [--all] [--style=prop,prop] <selector> [<selector> …]');
  process.exit(2);
}
const width = Number(opts.width || 375);
let engines;
try { engines = enginesFrom(opts.engine); } catch (e) { console.error(e.message); process.exit(2); }
const styleProps = opts.style ? String(opts.style).split(',').map((s) => s.trim()).filter(Boolean) : [];
const all = !!opts.all;

const probe = `
(function (selectors, styleProps, all) {
  const describe = ${describeElementFn};
  return selectors.map((sel) => {
    let els;
    try { els = [...document.querySelectorAll(sel)]; } catch (e) { return { sel, error: e.message }; }
    if (!all) els = els.slice(0, 1);
    return {
      sel,
      matches: els.map((el) => {
        const r = el.getBoundingClientRect();
        const cs = getComputedStyle(el);
        const style = {};
        for (const p of styleProps) style[p] = cs.getPropertyValue(p);
        return { desc: describe(el), x: +r.left.toFixed(1), y: +(r.top + window.scrollY).toFixed(1), w: +r.width.toFixed(1), h: +r.height.toFixed(1), style };
      }),
    };
  });
})`;

let missing = false;
for (const name of engines) {
  const { browser } = await launch(name);
  try {
    const { page, context } = await openPage(browser, url, width, opts);
    try {
      const data = await page.evaluate(`(${probe})(${JSON.stringify(selectors)}, ${JSON.stringify(styleProps)}, ${all})`);
      const cw = await page.evaluate('document.documentElement.clientWidth');
      console.log(`\n═══ [${name}] ${width}px（clientWidth=${cw}）═══`);
      let prev = null;
      for (const item of data) {
        if (item.error) { console.log(`✗ ${item.sel}：selector 無效（${item.error}）`); missing = true; prev = null; continue; }
        if (!item.matches.length) { console.log(`✗ ${item.sel}：找不到元素`); missing = true; prev = null; continue; }
        for (const m of item.matches) {
          const styleStr = Object.keys(m.style).length ? '   ' + Object.entries(m.style).map(([k, v]) => `${k}=${v}`).join(' ') : '';
          console.log(`${item.sel}\n   ${m.desc}\n   x=${m.x} y=${m.y} w=${m.w} h=${m.h}  right=${(m.x + m.w).toFixed(1)}  centerX=${(m.x + m.w / 2).toFixed(1)}${styleStr}`);
        }
        const first = item.matches[0];
        if (prev) {
          const gap = +(first.y - (prev.y + prev.h)).toFixed(1);
          console.log(`   ↕ 與上一個（${prev.sel}）底部的間距：${gap}px`);
        }
        prev = { ...first, sel: item.sel };
      }
    } finally {
      await context.close();
    }
  } catch (e) {
    console.error(`[${name}] 量測失敗：${e.message}`);
    await browser.close();
    process.exit(2);
  }
  await browser.close();
}
process.exit(missing ? 1 : 0);
