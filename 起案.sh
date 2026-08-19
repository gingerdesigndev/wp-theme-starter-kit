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
#   4. 沒有副作用的檢查（位置防呆、參數格式驗證）全部排在使用者確認之前；
#      任何會動到檔案的動作（清除、複製、字串替換）都排在確認之後。
#      這樣「參數打錯早退」或「確認提示按 n」都不會留下半成品，
#      改參數就能直接重跑，不用先手動清理上一次跑到一半的殘骸。
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

# 防呆：只允許在「已經被複製到某個 WordPress 主題目錄底下」的複本上跑。
#
# ⚠️ 不要改用「git remote 是不是指向起案包」來判斷——那樣會自相矛盾：
#    照 README 說的整包複製（含 .git）過去，remote 還在，會被自己的防呆擋死；
#    要繞過就得排除 .git，但那樣下面的 KIT_COMMIT 就永遠讀不到、
#    HANDOFF.md 記錄不到起案版本，等於把漂移管理的錨點弄丟。
#    用「位置」判斷才同時滿足這兩件事：正本不在 themes/ 底下，複本在。
# ⚠️ 這個檢查一定要排在最前面（在任何清除動作之前）——它是唯一能防止
#    這支腳本在起案包正本上被誤跑、刪掉正本自己檔案的關卡。
case "$SRC" in
  */wp-content/themes/*) ;;
  *)
    echo "❌ 這裡不是 WordPress 的主題目錄。"
    echo "   目前位置：$SRC"
    echo ""
    echo "   正確流程：先把整包（**含 .git**）複製到目標 Local 站的"
    echo "   wp-content/themes/ 底下，再到那份複本上跑這支腳本。"
    echo "   保留 .git 是刻意的——腳本要讀它來記錄起案包版本；"
    echo "   跑完之後腳本會提示你重開 git。"
    exit 1
    ;;
esac

# 參數格式驗證：完全沒有副作用，刻意排在任何清除動作之前。
#
# ⚠️ 這裡曾經被改成排在清除動作「之後」，理由是想避免正本殘留的
#    HANDOFF.md／MEMORY.md（含上一個真實客戶的名字）在早退時留在複本裡沒清掉。
#    但那個順序造成更糟的後果：CSS 前綴打錯 → 早退，但範本已被刪、
#    docs/superpowers 也已被刪、字串替換卻沒跑——複本變成一個「回不去、
#    也起不來」的半成品，改參數重跑會直接卡在
#    `cp: …/HANDOFF.template.md: No such file or directory`。
#    在確認提示按 n 也是同樣下場：印出「已取消。」，但東西已經被刪了，
#    「已取消」其實是假的。
#    正確做法是把驗證（沒有副作用）搬到最前面、把清除（有副作用）留在
#    使用者明確按 y 確認之後——這樣任何早退都不會動到任何檔案，
#    永遠可以直接改參數重跑。
if ! echo "$NEW_SLUG" | grep -qE '^[a-z0-9-]+$'; then
  echo "❌ 主題 slug 只能用小寫英數與連字號：$NEW_SLUG"; exit 1
fi
if ! echo "$NEW_PREFIX" | grep -qE '^[a-z]{2,6}$'; then
  echo "❌ CSS 前綴只能用 2-6 個小寫英文字母：$NEW_PREFIX"; exit 1
fi

# 讀起案包版本：純讀取、沒有副作用，可以放在確認之前給使用者看。
KIT_COMMIT="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo '未知（非 git 複本）')"

echo "▶ 主題 slug ：starter-theme → $NEW_SLUG"
echo "▶ CSS 前綴  ：st-           → ${NEW_PREFIX}-"
echo "▶ 函式前綴  ：st_           → ${NEW_PREFIX}_"
echo "▶ 顯示名稱  ：Starter Theme → $NEW_NAME"
echo "▶ 起案包版本：$KIT_COMMIT"
echo ""
read -r -p "確認執行？這會就地改寫這份複本的檔案 [y/N] " ans
[ "$ans" = "y" ] || { echo "已取消。"; exit 0; }

# ── 以下才開始有副作用：清除、複製、字串替換 ──────────────

# 清掉起案包正本可能帶進來的敏感殘留（HANDOFF.md／MEMORY.md／
# docs/superpowers/／.superpowers/）。
#
# 位置防呆已經在最前面確認過這裡是 wp-content/themes/ 底下的複本、不是正本，
# 所以在這裡動筆刪除／覆寫是安全的，不會誤刪正本自己的檔案。
echo "→ 清掉正本殘留與敏感檔案…"
rm -rf "$SRC/docs/superpowers" "$SRC/.superpowers"

# HANDOFF.md / MEMORY.md 是這個站**自己的**工作交接紀錄，已列入 .gitignore
# （這個 repo 是公開的，內部進度不該推上去）。範本檔名是 *.template.md，
# 進版控；這裡把範本複製成新站的 HANDOFF.md / MEMORY.md 再刪掉範本——
# 新站不需要範本本身。
#
# ⚠️ cp 前先用 [ -f 範本 ] 判斷是否存在——讓這段可以重入：萬一腳本在這之後、
#    完成之前意外中斷，重跑一次也不會因為範本已經被上一次跑掉而直接炸掉。
if [ -f "$SRC/HANDOFF.template.md" ]; then
  cp "$SRC/HANDOFF.template.md" "$SRC/HANDOFF.md"
  # commit hash 是漂移管理的錨點：日後要比對規範差異、或把這站學到的東西
  # 回饋正本時，都是以這個 hash 為基準，一定要確認真的寫進去了。
  LC_ALL=C sed -i '' \
    -e "s/<起案\.sh 會自動填>/$KIT_COMMIT/" \
    -e "s/<專案名>/$NEW_NAME/g" \
    "$SRC/HANDOFF.md"
  rm -f "$SRC/HANDOFF.template.md"
fi

if [ -f "$SRC/MEMORY.template.md" ]; then
  cp "$SRC/MEMORY.template.md" "$SRC/MEMORY.md"
  LC_ALL=C sed -i '' -e "s/<專案名>/$NEW_NAME/g" "$SRC/MEMORY.md"
  rm -f "$SRC/MEMORY.template.md"
fi

# 1) 字串替換
# 只處理文字檔；排除 .git 與二進位素材。順序重要：先長後短，
# 避免 st- 先被換掉導致 starter-theme 對不上。
#
# ⚠️ 詞界用 [[:<:]] 不是 \b——BSD sed（macOS 內建）不支援 \b 而且**不會報錯**，
#    只會靜默比對不到，結果 st_ 與 st- 一個都沒換掉（實測殘留 98 筆）。
#    這種漏法 PHP lint 與前台 200 都抓不到（function_exists('st_opt') 判斷落空
#    不算語法錯誤），事後只有另外跑一次 grep 殘留計數才會發現。
#
# ⚠️ 還要多一條 s/_st_/_${NEW_PREFIX}_/g——ACF 欄位 key（如 field_st_site_logo）
#    是「底線 st 底線」，底線在 POSIX 裡算詞字元，[[:<:]]st_ 在 field_ 與 st_
#    之間構不成詞界，比對不到。這不是 BSD 特有的，GNU sed 的 \b 同樣情境行為一樣。
#
# ⚠️ 用 find -print0 配 while read -d ''，不要用 FILES=$(find ...) 接
#    for f in $FILES（未加引號）——後者會被 shell 用空白斷詞，Local by Flywheel
#    的標準路徑 ~/Local Sites/ 就含空白，斷詞後路徑會被切成兩半，
#    實測出現 `sed: /…/Local: No such file or directory`。
echo "→ 替換字串…"
# docs/superpowers/ 與 .superpowers/ 上面已經刪掉，這裡的排除只是保險
# （萬一哪天清除順序被改掉，這行還能擋住誤替換）。
while IFS= read -r -d '' f; do
  LC_ALL=C sed -i '' \
    -e "s/starter-theme/$NEW_SLUG/g" \
    -e "s/Starter Theme/$NEW_NAME/g" \
    -e "s/[[:<:]]st_/${NEW_PREFIX}_/g" \
    -e "s/[[:<:]]st-/${NEW_PREFIX}-/g" \
    -e "s/_st_/_${NEW_PREFIX}_/g" \
    -e "s/\.st-/.${NEW_PREFIX}-/g" \
    "$f"
done < <(find "$SRC" -type f \
  \( -name '*.php' -o -name '*.css' -o -name '*.md' -o -name '*.sh' -o -name '*.json' \) \
  -not -path '*/.git/*' \
  -not -path '*/docs/superpowers/*' \
  -not -path '*/.superpowers/*' \
  -print0)

# 2) 清掉示範素材（示範 partial 與 ACF 群組**保留**——它們是新站的起點）
echo "→ 清掉示範素材…"
rm -f "$SRC"/assets/img/* 2>/dev/null || true
mkdir -p "$SRC/assets/img"

# 3) 產生 .deploy.env（若尚未存在）
echo "→ 產生 .deploy.env…"
if [ ! -f "$SRC/.deploy.env" ]; then
  cp "$SRC/.deploy.env.example" "$SRC/.deploy.env"
  chmod 600 "$SRC/.deploy.env"
fi

# 4) 印出人類必須親手做的事
cat <<EOF

✅ 起案完成。

接下來這三件事**只有你能做**，AI 做不到：

  1. 把 SSH 公鑰裝到主機（要輸密碼，AI 不碰密碼）
     ssh-copy-id -i ~/.ssh/$NEW_SLUG.key.pub -p <PORT> <USER>@<HOST>
     ⚠️ 在你自己的電腦上跑，不是 SSH 進伺服器之後。

  2. 產生 Application Password（AI 沒有後台登入權）
     WP 後台 → 使用者 → 個人資料 → 應用程式密碼 → 命名 → 產生 → 複製（只顯示一次）
     ⚠️ 不要把密碼貼在對話裡，那會讓它明文留在紀錄。填進 .env 時記得放在
     repo 外（例如 ~/wp-secrets/），不要放進這個主題目錄——會被 deploy.sh 打包上傳。

  3. 到 WP 後台啟用主題（WP 核心的 REST API 沒有這個端點）

還有兩件建議現在做：

  - 把這個資料夾改名成 $NEW_SLUG（WordPress 用目錄名認主題）
  - 重開 git：rm -rf .git && git init
    （新站不該繼承起案包的歷史；起案包版本已記在 HANDOFF.md）

EOF
