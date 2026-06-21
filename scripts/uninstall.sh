#!/bin/bash
# ============================================================================
# Relay Card 卸载脚本
# ============================================================================
# 卸哪些:
#   - $RELAY_HOME/relay-card*.sh + relay_card_*.py
#   - $RELAY_HOME/relay-card-claude-adapter/
#   - $BIN_DIR/relay-*
#   - settings.json 里的 relay-card hooks 段 (其它配置保留)
#
# 保留:
#   - $RELAY_DIR (历史卡片, 默认不删, --purge 才删)
#
# 用法:
#   bash scripts/uninstall.sh
#   bash scripts/uninstall.sh --dry-run
#   bash scripts/uninstall.sh --purge    # 同时清空历史卡片
# ============================================================================

set -euo pipefail

RELAY_HOME="${RELAY_HOME:-$HOME/.claude/hooks}"
RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.claude/settings.json}"

DRY_RUN=0
PURGE=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  --purge)   PURGE=1 ;;
  --help|-h)
    sed -n '2,16p' "$0"
    exit 0
    ;;
esac

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [DRY-RUN] $*"
  else
    "$@"
  fi
}

echo "▶ 卸载 Relay Card"

# === 卸核心脚本 ===
if [ -d "$RELAY_HOME" ]; then
  echo "▶ 从 $RELAY_HOME 移除 relay-card* 文件"
  for f in "$RELAY_HOME"/relay-card*.sh "$RELAY_HOME"/relay_card_*.py; do
    [ -f "$f" ] || continue
    run rm -f "$f"
    echo "  ✓ $(basename "$f")"
  done
  # 卸 adapter 目录
  if [ -d "$RELAY_HOME/relay-card-claude-adapter" ]; then
    run rm -rf "$RELAY_HOME/relay-card-claude-adapter"
    echo "  ✓ relay-card-claude-adapter/"
  fi
fi

# === 卸 PATH 命令 ===
if [ -d "$BIN_DIR" ]; then
  echo "▶ 从 $BIN_DIR 移除 relay-* 软链"
  for f in "$BIN_DIR"/relay-*; do
    [ -L "$f" ] || continue
    run rm -f "$f"
    echo "  ✓ $(basename "$f")"
  done
fi

# === 从 settings.json 移除 hooks ===
if [ -f "$SETTINGS_FILE" ]; then
  echo "▶ 从 $SETTINGS_FILE 移除 relay-card hooks"
  if [ "$DRY_RUN" = "0" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak.uninstall-$(date +%Y%m%d-%H%M%S)"
    python3 -c "
import json
sp = '$SETTINGS_FILE'
with open(sp) as f:
    s = json.load(f)
if 'hooks' in s:
    for event, hook_list in s['hooks'].items():
        s['hooks'][event] = [
            entry for entry in hook_list
            if not any('relay-card' in h.get('command', '') or 'relay_card' in h.get('command', '')
                       for h in entry.get('hooks', []))
        ]
    # 清理空列表
    s['hooks'] = {k: v for k, v in s['hooks'].items() if v}
    if not s['hooks']: del s['hooks']
with open(sp, 'w') as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
print('  ✓ relay-card hooks 已从 settings.json 移除')
"
  else
    echo "  [DRY-RUN] 合并修改 $SETTINGS_FILE"
  fi
fi

# === 卸历史卡片 (可选) ===
if [ "$PURGE" = "1" ]; then
  if [ -d "$RELAY_DIR" ]; then
    echo "▶ 清空历史卡片 $RELAY_DIR"
    if [ "$DRY_RUN" = "0" ]; then
      # 备份到 ~/.relay-cards-purge-YYYYMMDD
      BAK="${RELAY_DIR}-purge-$(date +%Y%m%d-%H%M%S)"
      mv "$RELAY_DIR" "$BAK"
      echo "  ✓ 已备份到 $BAK"
    else
      echo "  [DRY-RUN] mv $RELAY_DIR ${RELAY_DIR}-purge-..."
    fi
  fi
else
  if [ -d "$RELAY_DIR" ]; then
    echo "▶ 保留历史卡片: $RELAY_DIR (用 --purge 一起清)"
  fi
fi

cat <<EOF

════════════════════════════════════════
✅ Relay Card 卸载完成
════════════════════════════════════════
EOF
