#!/usr/bin/env node
// tools/webkit-shot.mjs
//
// 用 WebKit（或 Chromium）對指定 URL 截圖。沒給 --selector 就拍整頁（full page），給了就只拍該元素。
// 用途：Chromium 看起來正常、但使用者手機截圖有問題時，先用這支在 WebKit 拍一張
// 對照，確認是引擎差異還是實機／版本差異，再決定往哪邊追。
// 部署前後的截圖 diff 以 WebKit 為準：Chromium 的整頁圖會把固定定位元素重複畫到錯的位置。
//
// 用法：
//   node tools/webkit-shot.mjs <url> --out=<path.png> [--width=375] [--engine=webkit|chromium|both] [--selector=".st-hero"] [--dpr=2]
//   例：node tools/webkit-shot.mjs http://<站>.local/team/ --width=375 --out=/tmp/team-wk.png
//   --engine=both 時檔名自動插入引擎名：team-wk.webkit.png／team-wk.chromium.png
//
// Playwright 的 locator.screenshot() 與 fullPage 自己處理捲動與拼接，沒有 CDP clip 在大尺寸
// 回白圖的問題。元素截圖偶爾會對到錯的區域（固定 header／sticky 影響），截整個父區塊比較穩。
// 輸出 deviceScaleFactor 預設 2（圖是 CSS 尺寸的兩倍）。
// reveal 已全開、lazy 圖已轉 eager（見 _webkit-lib.mjs openPage），拍到的是最終畫面。
//
// exit code：0=成功　1=selector 找不到　2=環境/執行錯誤

import { parseArgs, enginesFrom, launch, openPage } from './_webkit-lib.mjs';

const { positional, opts } = parseArgs(process.argv.slice(2));
const url = positional[0];
const out = opts.out;
if (!url || !out) {
  console.error('用法：node tools/webkit-shot.mjs <url> --out=<path.png> [--width=375] [--engine=…] [--selector=…]');
  process.exit(2);
}
const width = Number(opts.width || 375);
let engines;
try { engines = enginesFrom(opts.engine); } catch (e) { console.error(e.message); process.exit(2); }

function outFor(name) {
  if (engines.length === 1) return String(out);
  return String(out).replace(/(\.png)?$/i, `.${name}.png`);
}

for (const name of engines) {
  const { browser } = await launch(name);
  try {
    const { page, context } = await openPage(browser, url, width, opts);
    try {
      const path = outFor(name);
      if (opts.selector) {
        const loc = page.locator(String(opts.selector)).first();
        if ((await loc.count()) === 0) {
          console.error(`[${name}] 找不到 selector：${opts.selector}`);
          process.exit(1);
        }
        await loc.scrollIntoViewIfNeeded();
        await loc.screenshot({ path });
        const box = await loc.boundingBox();
        console.log(`[${name}] ${path}  元素 ${box?.width.toFixed(0)}×${box?.height.toFixed(0)} CSS px`);
      } else {
        await page.screenshot({ path, fullPage: true });
        const h = await page.evaluate('document.documentElement.scrollHeight');
        console.log(`[${name}] ${path}  整頁 ${width}×${h} CSS px`);
      }
    } finally {
      await context.close();
    }
  } catch (e) {
    console.error(`[${name}] 截圖失敗：${e.message}`);
    await browser.close();
    process.exit(2);
  }
  await browser.close();
}
