# GA 與 Pixel Cat 追蹤

> 讀完這份約 6 分鐘。這份講的是「客戶要知道哪顆 CTA 被點了幾次」怎麼接：主題端只加
> 一個追蹤用的 class，事件由 Pixel Cat 這類外掛送進 GA4。每一案的設定方式都一樣，
> 照這份走就不必重新摸一遍。
>
> 相關文件：代號對照表放在該站 `design-system.md`；部署後的驗收項目見 `docs/04-部署SOP.md`
> 第六節與 `docs/07-審查清單.md`；量測腳本打出假流量的事見 `docs/05-踩坑清單.md`。

---

## 一、主題端：只加一個「給 GA 用」的 class

**原理**：GA4 加強型評估對「外連連結」的點擊會自動送 `click` 事件，帶 `link_classes`／`link_id`；
在 GA 以「link_classes 包含代號」分組就能看每一類按鈕的點擊。Pixel Cat 這類外掛則是直接綁
元素的 click 送自訂事件。兩條路都只需要元素上有一個**可辨識的 class**。

**規則**：

1. **追蹤 class 放在既有 class 旁邊，沒有任何 CSS 規則對它。** 它不改樣式、不參與版面；
   設計師改版換 class 名時它不受影響，反過來拿它寫樣式則會在改追蹤代號時弄壞版面。
2. **全站唯一一顆用 ID、重複出現的用 class。** 同一顆按鈕出現在多頁（頁首 CTA、頁尾 CTA）
   一律 class。
3. **底線命名**：`<位置>_<區塊>_<目的>`。例如：

   | 代號 | 掛在哪 |
   |---|---|
   | `all_nav_line` | 頁首 CTA（桌機）＋手機抽屜 CTA |
   | `all_footer_line` | 頁尾 CTA 帶、頁尾連結裡的預約鈕 |
   | `all_sidebtn_line` | 側邊懸浮鈕（桌機右下＝手機底部列同一顆） |
   | `all_section_line` | 各頁內文的「立即諮詢」 |
   | `<單一模板>_section_line` | 某種單篇模板裡的卡片 CTA（每篇一顆，同模板） |

   `all_` 表示全站共用的位置；只在某一類頁面出現的用該模板名開頭。目的詞（`line`、`tel`、`form`）
   寫按鈕導去哪，不寫按鈕長相。
4. **`tel:` 連結與非 `<a>` 的按鈕，GA 加強型評估抓不到**（它只認外連連結）。
   要追電話鈕就得走 Pixel Cat 的元素點擊事件；或客戶裁定先不追。

**代號對照表要寫進該站 `design-system.md`**：代號、元素型態（ID／class）、掛在哪些檔案的哪些
元素、每頁幾顆。新增 CTA 時要一起掛對應代號——這條列進切版完成的定義，不是事後補。
引言裡的純文字連結（例如 404 頁「請透過 LINE 聯繫」）若也導去同一個目的，客戶通常裁定同代號。

---

## 二、Pixel Cat 設定（每案相同）

Pixel Cat 後台「Events」新增一筆，四個欄位：

| 欄位 | 填什麼 |
|---|---|
| Trigger | **Click on Element** |
| CSS Target | **`.all_nav_line`**（class 前面是點） |
| Event | **Custom Event** |
| Event Name | 與 class **同名**：`all_nav_line` |

**CSS Target 用 `.` 不要用 `#`。** 外掛是 `$(selector).on('click')` 直接綁元素，寫成 `#all_nav_line`
會去找 id、整顆抓不到，而且不會有任何錯誤——實案裡客戶的對照表原本寫 `#`，上線後事件全空。
Event Name 與 class 同名是為了 GA 報表看到的名字＝程式碼裡的名字＝文件裡的名字，三處對得上。

一顆代號一筆事件；五顆就五筆。外掛會把 Event Name 原樣當 `gtag('event', …)` 的名稱送出。

---

## 三、上線後：事件要先被觸發過，才標得成重要事件

GA4 的「重要事件」（舊稱轉換）要先在事件清單裡出現才能標星星，而**事件要實際觸發過一次才會進清單**，
中間還有時間差。客戶的 GA 帳號權限通常不能用「自訂設定 → 建立重要事件」預先登記，只能等。

部署後的順序：

1. 清頁面快取（追蹤 class 在被快取的 HTML 裡，不清就是舊版）。
2. 自己（或請客戶）點一輪每顆 CTA。
3. GA4「報表 → 即時」確認事件名有進來——這是當下就能看的。
4. 「管理 → 事件 → 近期事件」約 **24 小時後**才會列出新事件名。
5. 列出後逐一點星星標為重要事件。沒標的話轉換報表不會算 CTA 點擊。

**第 4、5 步隔天才能做，很容易忘。** 寫進部署驗證清單與 `HANDOFF.md` 的待辦，
並在「留給客戶／使用者」那段註明「隔天回 GA 標重要事件」。

---

## 四、測試環境：Local 一定要停用 Pixel Cat

**症狀**：客戶看 GA 說「流量掉了一半」、「多了一堆 Direct、0 秒、來自日本的使用者」。

**成因**：Local 是正式站的複製，Pixel Cat 設定跟著複製過來，GA 評估 ID 也一樣。
量測與截圖腳本（Playwright、headless Chrome）**每開一個新 context 載入 Local 頁面就是一個新使用者**；
改版期間一天跑幾百次量測，就打出上千個假使用者進正式站的 GA。
舊站新站共用同一組 GA 時（為了看流量承接）更嚴重，兩邊的數字都被稀釋。

**做法**：

- 在 Local 後台**停用 Pixel Cat**（或任何輸出 GA／FB Pixel 的外掛），首頁原始碼確認沒有
  `gtag`／`fbq` 再開始量測。
- **從正式站重新同步 DB 之後外掛會復活**，要再停一次。把這條寫進該站 `MEMORY.md` 的同步步驟裡。
- 腳本載入**正式站**頁面時仍會送 GA（主機名稱正確、量很小），分析時知道即可；
  實案裁定不在腳本裡加 route 攔截，只靠 Local 停用外掛。
- 看報表要拆站時用「主機名稱」維度；舊站新站共用一組 GA 是刻意的，不要為此另開資源。

---

## 五、驗證：攔 `/g/collect`，逐行解析

要證明「五顆按鈕的事件都有送到正確的評估 ID」，用 Playwright WebKit 腳本逐顆點、攔截對
`google-analytics.com/g/collect` 的請求，讀 body 裡的 `en=`（事件名）與 `tid=`（評估 ID）。

**GA4 會把同一瞬間的多個事件合併成一個 POST。** body 以換行分隔多筆，每行一個 `en=…`。
點 CTA 時 `scrollIntoView` 常同時觸發外掛的捲動事件，兩個事件進同一個請求——
只讀第一行會誤判「按鈕事件沒送」然後去改碼。

```js
page.on('request', r => {
  if (!r.url().includes('/g/collect')) return;
  const body = r.postData() || '';
  const url  = new URL(r.url());
  const names = body.split('\n').map(l => new URLSearchParams(l).get('en')).filter(Boolean);
  if (!names.length && url.searchParams.get('en')) names.push(url.searchParams.get('en'));
  console.log(url.searchParams.get('tid'), names);
});
```

- 有時事件在 query string 不在 body（單一事件的 GET），兩處都要讀。
- 手機抽屜裡的按鈕要先把抽屜打開再點；固定定位的側邊鈕要確認沒被別的元素蓋住
  （`elementFromPoint` 回的是不是它）。
- 這一輪驗證本身也會送事件進 GA，量很小，但驗完別忘了第三節第 3 步看「即時」是順便的。

---

## 延伸閱讀

| 情況 | 讀這份 |
|---|---|
| 部署後的驗收項目、快取沒清 | `docs/04-部署SOP.md` |
| 量測腳本的假流量、其他 GA／外掛怪現象 | `docs/05-踩坑清單.md` |
| 這類改動要怎麼分級、怎麼審 | `docs/07-審查清單.md` |
