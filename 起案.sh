#!/usr/bin/env bash
#
# 起案.sh — 從起案包生成一個新客戶站的主題
#
# 設計原則：
#   1. 只動「這一份複本」，絕不回頭改起案包正本。
#   2. 不自動碰 git——新站不該繼承起案包的歷史，但要不要重開 repo
#      是使用者的決定，腳本只提示。
#   3. 把起案包當下的 commit hash 寫進 HANDOFF.md：
#      日後要知道「這站是哪一版起案包生出來的」只能靠它。
#
# 用法：
#   ./起案.sh <主題slug> <CSS前綴> "<主題顯示名>"
#   例：./起案.sh mayo-theme mayo "美佑診所"
#
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ $# -ne 3 ]; then
  echo "用法：./起案.sh <主題slug> <CSS前綴> \"<主題顯示名>\""
  echo "例：  ./起案.sh mayo-theme mayo \"美佑診所\""
  echo ""
  echo "  <主題slug>   小寫英數與連字號，會變成主題目錄名，例：mayo-theme"
  echo "  <CSS前綴>    小寫英文，2-6 字，例：mayo（class 會變成 .mayo-wrap）"
  echo "  <主題顯示名> 後台看到的名字，可用中文"
  exit 1
fi

NEW_SLUG="$1"
NEW_PREFIX="$2"
NEW_NAME="$3"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 防呆：不允許在起案包正本上跑
if [ -d "$SRC/.git" ] && git -C "$SRC" remote -v 2>/dev/null | grep -q 'wp-theme-starter-kit'; then
  echo "❌ 這裡看起來是起案包**正本**（git remote 指向 wp-theme-starter-kit）。"
  echo "   請先把整包複製到目標 Local 站的 wp-content/themes/ 底下，再到那份複本上跑。"
  exit 1
fi

if ! echo "$NEW_SLUG" | grep -qE '^[a-z0-9-]+$'; then
  echo "❌ 主題 slug 只能用小寫英數與連字號：$NEW_SLUG"; exit 1
fi
if ! echo "$NEW_PREFIX" | grep -qE '^[a-z]{2,6}$'; then
  echo "❌ CSS 前綴只能用 2-6 個小寫英文字母：$NEW_PREFIX"; exit 1
fi

KIT_COMMIT="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '未知（非 git 複本）')"

echo "▶ 主題 slug ：starter-theme → $NEW_SLUG"
echo "▶ CSS 前綴  ：st-           → ${NEW_PREFIX}-"
echo "▶ 函式前綴  ：st_           → ${NEW_PREFIX}_"
echo "▶ 顯示名稱  ：Starter Theme → $NEW_NAME"
echo "▶ 起案包版本：$KIT_COMMIT"
echo ""
read -r -p "確認執行？這會就地改寫這份複本的檔案 [y/N] " ans
[ "$ans" = "y" ] || { echo "已取消。"; exit 0; }

# 1) 字串替換
# 只處理文字檔；排除 .git 與二進位素材。順序重要：先長後短，
# 避免 st- 先被換掉導致 starter-theme 對不上。
#
# 注意：這裡用 [[:<:]]（BSD sed 的「詞首」錨點）取代 \b。
# macOS 內建 sed 是 BSD sed，不支援 \b——用了不會報錯，只會靜默比對不到，
# 等於 st_ / st- 完全沒被替換掉，卻不會有任何錯誤訊息（已實測踩過這個坑）。
# [[:<:]] 是 BSD 規則運算式的擴充語法，效果等同「左邊詞界」，才是這台機器上真的有效的寫法。
echo "→ 替換字串…"
FILES=$(find "$SRC" -type f \
  \( -name '*.php' -o -name '*.css' -o -name '*.md' -o -name '*.sh' -o -name '*.json' \) \
  -not -path '*/.git/*')

for f in $FILES; do
  LC_ALL=C sed -i '' \
    -e "s/starter-theme/$NEW_SLUG/g" \
    -e "s/Starter Theme/$NEW_NAME/g" \
    -e "s/[[:<:]]st_/${NEW_PREFIX}_/g" \
    -e "s/[[:<:]]st-/${NEW_PREFIX}-/g" \
    -e "s/\.st-/.${NEW_PREFIX}-/g" \
    "$f"
done

# 2) 清掉示範素材（示範 partial 與 ACF 群組**保留**——它們是新站的起點）
echo "→ 清掉示範素材…"
rm -f "$SRC"/assets/img/* 2>/dev/null || true
mkdir -p "$SRC/assets/img"

# 3) 產生站台專屬檔
echo "→ 產生 .deploy.env 與 HANDOFF.md…"
if [ ! -f "$SRC/.deploy.env" ]; then
  cp "$SRC/.deploy.env.example" "$SRC/.deploy.env"
  chmod 600 "$SRC/.deploy.env"
fi

cat > "$SRC/HANDOFF.md" <<EOF
# HANDOFF — $NEW_NAME

> 起案自「WP 自刻主題起案包」commit \`$KIT_COMMIT\`。
> 日後要比對規範差異、或把這站學到的東西回饋正本時，以這個 hash 為基準。

## 目前進度

（剛起案，還沒開始切版）

## 還沒做完 / TODO

- [ ] 把 style.css §1 的顏色換成客戶品牌色，並同步 design-system.md
- [ ] 依設計稿調整 --container 與 --measure
- [ ] 填 .deploy.env 的主機資訊
- [ ] 後台建立 ACF 欄位群組（位置規則：選項頁面 等於 網站設定）

## 下次怎麼接

先讀 \`docs/00-開站六步.md\`。
EOF

# 4) 印出人類必須親手做的事
cat <<EOF

✅ 起案完成。

接下來這三件事**只有你能做**，AI 做不到：

  1. 把 SSH 公鑰裝到主機（要輸密碼，AI 不碰密碼）
     ssh-copy-id -i ~/.ssh/$NEW_SLUG.key.pub -p <PORT> <USER>@<HOST>
     ⚠️ 在你自己的電腦上跑，不是 SSH 進伺服器之後。

  2. 產生 Application Password（AI 沒有後台登入權）
     WP 後台 → 使用者 → 個人資料 → 應用程式密碼 → 命名 → 產生 → 複製（只顯示一次）
     ⚠️ 不要把密碼貼在對話裡，那會讓它明文留在紀錄。

  3. 到 WP 後台啟用主題（WP 核心的 REST API 沒有這個端點）

還有兩件建議現在做：

  - 把這個資料夾改名成 $NEW_SLUG（WordPress 用目錄名認主題）
  - 重開 git：rm -rf .git && git init
    （新站不該繼承起案包的歷史；起案包版本已記在 HANDOFF.md）

EOF
