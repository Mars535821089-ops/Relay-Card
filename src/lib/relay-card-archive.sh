#!/bin/bash
# 接力卡归档清理工具 (Relay Card Archiver) - 工具无关
# ============================================================================
# 策略:
#   1. 活跃区: 根目录保留最近 N 张 (默认 10), 其余移入 archive/YYYY-MM/
#   2. 归档区: archive/YYYY-MM/ 按年月归档, 不再被 restore 读取
#   3. 清理区: 超过 D 天的归档 (默认 90) 进 archive/_compressed/, 可选 gzip
#   4. 安全: 写卡 stamp + dry-run + 备份, 决不会删除带 .pin 的卡
#
# 用法:
#   bash relay-card-archive.sh                # 默认: keep=10, age=90d
#   bash relay-card-archive.sh --dry-run      # 演练
#   bash relay-card-archive.sh --keep 5       # 自定义活跃保留数
#   bash relay-card-archive.sh --max-age 30   # 自定义归档保留天数
#   bash relay-card-archive.sh --compress     # 旧归档卡再 gzip
#   bash relay-card-archive.sh --stats        # 只打统计, 不动文件
#
# 钉住保护: 想保留某张卡永不归档, 在卡片同名加 .pin:
#   touch ~/.relay-cards/20260612-xxx.md.pin
# ============================================================================

set -euo pipefail

RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
ARCHIVE_DIR="$RELAY_DIR/archive"
COMPRESSED_DIR="$ARCHIVE_DIR/_compressed"
STAMP="$RELAY_DIR/.archive-stamp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEEP_ACTIVE=10
MAX_AGE_DAYS=90
DRY_RUN=0
COMPRESS=0
STATS_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --keep)
      KEEP_ACTIVE="$2"
      shift 2
      ;;
    --max-age)
      MAX_AGE_DAYS="$2"
      shift 2
      ;;
    --compress)
      COMPRESS=1
      shift
      ;;
    --stats)
      STATS_ONLY=1
      shift
      ;;
    --help | -h)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$RELAY_DIR" ]; then
  echo "[archive] $RELAY_DIR 不存在, 退出"
  exit 0
fi

mkdir -p "$ARCHIVE_DIR" "$COMPRESSED_DIR"

# === 统计 ===
ACTIVE_COUNT=$(ls -1 "$RELAY_DIR"/[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)
ARCHIVE_COUNT=$(find "$ARCHIVE_DIR" -mindepth 2 -maxdepth 2 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ' || true)
COMPRESSED_COUNT=$(ls -1 "$COMPRESSED_DIR"/*.md.gz 2>/dev/null | wc -l | tr -d ' ' || true)
BAK_COUNT=$(ls -1 "$RELAY_DIR"/*.bak.* 2>/dev/null | wc -l | tr -d ' ' || true)
TOTAL_SIZE=$(du -sh "$RELAY_DIR" 2>/dev/null | awk '{print $1}')

echo "════════════════════════════════════════"
echo "📊 接力卡库存"
echo "════════════════════════════════════════"
echo "  活跃: $ACTIVE_COUNT 张 (上限 $KEEP_ACTIVE)"
echo "  归档: $ARCHIVE_COUNT 张 (archive/YYYY-MM/)"
echo "  压缩: $COMPRESSED_COUNT 张 (archive/_compressed/, > ${MAX_AGE_DAYS}d)"
echo "  备份: $BAK_COUNT 个 .bak.* 文件"
echo "  总体: $TOTAL_SIZE"

if [ "$STATS_ONLY" = "1" ]; then
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "════════════════════════════════════════"
  echo "🧪 DRY-RUN 模式, 不会修改"
fi

# === Step 1: 活跃 → 归档 ===
# KEEP_ACTIVE 指的是"非 pin 的最大保留数"; pin 卡永远不归档
MOVED_ARCHIVE=0
if [ "$ACTIVE_COUNT" -gt "$KEEP_ACTIVE" ]; then
  echo "════════════════════════════════════════"
  echo "📦 归档 (超过 $KEEP_ACTIVE 张的旧卡, pin 卡永不动)"
  echo "════════════════════════════════════════"
  CARDS_SORTED=$(ls -1 "$RELAY_DIR"/[0-9]*.md 2>/dev/null | sort -r || true)
  # 统计 pin 数量, KEEP_ACTIVE 减去 pin 后是 "非 pin 保留位"
  PIN_COUNT=$(ls -1 "$RELAY_DIR"/[0-9]*.md.pin 2>/dev/null | wc -l | tr -d ' ' || true)
  PIN_COUNT="${PIN_COUNT:-0}"
  NON_PIN_KEEP=$((KEEP_ACTIVE - PIN_COUNT))
  # 如果 pin 已占满 KEEP_ACTIVE, 非 pin 全归档
  if [ "$NON_PIN_KEEP" -lt 0 ]; then NON_PIN_KEEP=0; fi
  # 非 pin 卡在 sort 后, 按"非 pin 内的位置"判定
  NON_PIN_IDX=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # pin 卡永远不归档
    if [ -f "${f}.pin" ]; then
      echo "  📌 keep (pinned): $(basename "$f")"
      continue
    fi
    NON_PIN_IDX=$((NON_PIN_IDX + 1))
    # 保留前 NON_PIN_KEEP 张非 pin
    if [ "$NON_PIN_IDX" -le "$NON_PIN_KEEP" ]; then
      continue
    fi
    bn=$(basename "$f")
    year_month=$(echo "$bn" | sed -E 's/^([0-9]{4})([0-9]{2}).*/\1-\2/')
    target_dir="$ARCHIVE_DIR/$year_month"
    target="$target_dir/$bn"
    if [ "$DRY_RUN" = "0" ]; then
      mkdir -p "$target_dir"
      mv -f "$f" "$target" 2>/dev/null && echo "  ✅ → $year_month/$bn"
    else
      echo "  → $year_month/$bn  (dry-run)"
    fi
    MOVED_ARCHIVE=$((MOVED_ARCHIVE + 1))
  done <<<"$CARDS_SORTED"
fi

# === Step 2: 归档 → 压缩 ===
MOVED_COMPRESSED=0
if [ "$COMPRESS" = "1" ] && [ -d "$ARCHIVE_DIR" ]; then
  echo "════════════════════════════════════════"
  echo "🗜️  压缩 (归档超过 ${MAX_AGE_DAYS} 天的)"
  echo "════════════════════════════════════════"
  find "$ARCHIVE_DIR" -mindepth 2 -maxdepth 2 -name "*.md" -type f -mtime +"$MAX_AGE_DAYS" 2>/dev/null | while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -f "${f}.pin" ]; then
      echo "  📌 keep (pinned): $(basename "$f")"
      continue
    fi
    bn=$(basename "$f")
    target="$COMPRESSED_DIR/${bn}.gz"
    if [ "$DRY_RUN" = "0" ]; then
      if gzip -c "$f" >"$target" 2>/dev/null; then
        rm -f "$f"
        echo "  ✅ gzip → _compressed/${bn}.gz"
      else
        echo "  ❌ gzip 失败: $bn" >&2
      fi
    else
      echo "  → _compressed/${bn}.gz  (dry-run)"
    fi
    MOVED_COMPRESSED=$((MOVED_COMPRESSED + 1))
  done
fi

# === Step 3: 清理 .bak 老备份 ===
CLEANED_BAK=0
if [ "$BAK_COUNT" -gt 0 ]; then
  echo "════════════════════════════════════════"
  echo "🧹 清理 .bak 备份 (超过 30 天)"
  echo "════════════════════════════════════════"
  find "$RELAY_DIR" -maxdepth 1 -name "*.bak.*" -mtime +30 2>/dev/null | while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$DRY_RUN" = "0" ]; then
      rm -f "$f" && echo "  🗑️  $(basename "$f")"
    else
      echo "  🗑️  $(basename "$f")  (dry-run)"
    fi
    CLEANED_BAK=$((CLEANED_BAK + 1))
  done
fi

# === 写 stamp ===
if [ "$DRY_RUN" = "0" ]; then
  date -u +"%Y-%m-%dT%H:%M:%SZ archive keep=${KEEP_ACTIVE} max_age=${MAX_AGE_DAYS}d compress=${COMPRESS}" >"$STAMP"

  LAST_ARCHIVE_JSON="$RELAY_DIR/.last-archive.json"
  cat >"$LAST_ARCHIVE_JSON" <<EOF
{
  "ts": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "active": $ACTIVE_COUNT,
  "archived": $ARCHIVE_COUNT,
  "compressed": $COMPRESSED_COUNT,
  "moved_to_archive_this_run": ${MOVED_ARCHIVE:-0},
  "compressed_this_run": ${MOVED_COMPRESSED:-0},
  "cleaned_bak_this_run": ${CLEANED_BAK:-0},
  "keep_active": $KEEP_ACTIVE,
  "max_age_days": $MAX_AGE_DAYS
}
EOF
  chmod 600 "$LAST_ARCHIVE_JSON" 2>/dev/null || true

  # 调 indexer 刷新 latest.md, 避免它指向已归档的卡
  INDEXER="$SCRIPT_DIR/relay-card-index.sh"
  if [ -x "$INDEXER" ]; then
    bash "$INDEXER" 5 2>/dev/null || true
  fi

  echo "════════════════════════════════════════"
  echo "✅ 归档完成 (stamp + .last-archive.json 已写, latest.md 已刷)"
  echo "════════════════════════════════════════"
fi
