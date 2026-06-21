#!/bin/bash
# 批量脱敏所有历史接力卡 (一次性工具)
# ============================================================================
# 用途: 给已经存在的老卡 补脱敏
# 用法:
#   bash relay-card-sanitize-all.sh --dry-run    # 看会改哪些, 不动文件
#   bash relay-card-sanitize-all.sh              # 真改, 原地 + .bak 备份
#   bash relay-card-sanitize-all.sh --no-backup  # 不留 bak (省空间)
#
# 完成后写 .sanitized-stamp 标记, 避免重复跑
# ============================================================================

set -euo pipefail

RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
STAMP="$RELAY_DIR/.sanitized-stamp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SANITIZER="$SCRIPT_DIR/relay-card-sanitize.sh"
PY_CORE="$SCRIPT_DIR/relay_card_sanitize.py"

DRY_RUN=0
NO_BACKUP=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  --no-backup) NO_BACKUP=1 ;;
  --help | -h)
    sed -n '2,15p' "$0"
    exit 0
    ;;
esac

if [ ! -d "$RELAY_DIR" ]; then
  echo "[batch-sanitize] $RELAY_DIR 不存在, 跳过"
  exit 0
fi

if [ ! -f "$PY_CORE" ]; then
  echo "[batch-sanitize] 缺 $PY_CORE" >&2
  exit 2
fi

# 收集所有卡 (含 latest.md, 不含 archive/)
CARDS=()
while IFS= read -r -d '' f; do
  CARDS+=("$f")
done < <(find "$RELAY_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

if [ ${#CARDS[@]} -eq 0 ]; then
  echo "[batch-sanitize] 无卡片, 退出"
  exit 0
fi

echo "[batch-sanitize] 找到 ${#CARDS[@]} 张卡"
[ "$DRY_RUN" = "1" ] && echo "[batch-sanitize] DRY-RUN 模式, 不会修改"

TOTAL_HITS=0
CHANGED_COUNT=0
for f in "${CARDS[@]}"; do
  TMP="${f}.scan.$$"
  REPORT="${f}.report.$$"
  python3 "$PY_CORE" <"$f" >"$TMP" 2>"$REPORT"

  if ! cmp -s "$f" "$TMP"; then
    CHANGED_COUNT=$((CHANGED_COUNT + 1))
    HITS=$(cat "$REPORT" 2>/dev/null || echo "")
    echo "  📝 $(basename "$f")  $HITS"
    if [ "$DRY_RUN" = "0" ]; then
      if [ "$NO_BACKUP" = "0" ]; then
        cp "$f" "${f}.bak.batch-$(date +%Y%m%d)"
      fi
      mv -f "$TMP" "$f"
    else
      rm -f "$TMP"
    fi
  else
    rm -f "$TMP"
  fi
  rm -f "$REPORT"
done

echo "[batch-sanitize] 完成: ${CHANGED_COUNT}/${#CARDS[@]} 张含敏感信息"

if [ "$DRY_RUN" = "0" ] && [ "$CHANGED_COUNT" -gt 0 ]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ batch-sanitize ${CHANGED_COUNT}/${#CARDS[@]}" >"$STAMP"
  echo "[batch-sanitize] 写入 stamp: $STAMP"
fi
