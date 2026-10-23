// tools/_webkit-lib.mjs
//
// tools/webkit-*.mjs 三支腳本共用的啟動模組：解參數 → 開 Playwright 瀏覽器 →
// 設視窗 → 導頁 → 把動畫關掉、reveal 全開、lazy 圖轉 eager。
// 只有這一份實作，三支腳本都 import 它；「每支各寫一份」會在改判準時漏改。
//
// ⚠️ 為什麼要用 WebKit 量（實案，見 docs/05-踩坑清單.md「只有 Safari 壞的 bug」）：
//   headless Chrome 量六個寬度全 PASS，客戶的 iPhone 卻右邊破出視窗——WebKit 把
//   側欄 width:100% 圖片的最小寬算成原始尺寸、把 grid 的 1fr 欄撐開；另一頁的
//   @container 在舊 WebKit 把整張卡塌成一字一行。這些只有真的用 WebKit 排一次版才看得到。
//   客戶端有 iPhone 用戶，「Chromium 全 PASS」不代表 iOS 沒事。
//
// ⚠️ 它能與不能重現什麼：Playwright 的 WebKit 是**最新版** WebKit（等同新 iOS Safari），
//   抓得到「引擎差異」（Chromium 對 vs WebKit 錯），抓不到「舊版本差異」
//   （停在舊 iOS 的機器）。舊機專屬問題還是要拿實機看。
//
// 相依：tools/package.json 的 playwright；WebKit 引擎本體在
//   ~/Library/Caches/ms-playwright/webkit-*（`npx playwright install webkit` 會裝到那裡，
//   不在 repo 內）。第一次用：cd tools && npm install && npx playwright install webkit。
//   Chromium 對照組走機器上已裝的 Google Chrome（channel:'chrome'），不另外下載。
//
// deploy.sh 整個排除 tools/，node_modules 由 .gitignore 擋，都不會上正式站。

import { chromium, webkit } from 'playwright';

/** 六個慣例寬度（docs/01-切版SOP.md 驗證步驟用的那組再加 414／1024） */
export const DEFAULT_WIDTHS = [320, 375, 414, 768, 1024, 1440];

/**
 * 解 argv：位置參數 + `--key=value`／`--flag`。
 * 回 { positional: [...], opts: {key: value|true} }
 */
export function parseArgs(argv) {
  const positional = [];
  const opts = {};
  for (const a of argv) {
    if (a.startsWith('--')) {
      const eq = a.indexOf('=');
      if (eq === -1) opts[a.slice(2)] = true;
      else opts[a.slice(2, eq)] = a.slice(eq + 1);
    } else {
      positional.push(a);
    }
  }
  return { positional, opts };
}

/** `--engine=webkit|chromium|both` → 要跑的引擎名單；預設只跑 webkit */
export function enginesFrom(opt) {
  const v = (opt || 'webkit').toLowerCase();
  if (v === 'both') return ['webkit', 'chromium'];
  if (v === 'webkit' || v === 'chromium') return [v];
  throw new Error(`--engine 只接受 webkit／chromium／both，收到「${opt}」`);
}

/** `--widths=320,375` → [320, 375]；沒給用 DEFAULT_WIDTHS */
export function widthsFrom(opt) {
  if (!opt) return DEFAULT_WIDTHS;
  const ws = String(opt).split(',').map((s) => Number(s.trim())).filter((n) => Number.isFinite(n) && n > 0);
  if (!ws.length) throw new Error(`--widths 解不出任何寬度：「${opt}」`);
  return ws;
}

/**
 * 開一個瀏覽器。回傳 { browser, name }。呼叫端負責 browser.close()。
 * WebKit 用 Playwright 內建版本；Chromium 走機器上的 Google Chrome（見函式內註解）。
 */
export async function launch(name) {
  if (name === 'chromium') {
    // 用機器上已裝的 Google Chrome（channel:'chrome'），不下載 Playwright 自帶的 Chromium：
    // 那份跟 playwright 套件版本綁死，每次升版都要再抓 100MB；Chromium 這裡只是要一份對照組。
    const browser = await chromium.launch({ headless: true, channel: 'chrome' });
    return { browser, name };
  }
  const browser = await webkit.launch({ headless: true });
  return { browser, name };
}

/**
 * 在指定寬度開一頁、導到 url、把版面「定格」到最終狀態。
 *
 * - viewport 寬 = width、高 = opts.height（預設 900）。width < 768 視為手機：
 *   isMobile + hasTouch + iPhone UA，讓 WebKit 走手機的 viewport meta 路徑
 *   （viewport-fit=cover、env(safe-area-inset-*) 這類只在手機模式才有意義）。
 * - deviceScaleFactor 預設 2（量座標時不影響 CSS px 數值）。
 * - 導頁後：
 *   1. 注入 `*{transition:none!important;animation:none!important}`——量的是最終版面，
 *      不是動畫中途；且瀏覽器面板在背景時會節流動畫（實案：翻頁位移連讀兩次都是 identity，CSS 其實沒錯）。
 *   2. 全頁 [data-reveal] 加 is-visible——reveal 靠 IntersectionObserver，視窗外的區塊
 *      沒捲到就永遠 opacity:0，量到的高度是對的但截圖是空白。
 *   3. loading="lazy" 全改 eager 並等圖載完——WebKit 分類頁那個 bug 正是圖片
 *      「原始尺寸 vs 排版尺寸」的問題，圖沒載入時量不到。
 */
export async function openPage(browser, url, width, opts = {}) {
  const mobile = width < 768;
  const context = await browser.newContext({
    viewport: { width, height: Number(opts.height) || 900 },
    deviceScaleFactor: Number(opts.dpr) || 2,
    isMobile: mobile,
    hasTouch: mobile,
    userAgent: mobile
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
      : undefined,
  });
  const page = await context.newPage();
  await page.goto(url, { waitUntil: 'load', timeout: Number(opts.timeout) || 60000 });

  await page.addStyleTag({ content: '*,*::before,*::after{transition:none!important;animation:none!important}' });
  await page.evaluate(async () => {
    document.querySelectorAll('[data-reveal]').forEach((el) => el.classList.add('is-visible'));
    const imgs = [...document.querySelectorAll('img')];
    imgs.forEach((img) => { if (img.loading === 'lazy') img.loading = 'eager'; });
    await Promise.all(imgs.map((img) => (img.complete ? null : new Promise((r) => { img.onload = img.onerror = r; }))));
    // 讓 layout 落定：兩個 frame
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  });
  return { page, context };
}

/**
 * 給元素產生一個人看得懂的短路徑：tag#id.class1.class2 > … 最多三層。
 * 只是給人對照用，不保證可當 querySelector 用（class 可能重複）。
 */
export const describeElementFn = `
(function describe(el) {
  const parts = [];
  let cur = el;
  while (cur && cur.nodeType === 1 && parts.length < 3) {
    let s = cur.tagName.toLowerCase();
    if (cur.id) s += '#' + cur.id;
    const cls = [...cur.classList].filter((c) => c !== 'is-visible').slice(0, 3);
    if (cls.length) s += '.' + cls.join('.');
    parts.unshift(s);
    cur = cur.parentElement;
  }
  return parts.join(' > ');
})`;
