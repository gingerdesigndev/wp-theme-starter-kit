#!/usr/bin/env bash
#
# deploy.sh — 部署主題到正式主機
#
# 設計原則：
#   1. 只上傳「主題檔案」，絕不啟用主題、絕不碰資料庫。
#      （啟用要人為到 WP 後台做，避免誤觸線上站）
#   2. 每一步都驗證：連線 → md5 → 鏡像對齊 → 逐檔比對，任一步失敗就中止。
#      鏡像＝遠端多餘檔（本機已刪的素材、曾外洩的內部文件）自動從遠端刪除；
#      多餘檔 >50 判定異常、中止不亂刪。主題目錄完全由本腳本管，鏡像才安全。
#   3. 不使用 rsync —— 正式主機是精簡容器，沒有 rsync / sftp-server / php CLI，
#      只有 tar + gzip，所以走 tar over SSH。
#   4. COPYFILE_DISABLE=1 —— macOS 的 BSD tar 會把延伸屬性打包成 AppleDouble
#      檔案，在 Linux 解開會變成一堆 `._*` 垃圾檔。這個環境變數可根治。
#
# 用法：
#   ./deploy.sh              # 部署
#   ./deploy.sh --dry-run    # 打包 + 檢查 + 印出「鏡像會刪什麼／新增什麼」，不上傳
#
# ⚠️ --dry-run 也會連 SSH（為了列遠端清單）。這是刻意的：想知道鏡像會刪哪些檔，
#    唯一正確的方式就是跑這個，**不要自己另外開一條 SSH 去 find 遠端**——
#    那正是 MEMORY.md「部署的連線紀律」記載、害我們被 fail2ban 擋掉的動作。
#    代價是 dry-run 連線失敗同樣會把 fail2ban 封鎖時間歸零，所以它也不能盲目重跑。
#
# 設定一律從專案根目錄的 .deploy.env 讀（複製 .deploy.env.example 並填值）。
#
set -euo pipefail

# ── 設定：一律從 .deploy.env 讀 ─────────────────────
# 為什麼不寫預設值：寫了預設值，設定檔漏了也會「成功」跑起來，
# 只是傳到錯的地方。客戶站傳錯主機的代價太高，寧可直接中止。
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SRC/.deploy.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 找不到 $ENV_FILE"
  echo "   複製 .deploy.env.example 成 .deploy.env 並填入主機資訊。"
  echo "   ⚠️ 這個檔含主機位址與金鑰路徑，已列入 .gitignore，不要提交。"
  exit 1
fi
# shellcheck disable=SC1090
. "$ENV_FILE"

for v in SITE_HOST SITE_PORT SITE_USER SITE_KEY SITE_REMOTE_DIR; do
  if [ -z "${!v:-}" ]; then
    echo "❌ .deploy.env 缺少 $v"
    exit 1
  fi
done

HOST="$SITE_HOST"
PORT="$SITE_PORT"
SSH_USER="$SITE_USER"
KEY="$SITE_KEY"
REMOTE_DIR="$SITE_REMOTE_DIR"
REMOTE_TMP="$(dirname "$SITE_REMOTE_DIR")/.starter-deploy.tgz"
# ─────────────────────────────────────────────────────

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

TGZ="$(mktemp)"
# ⚠️ 固定檔名（原本是 /tmp/.st-local 等）在同時部署兩個站時會互相覆蓋：
#    鏡像比對可能拿 A 站的遠端清單去減 B 站的本機清單，得出錯的「多餘檔」
#    清單而誤刪。部署包只有十幾個檔，>50 的防呆攔不到這個量級的誤判。
#    改用 mktemp 產生本次執行專屬的唯一檔名。
ST_LOCAL="$(mktemp)"
ST_REMOTE="$(mktemp)"
ST_STALE="$(mktemp)"
SSH_CMD=(ssh -i "$KEY" -p "$PORT" -o BatchMode=yes -o ConnectTimeout=15)

# 不進入部署包的東西：版控、內部文件、開發工具、系統垃圾、本腳本自己
# 內部文件含主機資訊與內部流程，傳到網頁伺服器就是對外可讀的資訊洩漏。
# ⚠️ docs/、.claude/、.superpowers/ 一定要在這裡——它們是起案包獨有、原始主題
#    沒有的東西（task brief、implementer report、review diff、規格與計畫、
#    AI 協作設定），漏掉就會把整包規範連同踩坑紀錄傳到客戶主機上。
# ⚠️ .env 也一定要在這裡——文件規定 REST API 的 Application Password 要放在
#    repo 外，但文件會被人改、放錯位置的事還是可能發生。這行是程式碼側的
#    第二道防線：就算有人真的把 .env 放進了專案根目錄，也不會被打包上傳。
EXCLUDES=(
  --exclude='.git'
  --exclude='.gitignore'
  --exclude='.DS_Store'
  --exclude='docs'
  --exclude='.claude'
  --exclude='.superpowers'
  --exclude='HANDOFF.md'
  --exclude='MEMORY.md'
  --exclude='AI-協作指南.md'
  --exclude='CLAUDE.md'
  --exclude='AGENTS.md'
  --exclude='design-system.md'
  --exclude='README.md'
  --exclude='deploy.sh'
  --exclude='起案.sh'
  --exclude='.deploy.env'
  --exclude='.deploy.env.example'
  --exclude='.env'
)

# 遠端「多餘檔」由步驟 5 的鏡像機制統一處理（見下）：
# tar 解壓不刪既有檔，所以凡是「本機沒有、遠端有」的檔（本機刪掉的素材、
# 曾外洩的內部文件 design-system.md 等）一律在步驟 5 從遠端刪除。
# 不再維護手動的 STALE_REMOTE 清單——那是逐檔白名單，遲早漏。

cleanup() { rm -f "$TGZ" "$ST_LOCAL" "$ST_REMOTE" "$ST_STALE"; }
trap cleanup EXIT

# 本機檔案清單（步驟 5 的鏡像比對與 --dry-run 的預覽共用同一份）
# ⚠️ 只能有這一份實作。抽成函式的理由不是「比較整潔」：這份清單的排除集必須跟
#    上方 EXCLUDES 一致，一旦兩處各寫一份，改了 EXCLUDES 卻漏改另一處，
#    鏡像就會把「其實該留」的檔判成多餘而刪掉——那是靜默的資料損失。
# .git/、docs/、.claude/、.superpowers/ 是目錄，要用 -not -path
#（! -name 只比對檔名，比對不到目錄，會漏排除）。
list_local_files() {
  (cd "$SRC" && find . -type f \
    -not -path './.git/*' -not -path './docs/*' -not -path './.claude/*' \
    -not -path './.superpowers/*' \
    ! -name '.gitignore' ! -name '.DS_Store' \
    ! -name 'HANDOFF.md' ! -name 'MEMORY.md' ! -name 'AI-協作指南.md' \
    ! -name 'CLAUDE.md' ! -name 'AGENTS.md' ! -name 'design-system.md' ! -name 'README.md' \
    ! -name 'deploy.sh' ! -name '起案.sh' \
    ! -name '.deploy.env' ! -name '.deploy.env.example' ! -name '.env' \
    | sed 's|^\./||' | sort)
}

# 遠端檔案清單（目錄不存在時回空，不讓 find 的錯誤訊息混進清單）
list_remote_files() {
  "${SSH_CMD[@]}" "$SSH_USER@$HOST" \
    "cd '$REMOTE_DIR' 2>/dev/null && find . -type f | sed 's|^\./||' | sort || true"
}

echo "▶ 來源：$SRC"
echo "▶ 目標：$SSH_USER@$HOST:$REMOTE_DIR"
echo "▶ 模式：$([ $DRY_RUN -eq 1 ] && echo 'DRY-RUN（不上傳）' || echo '實際部署')"
echo ""

# 1) 打包
echo "→ 打包主題…"
COPYFILE_DISABLE=1 tar czf "$TGZ" -C "$SRC" "${EXCLUDES[@]}" .
echo "  大小：$(du -h "$TGZ" | cut -f1)"

# 安全檢查：確認沒夾帶敏感/無關檔案
# ⚠️ 這道檢查刻意跟 EXCLUDES 分開寫死一份、不是「重複同一件事」：
#    萬一以後 EXCLUDES 漏加了什麼（就像這次的 .superpowers/ 與 docs/），
#    這裡是最後一道會讓部署直接中止的關卡，不能只靠改 EXCLUDES 時記得同步改這裡。
# ⚠️ .env：REST API 的 Application Password，文件規定放 repo 外，但這裡多一道
#    程式碼側的攔截，不完全靠人照文件做對。
# ⚠️ deploy.sh / 起案.sh：本腳本自己與起案腳本不該出現在客戶主機上（沒有部署
#    憑證、對客戶主機也無用，多出來只是徒增可攻擊面）。
# ⚠️ tar tzf 對非 ASCII 檔名（中文檔名）會轉義成八進位跳脫序列
#    （例如「起案.sh」印成 \350\265\267\346\241\210.sh），regex 裡的中文字
#    永遠比不到、卻不會報任何錯誤——這條分支曾經整個沒生效過。
#    先用 sed 把 \NNN 補成 \0NNN、再用 printf '%b' 還原成真正的 UTF-8 位元組，
#    regex 才吃得到中文檔名。續用 tar tzf 的內容（不要換成 find 的輸出），
#    這樣這道檢查才是獨立於上面 EXCLUDES 之外的第二道防線。
# ⚠️ 還原後的清單一定要先落地成暫存檔，不能直接接 grep -qE：
#    `tar tzf | sed | while read/printf | grep -qE` 這種多階管線，一旦 grep -q
#    提早找到相符就會馬上結束，還在慢慢逐行 printf 的上游行程會收到 SIGPIPE
#    （結束碼 141）。set -o pipefail 之下，這個 141 會蓋掉 grep 真正抓到相符
#    的 0，讓 if 誤判成「沒找到」——grep 明明抓到了，卻因管線裡更早的行程被
#    訊號打斷而整條回報失敗，又是一次沒有任何錯誤訊息的靜默失敗。改成先寫進
#    暫存檔、grep -q 讀真正的檔案（不是活的管線），就不會有這個問題。
ST_TARLIST="$(mktemp)"
tar tzf "$TGZ" \
  | LC_ALL=C sed 's/\\\([0-7][0-7][0-7]\)/\\0\1/g' \
  | while IFS= read -r l; do printf '%b\n' "$l"; done \
  > "$ST_TARLIST"
if grep -qE '(^|/)\.git/|(^|/)docs/|(^|/)\.claude/|(^|/)\.superpowers/|HANDOFF\.md|MEMORY\.md|AI-協作指南\.md|CLAUDE\.md|AGENTS\.md|design-system\.md|README\.md|\.deploy\.env|(^|/)\.env$|(^|/)deploy\.sh$|(^|/)起案\.sh$' "$ST_TARLIST"; then
  echo "  ❌ 部署包夾帶了不該上線的檔案，中止"
  rm -f "$ST_TARLIST"
  exit 1
fi
rm -f "$ST_TARLIST"
echo "  ✅ 內容乾淨（無 .git / 內部文件 / .claude / .superpowers / docs / .env / deploy.sh / 起案.sh）"

if [ $DRY_RUN -eq 1 ]; then
  echo ""
  echo "  包內容（前 20 項）："
  tar tzf "$TGZ" | head -20 | sed 's/^/    /'
  echo ""
fi

# 2) 連線檢查
echo "→ 檢查金鑰連線…"
# 原本這裡把 stderr 丟掉、只印「金鑰或主機有問題」，但那三種情況的解法完全不同
# （fail2ban 要重啟 SSH、sidecar 沒開要啟動、金鑰壞要換金鑰），看不出是哪種等於沒說。
# ⚠️ 這個檢查失敗**本身就是一次失敗連線**，會把 fail2ban 的封鎖時間重新計算——
#    所以「等一下再跑一次」是永遠出不去的迴圈。看清楚是哪一種再動作，不要盲目重試。
SSH_ERR="$(mktemp)"
if ! "${SSH_CMD[@]}" "$SSH_USER@$HOST" 'true' 2>"$SSH_ERR"; then
  echo "  ❌ SSH 連線失敗。原始錯誤："
  sed 's/^/     /' "$SSH_ERR"
  echo ""
  if grep -qE 'kex_exchange_identification|Connection reset|Connection closed by' "$SSH_ERR"; then
    echo "  → 判定：**fail2ban 封鎖**（TCP 通得了、但一握手就被切斷）"
    echo "     解法：到主機面板把 SSH **停止 → 再啟動**（重啟容器才會清掉 fail2ban 狀態）。"
    echo "     ⚠️ 不要用等的，也不要重跑本腳本——每次失敗都會把封鎖時間歸零。"
  elif grep -qE 'Permission denied|Too many authentication|Invalid key|no matching host key' "$SSH_ERR"; then
    echo "  → 判定：**金鑰問題**（連得上、但不被接受）"
    echo "     解法：確認 $KEY 存在、權限 600、且公鑰有掛在主機上。這與 fail2ban 無關，重啟 SSH 沒用。"
  elif grep -qE 'Connection refused|Connection timed out|No route to host|Operation timed out' "$SSH_ERR"; then
    echo "  → 判定：**SSH sidecar 沒開或網路不通**"
    echo "     先測 TCP：nc -z -w 8 $HOST $PORT"
    echo "     不通 → 到主機面板啟動 SSH；通了卻還是這個錯 → 回頭看上面兩種。"
  else
    echo "  → 無法自動判定。先測 TCP：nc -z -w 8 $HOST $PORT"
    echo "     通 = 多半是 fail2ban（面板停止再啟動）；不通 = sidecar 沒開（面板啟動）。"
  fi
  rm -f "$SSH_ERR"
  exit 1
fi
rm -f "$SSH_ERR"
echo "  ✅ 免密碼登入正常"

# 2b) DRY-RUN 的鏡像預覽：印出「會刪什麼、會新增什麼」，然後停手
#
# 為什麼要有這段（2026-08-05 加）：
# 沒有它的時候，想在部署前知道鏡像會刪掉哪些遠端檔，就只能自己另外開一條 SSH 去
# find 遠端清單——那正是 MEMORY.md「部署的連線紀律」記載、害我們被 fail2ban 擋掉
# 一整個下午的錯誤動作，而且 2026-08-05 又重犯了一次。
#
# 所以把預覽收進本腳本：**一次連線、看得到刪除清單、不上傳任何東西**。
# ⚠️ 代價是 --dry-run 從此需要 SSH。它跟實際部署一樣，連線失敗會把 fail2ban 的
#    封鎖時間歸零，所以 dry-run 也不能盲目重跑。
if [ $DRY_RUN -eq 1 ]; then
  echo "→ 預覽鏡像差異（唯讀，不上傳、不刪除）…"
  list_local_files  > "$ST_LOCAL"
  list_remote_files > "$ST_REMOTE"

  if [ ! -s "$ST_REMOTE" ]; then
    echo "  ⚠️ 遠端清單是空的——可能是 $REMOTE_DIR 不存在（首次部署），"
    echo "     也可能是遠端 find 失敗。首次部署屬正常，其他情況先確認再實際部署。"
  fi

  comm -13 "$ST_LOCAL" "$ST_REMOTE" > "$ST_STALE"
  STALE_N=$(wc -l < "$ST_STALE" | tr -d ' ')
  ADD_N=$(comm -23 "$ST_LOCAL" "$ST_REMOTE" | wc -l | tr -d ' ')

  echo ""
  if [ "$STALE_N" -gt 0 ]; then
    echo "  🗑  實際部署時會從正式站刪除 $STALE_N 個檔："
    sed 's/^/      - /' "$ST_STALE"
    [ "$STALE_N" -gt 50 ] && echo "      ⚠️ 超過 50 個，實際部署會判定異常並中止（不會刪）"
  else
    echo "  🗑  不會刪除任何遠端檔"
  fi
  echo ""
  echo "  ⬆️  會新增／覆寫 $ADD_N 個檔（本機共 $(wc -l < "$ST_LOCAL" | tr -d ' ') 個）"
  echo ""
  echo "DRY-RUN 完成，未對正式站做任何寫入。"
  exit 0
fi

# 3) 上傳 + md5 驗證
echo "→ 上傳…"
"${SSH_CMD[@]}" "$SSH_USER@$HOST" "cat > $REMOTE_TMP" < "$TGZ"
LOCAL_MD5="$(md5 -q "$TGZ" 2>/dev/null || md5sum "$TGZ" | cut -d' ' -f1)"
REMOTE_MD5="$("${SSH_CMD[@]}" "$SSH_USER@$HOST" "md5sum $REMOTE_TMP | cut -d' ' -f1")"
if [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
  echo "  ❌ md5 不符，傳輸有問題，中止"
  echo "     本機：$LOCAL_MD5"
  echo "     遠端：$REMOTE_MD5"
  "${SSH_CMD[@]}" "$SSH_USER@$HOST" "rm -f $REMOTE_TMP" || true
  exit 1
fi
echo "  ✅ md5 一致：$LOCAL_MD5"

# 4) 解壓 + 清理垃圾檔 + 移除暫存
echo "→ 解壓到 $REMOTE_DIR…"
"${SSH_CMD[@]}" "$SSH_USER@$HOST" "
  set -e
  mkdir -p '$REMOTE_DIR'
  tar xzf '$REMOTE_TMP' -C '$REMOTE_DIR'
  find '$REMOTE_DIR' -name '._*' -delete 2>/dev/null || true
  find '$REMOTE_DIR' -name '.DS_Store' -delete 2>/dev/null || true
  rm -f '$REMOTE_TMP'
"
echo "  ✅ 完成"

# 5) 鏡像：刪除遠端多餘檔，再逐檔完整性比對
#    本機檔案清單的排除集必須與上方 EXCLUDES 一致，否則會誤判「多餘」而誤刪。
#    docs/、.claude/、.superpowers/ 是目錄，跟 .git/ 一樣要用 -not -path（! -name 只比對
#    檔名，比對不到目錄，會漏排除）。
echo "→ 對齊遠端（鏡像：刪除本機已無的檔）…"
list_local_files  > "$ST_LOCAL"
list_remote_files > "$ST_REMOTE"

# 多餘檔 = 遠端有、本機沒有（兩份都已 sort）
comm -13 "$ST_LOCAL" "$ST_REMOTE" > "$ST_STALE"
STALE_N=$(wc -l < "$ST_STALE" | tr -d ' ')

if [ "$STALE_N" -gt 0 ]; then
  echo "  遠端多餘 $STALE_N 個檔，將刪除："
  sed 's/^/    - /' "$ST_STALE"
  # 防呆：多餘檔異常多，很可能 REMOTE_DIR 設錯或遠端清單抓失敗，寧可中止不亂刪
  if [ "$STALE_N" -gt 50 ]; then
    echo "  ❌ 多餘檔超過 50 個，判定異常，為安全中止（未刪任何檔案，請人工確認 REMOTE_DIR）"
    exit 1
  fi
  # 逐行刪除（檔名可能含中文／空白，用 stdin 逐行讀，路徑一律綁在 REMOTE_DIR 底下）
  "${SSH_CMD[@]}" "$SSH_USER@$HOST" "cd '$REMOTE_DIR' && while IFS= read -r f; do rm -f \"./\$f\"; done" < "$ST_STALE"
  "${SSH_CMD[@]}" "$SSH_USER@$HOST" "find '$REMOTE_DIR' -type d -empty -delete 2>/dev/null || true"
  # 重抓遠端清單供最終比對
  "${SSH_CMD[@]}" "$SSH_USER@$HOST" "cd '$REMOTE_DIR' && find . -type f | sed 's|^\./||' | sort" > "$ST_REMOTE"
fi

echo "→ 驗證完整性…"
if diff -q "$ST_LOCAL" "$ST_REMOTE" >/dev/null; then
  echo "  ✅ 本機與遠端一致（$(wc -l < "$ST_LOCAL" | tr -d ' ') 個檔案）"
else
  echo "  ⚠️ 對齊後仍有差異（本機缺 < ／遠端多 >）："
  diff "$ST_LOCAL" "$ST_REMOTE" || true
  exit 1
fi

echo ""
echo "✅ 部署完成 — 主題檔已上傳，**未啟用**。"
echo "   正式站目前的啟用主題不受影響。"
echo "   要讓它生效，需人為到 WP 後台啟用。"
echo ""
echo "⚠️ 若正式站有頁面快取外掛（WP Rocket / LiteSpeed / W3TC 等），"
echo "   改動 theme 檔『不會』自動清快取，訪客會繼續看到舊版。"
echo "   驗證務必用『裸網址』curl（加 query 會繞過快取，量到假的成功）。"
