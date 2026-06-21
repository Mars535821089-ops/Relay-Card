#!/bin/bash
# 接力卡敏感信息脱敏器 (Relay Card Sanitizer) - bash wrapper
# ============================================================================
# 调用 relay_card_sanitize.py 做实际工作
#
# 用法:
#   cat file.md | bash relay-card-sanitize.sh         # 流式 stdin → stdout
#   bash relay-card-sanitize.sh file.md               # 原地, 备份到 .bak.YYYYMMDD-HHMMSS
#   bash relay-card-sanitize.sh --test                # 自检
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_CORE="$SCRIPT_DIR/relay_card_sanitize.py"
LOG_FILE="$RELAY_DIR/.sanitize.log"
mkdir -p "$RELAY_DIR"

if [ ! -f "$PY_CORE" ]; then
  echo "ERROR: 找不到 $PY_CORE" >&2
  exit 2
fi

# 自检模式
if [ "${1:-}" = "--test" ]; then
  echo "=== 自检 ==="
  for tc in \
    'sk-1234567890abcdef1234567890abcdef' \
    'Bearer abc123xyz456def789ghi012jkl' \
    'ghp_abcdefghijklmnopqrstuvwxyz1234567890' \
    'user@example.com' \
    'OPENAI_API_KEY=sk-proj-xxxxxxxxxxxxx' \
    'AKIA1234567890ABCDEF' \
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c' \
    'Normal text without secrets, like /home/user/project/main.py'; do
    result=$(echo "$tc" | python3 "$PY_CORE" 2>/dev/null)
    echo "INPUT : $tc"
    echo "OUTPUT: $result"
    echo "---"
  done
  exit 0
fi

INPUT_FILE="${1:-}"

if [ -n "$INPUT_FILE" ] && [ -f "$INPUT_FILE" ]; then
  # 原地模式
  BACKUP="${INPUT_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$INPUT_FILE" "$BACKUP"
  TMP="${INPUT_FILE}.tmp.$$"
  if python3 "$PY_CORE" <"$INPUT_FILE" >"$TMP" 2> >(tee -a "$LOG_FILE" >&2); then
    mv -f "$TMP" "$INPUT_FILE"
    echo "[sanitize] $INPUT_FILE 已脱敏 (备份: $BACKUP)" >&2
  else
    rm -f "$TMP"
    rm -f "$BACKUP"
    echo "[sanitize] 失败, 原文件未改" >&2
    exit 1
  fi
elif [ ! -t 0 ]; then
  # 流式: stdin → stdout
  python3 "$PY_CORE" 2> >(tee -a "$LOG_FILE" >&2)
else
  cat <<EOF >&2
用法:
  cat file.md | bash relay-card-sanitize.sh > clean.md     # 流式
  bash relay-card-sanitize.sh file.md                      # 原地 (备份)
  bash relay-card-sanitize.sh --test                       # 自检
EOF
  exit 1
fi
