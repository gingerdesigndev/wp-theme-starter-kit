#!/usr/bin/env node
// tools/webkit-overflow.mjs
//
// 逐元素量水平溢出：對 .site-main 底下（找不到就 body）每個可見元素量 getBoundingClientRect()，
// right > clientWidth + 容差 或 left < -容差 就記為 offender；另附 document.scrollWidth。
//
// 為什麼要逐元素量、不能只看 scrollWidth：`overflow-x:clip` 會讓 scrollWidth 測不到溢出
// （docs/05-踩坑清單.md「負向測試的探針」）。為什麼要用 WebKit：見 _webkit-lib.mjs 檔頭。
//
// `--engine=both` 會用 WebKit 與 Chromium 各跑一次，並把**只在 WebKit 出現**的 offender
// 標出來——那些就是 iOS 專屬問題的第一嫌疑。
//
// 用法：
//   node tools/webkit-overflow.mjs <url> [--widths=320,375,414] [--engine=webkit|chromium|both] [--tol=0.5]
//   例：node tools/webkit-overflow.mjs http://<站>.local/category/news/ --engine=both --widths=375
//
// ⚠️ 輸出是「待裁決的候選」，不是「一定有 bug」：
//   100vw 滿版區塊會比 clientWidth 寬剛好一個捲軸寬；輪播軌道上視窗外的卡片本來就在框外。
//   看的人要自己排除。WebKit-only 的項目比較值得追，兩邊都有的多半是這兩類。
//
// exit code：0=全過　1=有元素溢出　2=環境/執行錯誤

import { parseArgs, enginesFrom, widthsFrom, launch, openPage, describeElementFn } from './_webkit-lib.mjs';

const { positional, opts } = parseArgs(process.argv.slice(2));
const url = positional[0];
if (!url) {
  console.error('用法：node tools/webkit-overflow.mjs <url> [--widths=320,375] [--engine=webkit|chromium|both] [--tol=0.5]');
  process.exit(2);
}

let engines, widths;
try {
  engines = enginesFrom(opts.engine);
  widths = widthsFrom(opts.widths);
} catch (e) {
  console.error(e.message);
  process.exit(2);
}
const TOL = Number(opts.tol ?? 0.5);

// 在頁面內執行：回 { clientWidth, scrollWidth, offenders:[{desc,left,right,width}] }
const probe = `
(function (TOL) {
  const describe = ${describeElementFn};
  const cw = document.documentElement.clientWidth;
  const root = document.querySelector('.site-main') || document.body;
  const offenders = [];
  for (const el of root.querySelectorAll('*')) {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    if (r.right > cw + TOL || r.left < -TOL) {
      offenders.push({ desc: describe(el), left: +r.left.toFixed(1), right: +r.right.toFixed(1), width: +r.width.toFixed(1) });
    }
  }
  // 同一個 desc（同標籤同 class 的兄弟，典型是輪播軌道上的 20 張卡）併成一行，免得洗版；
  // 保留張數與最左／最右，看得出是「一排卡在框外」還是「一個元素破出」。
  const byDesc = new Map();
  for (const o of offenders) {
    const g = byDesc.get(o.desc);
    if (!g) byDesc.set(o.desc, { ...o, count: 1 });
    else { g.count++; g.left = Math.min(g.left, o.left); g.right = Math.max(g.right, o.right); }
  }
  return { clientWidth: cw, scrollWidth: document.documentElement.scrollWidth, offenders: [...byDesc.values()] };
})`;

// results[engine][width] = probe 結果
const results = {};
let hadError = false;
for (const name of engines) {
  const { browser } = await launch(name);
  results[name] = {};
  try {
    for (const w of widths) {
      const { page, context } = await openPage(browser, url, w, opts);
      try {
        results[name][w] = await page.evaluate(`(${probe})(${TOL})`);
      } catch (e) {
        hadError = true;
        console.error(`[${name} ${w}] 量測失敗：${e.message}`);
      } finally {
        await context.close();
      }
    }
  } finally {
    await browser.close();
  }
}

const fmt = (o) => `${o.desc}   left=${o.left} right=${o.right} w=${o.width}${o.count > 1 ? `  ×${o.count}` : ''}`;
let anyOffender = false;
for (const w of widths) {
  console.log(`\n═══ ${w}px ═══`);
  for (const name of engines) {
    const r = results[name]?.[w];
    if (!r) continue;
    const scrollFlag = r.scrollWidth > r.clientWidth ? '  ⚠️ 頁面本身有水平捲動' : '';
    const total = r.offenders.reduce((n, o) => n + o.count, 0);
    console.log(`[${name}] clientWidth=${r.clientWidth} scrollWidth=${r.scrollWidth}${scrollFlag}  offenders=${total}（${r.offenders.length} 組）`);
    if (r.offenders.length) anyOffender = true;
  }
  if (engines.length === 2) {
    const wk = new Set((results.webkit?.[w]?.offenders || []).map((o) => o.desc));
    const cr = new Set((results.chromium?.[w]?.offenders || []).map((o) => o.desc));
    const onlyWk = (results.webkit?.[w]?.offenders || []).filter((o) => !cr.has(o.desc));
    const both = (results.webkit?.[w]?.offenders || []).filter((o) => cr.has(o.desc));
    if (onlyWk.length) {
      console.log(`  ▶ 只在 WebKit 溢出（iOS 專屬嫌疑）：${onlyWk.length}`);
      for (const o of onlyWk) console.log(`     ${fmt(o)}`);
    }
    if (both.length) {
      console.log(`  ▷ 兩邊都溢出（多半是 100vw 滿版或輪播卡，自行排除）：${both.length}`);
      for (const o of both) console.log(`     ${fmt(o)}`);
    }
    const onlyCr = (results.chromium?.[w]?.offenders || []).filter((o) => !wk.has(o.desc));
    if (onlyCr.length) console.log(`  ▷ 只在 Chromium 溢出：${onlyCr.length}（多半是 100vw 捲軸寬那類，看的人自己排除）`);
  } else {
    const name = engines[0];
    for (const o of results[name]?.[w]?.offenders || []) {
      console.log(`     ${fmt(o)}`);
    }
  }
}

if (hadError) process.exit(2);
console.log(anyOffender ? '\n結果：有元素溢出（見上，自行裁決哪些是真 bug）' : '\n結果：全部 PASS');
process.exit(anyOffender ? 1 : 0);
