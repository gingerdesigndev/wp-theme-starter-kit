# 切版 SOP

> 讀完這份約 12 分鐘。這份講的是「拿到一個 Figma 區塊 → 切出可用的
> `template-parts/*.php` + CSS」的完整流程。
>
> 本主題**沒有編輯器**（古典 PHP 模板 + ACF，不是 Gutenberg），所以這份的核心
> 判準跟切出可在編輯器裡點改的版面區塊不一樣：客戶改版面靠的是後台的 ACF 欄位，
> 不是在編輯器裡點。切之前先確認這件事，再往下讀。

---

## 核心決策：ACF 欄位 vs 寫死在 PHP

**每切一塊之前先決定這個。決定錯了，客戶交件後第一件事就是回頭要求「這裡可以自己改嗎」。**

沒有編輯器，所以省事的做法是整塊內容通通寫死在 `template-parts/*.php` 裡——但代價
是客戶一個字都改不了，要改就得回頭找工程師動程式碼。

| 用 **ACF 欄位** | **寫死在 PHP** |
|---|---|
| 客戶會想自己改的文案、圖片、CTA 連結 | 純裝飾、結構性文字、設計稿烤進圖裡的內容 |
| ✅ 後台可改 | ❌ 要改就得動程式碼 |
| ❌ 每個欄位都要建、要寫回退值 | ✅ 快 |

**判準**：

- **文字內容為主 → ACF。** 客戶一定會想改文案，這是他們最常改的東西。
  範例：`section-hero.php` 的標題／副標／CTA 全部走 `st_opt()` 讀 ACF。
- **純圖片、無文字 → 寫死。** 設計稿的裝飾圖、Logo 花紋這類沒有可改文字的元素，
  接 ACF 只是徒增一個「客戶永遠不會用到」的欄位。
- **重複結構（卡片列表這類）→ ACF 的 Repeater 欄位。** 範例：`section-cards-3col.php`
  的卡片區資料是 `cards` 這個 repeater，子欄位 `title` / `body` / `image`。

### Repeater 的取捨要講出來，並留好演進路徑

Repeater 欄位＝客戶能在後台自己增減列數，比 PHP 陣列更彈性，但欄位數一多、
後台編輯介面會變得不好逛（尤其每列有多個子欄位時）。這個取捨要主動告訴客戶，
別默默決定。

如果那批內容之後會長期大量增減（例如超過十幾筆的案例、文章式的內容），
標準演進路徑是 **Repeater → 自訂內容類型（CPT）**：先用 Repeater 快速切出版面，
之後把資料搬到 CPT，`template-parts` 檔案改成跑 `WP_Query`，版面完全不用動。

切的時候在 docblock 標明現況與意圖，例如：
> 卡片資料：目前是 ACF Repeater，集中在「網站設定」一個畫面編輯；筆數如果之後
> 長到十幾筆以上，可改為自訂內容類型（CPT），版面不用動

---

## 流程

### 1. 從 Figma 取得 node

新手工程師最常卡在這一步——他知道要「把設計稿給 AI」，但不知道要給的是
**Dev Mode 連結**，不是截圖或口頭描述。拿不到連結就先教他這四步：

1. 在 Figma 點選要切的**那一個 frame／區塊**（看左側圖層面板確認選對層，
   選到整個 page 會讓範圍過大）
2. 按右上角藍色的 **Share**
3. 選 **Copy link to selection**——網址要帶 `?node-id=...`。
   面板裡沒有 Dev Mode 選項的話，先按右上角 `</>` 切到 Dev Mode 再複製
4. 把連結貼給 AI，說「切這塊」

兩條紀律：

- **沒有連結不要開始切。** 憑截圖或口頭描述做出來的版面，尺寸、間距、色票
  沒有一項對得上設計稿，返工比重做還久。
- **Figma MCP 沒接上時要直說讀不到**，不要照檔名或節點名猜版面。

#### 偵測到沒連上 Figma MCP，先帶他接好再切

以下與 `AGENTS.md`「使用者沒給你 Figma 連結時，這樣引導他」一節內容一致——
**以 `AGENTS.md` 為準**，這裡是給人看的展開版。

**怎麼判斷**：工具清單裡沒有 `get_design_context` / `get_screenshot` /
`get_variable_defs` 這一組——那就是沒接上；或是有工具但呼叫回授權錯誤。

這時候停下來，不要用截圖硬切，先照下面帶他接：

**路線 A：Figma 本機 Dev Mode MCP**（大多數情況用這條）

1. 開 **Figma 桌面版**（瀏覽器版不行）
2. **Figma 選單 → Preferences**，找到 MCP server 相關選項並開啟
3. 本機會起一個伺服器：`http://127.0.0.1:3845/mcp`
4. 在專案資料夾裡執行：
   ```bash
   claude mcp add --transport http figma http://127.0.0.1:3845/mcp
   ```
5. 重開 Claude Code，跑 `claude mcp list`，`figma` 要顯示 **Connected**

**路線 B：claude.ai 的 Figma 連接器（OAuth）**

OAuth 需要互動視窗，**非互動 session 跑不起來**——遇到就請使用者自己去
claude.ai 的連接器設定完成授權，**不要向他索取授權碼或 token**。

**接好之後怎麼確認真的通了**：請他再貼一次 Dev Mode 連結，呼叫
`get_design_context`。拿得到圖層結構與尺寸才算通；只拿到網址回音不算。

三個常見卡點：Figma 桌面版被關掉（重開就好）、帳號席次不足看不到 Dev Mode
（要他自己去開通）、連結指向的檔案他沒有存取權（換一份他有權限的檔案測）。

#### AI 這邊要做的事

> ⚠️ **抓取這一步先讀 `~/.claude/skills/design-capture-traps/SKILL.md`**——
> 如果你在野薑的機器上。裡面的陷阱**都不會報錯**，已知後果是整段區塊漏做，
> 審查才發現。讀不到這份的話，最關鍵的三條先記住：
> 1. `get_design_context` 對大節點會在字數上限**靜默截斷**——後果：截斷點看起來
>    就像正常結尾，你會漏做最後一段
> 2. `get_metadata` 對大節點有回應大小上限，**重試不會成功**——後果：白白卡住，
>    以為是節點本身有問題
> 3. **節點名稱猜不出圖片內容**（`Group 1203` 這類流水號）——後果：內容判斷出錯，
>    務必打開圖片本身確認再描述

接上之後依序呼叫：

- `get_design_context` — 拿結構、尺寸、樣式、以及**素材的下載 URL**
- `get_screenshot` — 拿視覺對照（切完比對用）
- `get_variable_defs` — 拿設計變數（顏色／間距），對 tokens 用

**先看整體再看細節**：確認這塊是滿版（100vw）還是內容寬（走 `.st-wrap`），
這決定 CSS 的骨架。

### 2. 對 design tokens，不要硬編

**切版前先讀 `design-system.md`**，看已經有哪些 token。

- Figma 的色票對到既有 token（如 `--color-accent`）→ 直接引用
- 真的是新顏色 → 在 `:root` 加一個 token，**並同步寫進 `design-system.md`**
- **不要在 template-part 或 CSS 裡硬編色碼**——那是之後全站改色時的地獄

間距同理：本包用 8 倍數查表（`--space-2`=8、`--space-4`=16……）。看
`design-system.md` 已填的是什麼就用什麼，不要另開一套。

### 3. 抓素材

從 `get_design_context` 拿到 asset URL，下載到 `assets/img/`。

**⚠️ Figma 匯出的圖常常大得離譜**——實際踩過：卡片照片匯出是 3230×4096，
版面上只顯示 310px 寬。整包 assets 一度累積到 147MB。

**規則**：下載後先確認尺寸，用 `sips` 縮到**顯示寬度的 ~2x**（retina）：

```bash
sips -Z 640 assets/img/foo.jpg                          # 縮到最長邊 640
sips -g pixelWidth -g pixelHeight assets/img/foo.jpg    # 確認
```

### 4. 寫 template-part

檔案放 `template-parts/section-<名字>.php`，在要用的模板檔（如
`front-page.php`）裡用 `get_template_part('template-parts/section', '<名字>')`
掛上——這一步是古典主題自己接版面的方式，沒有自動註冊這回事，掛哪個模板檔、
掛在第幾個位置都要自己寫清楚，順序就是前台輸出的順序。

參考：

```php
get_template_part('template-parts/section', 'hero');
get_template_part('template-parts/section', 'cards-3col');
```

docblock 必寫四件事：

1. **這塊是什麼**、結構長怎樣
2. **沿用了什麼**（哪些共用 class／token），讓人知道改動的連帶影響
3. **維護方式**：客戶要在後台哪個畫面改文案／換圖
4. **Figma 上略過了什麼**。誠實寫，不寫的話之後沒人知道是漏做還是刻意不做

必守的細節（`section-hero.php`、`section-cards-3col.php` 已是範例）：

- `if (!defined('ABSPATH')) exit;` 開頭
- 讀值一律走 `st_opt()`，不要直接呼叫 `get_field()`（ACF 被停用時
  `get_field()` 不存在，直接呼叫會整站白畫面，見 `docs/02-ACF規範.md`）
- 圖片路徑走 `get_stylesheet_directory_uri()`，不要寫死 URL
- 逸出：`esc_url()` / `esc_attr()` / `esc_html()`，一個都不能少
- `<img>` 要有 `width` / `height`（避免 CLS），非首屏加 `loading="lazy"`
- **沒資料就 `return`，整區不輸出**——空殼區塊比沒有區塊更糟。用 `trim()` 判斷
  文字欄位而不是直接判真值，避免編輯在後台誤打一個空白鍵就矇混過關

### 5. 寫 CSS

排版 scope 在 `.site-main`，避免影響全站其他區域。命名 BEM-like，前綴沿用
專案既有的 `.st-`（起案後 `起案.sh` 會換成客戶專屬前綴）：
`.st-hero` / `.st-hero__title` / `.st-card__thumb`。

滿版做法與防水平捲動：

```css
.site-main .st-hero{ width:100vw; max-width:100vw; margin-inline:calc(50% - 50vw); }
.site-main{ overflow-x:clip; }
```

### 6. 同步 `design-system.md`（硬性規則）

改了 CSS／PHP 就要更新這份，文件與程式碼是一體的：

- 新 token → 顏色／間距表
- 新元件 → 元件章節，寫清楚 class 結構與 RWD 行為
- 新模板檔或新區塊 → 模板檔章節
- 略過的東西 → 一併記錄，不要讓下一個人以為「沒寫到就是沒有」

### 7. 驗證

1. **重載 PHP**：`kill -USR2 "$(pgrep -f 'php-fpm: master' | head -1)"`。
   不重載會被 opcache 餵舊碼，你會開始修一個不存在的 bug。
2. **開真實瀏覽器**看，不要用 headless 截圖下結論——滿版 `100vw` 元素在
   headless 環境會依視窗高度算繪出錯（header 憑空消失之類），真實瀏覽器
   完全正常。
3. **跟 Figma 截圖並排比對**（`get_screenshot` 拿設計稿）。

   > ⚠️ 要用 headless Chrome 截圖或量 RWD 寬度的話，**先讀
   > `~/.claude/skills/design-capture-traps/SKILL.md`**——如果你在野薑的機器上。
   > 這幾條**都不會報錯**，讀不到這份的話先記住最關鍵的三條：
   > 1. CDP 截圖帶裁切區在大尺寸下**會回傳壞圖**——後果：大部分全白，誤判
   >    版面壞掉
   > 2. `overflow-x:clip` 讓水平捲動量測**測不到溢出**——後果：量測回報通過，
   >    畫面其實被裁掉或跑版
   > 3. 進場動畫會讓截圖**整塊空白**——後果：誤以為區塊沒做出來，其實只是
   >    還沒觸發顯示

4. **清空 ACF 值再看一次**，確認「沒資料時整區不輸出」真的成立——不是回退值
   剛好長得跟設計稿一樣就當作接通了（回退值＝真實值時，光看前台無法證明
   欄位真的接上，見 `docs/02-ACF規範.md` 第三節）。

---

## 三條切版規範（多頁專案上被驗證過，不能省）

沒有這三條，多人或多頁時版面一定會發散——不是「可能」，是「一定」。

### a) section 之間的垂直節奏要有預設值

沒有預設值時，兩個互不知情的人會對同一頁的 section 間距給出不同答案（實例：
64/32、64/96、96/96 混在同一頁，肉眼看得出斷面不一致）。

→ 定一個預設：本包用 `--space-24`（96px）。

**要偏離預設，必須拿設計稿量出證據**——逐一比較「上一個 section 底邊」到
「下一個 section 標題頂邊」的 y 座標差，並把量測依據（node id、量到的數字、
結論）寫進 `design-system.md`。不要讓下一個人只看到一個孤立的
`padding-block` 值，卻不知道背後有沒有量過。

### b) 頁面專屬的 CSS class 一律加頁面前綴

命名成 `.st-<頁面>-<元件>`。裸元件名遲早撞名——**不是會不會，是第幾頁會
撞上**。而且撞名是安靜的：兩份頁面 CSS 各自只在自己頁面生效，問題不會
馬上炸，會變成「改 A 頁以為只影響 A 頁，其實 B 頁也在用同一個名字」。

### c) 共用元件的晉升判準：第二個頁面需要它時才抽出來

- 抽的時候共用宣告寫一次，會變的值包成自訂屬性給預設值，**不要複製整組宣告**
- 判準：**格線怎麼排、順序反轉、字體間距＝結構 → 抽共用；單張圖的
  `aspect-ratio`＝內容尺寸 → 留頁面**
- **純文字排版的重複不觸發晉升**（字級／字重／顏色這類組合逐區塊各自宣告是
  既有做法，不是缺陷）
- 晉升是對已上線頁面的重構，**驗收是視覺零變化（逐區塊截圖比對），不是
  「看起來差不多」**

---

## 命名速查

| 對象 | 慣例 | 範例 |
|---|---|---|
| template-part 檔名 | `section-<名字>.php` | `section-hero.php` |
| 掛上模板 | `get_template_part('template-parts/section', '<名字>')` | `get_template_part('template-parts/section', 'cards-3col')` |
| 區塊根 | `.<prefix>-<name>` | `.st-hero` |
| 區塊元素 | `.<prefix>-<name>__<el>` | `.st-hero__title` |
| 卡片 | `.<prefix>-<name>-card` 或元件既有命名 | `.st-card` |
| 卡片元素 | `.<prefix>-<name>-card__<el>` | `.st-card__thumb` |
| ACF 欄位名 | 小寫底線 | `hero_title`、`contact_tel` |
| Repeater 子欄位 | 小寫底線，跟父欄位語意相關 | `cards.title` / `cards.body` / `cards.image` |
| 素材檔名 | `assets/img/<name>-<n>.<ext>` | `card-1.jpg` |
