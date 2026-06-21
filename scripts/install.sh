#!/bin/bash
# ============================================================================
# Relay Card 一键安装脚本
# ============================================================================
# 装到哪里:
#   - 核心脚本: $RELAY_HOME (默认 ~/.claude/hooks/) — 兼容 Claude Code 布局
#   - PATH 命令: $HOME/.local/bin/
#   - 接力卡目录: $RELAY_DIR (默认 ~/.relay-cards/)
#
# 自动配置:
#   - 在 ~/.claude/settings.json 的 hooks 段注入 PreCompact + SessionStart
#   - 不修改任何其它字段
#
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/Mars535821089-ops/Relay-Card/main/scripts/install.sh | bash
#   bash scripts/install.sh                # 默认安装
#   bash scripts/install.sh --uninstall    # 卸载
#   bash scripts/install.sh --dry-run      # 看会做什么
# ============================================================================

set -euo pipefail

# === Defaults ===
RELAY_HOME="${RELAY_HOME:-$HOME/.claude/hooks}"
RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SETTINGS_FILE="${SETTINGS_FILE:-$HOME/.claude/settings.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# === Parse args ===
DRY_RUN=0
UNINSTALL=0
case "${1:-}" in
  --uninstall) UNINSTALL=1 ;;
  --dry-run) DRY_RUN=1 ;;
  --help | -h)
    sed -n '2,18p' "$0"
    exit 0
    ;;
  "") ;;
  *)
    echo "❌ 未知参数: $1" >&2
    echo "用法: $0 [--uninstall|--dry-run]" >&2
    exit 1
    ;;
esac

# === Helpers ===
run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [DRY-RUN] $*"
  else
    "$@"
  fi
}

say() {
  echo "▶ $1"
}

# === Uninstall ===
if [ "$UNINSTALL" = "1" ]; then
  say "卸载 Relay Card"
  bash "$SCRIPT_DIR/uninstall.sh" $([ "$DRY_RUN" = "1" ] && echo "--dry-run")
  exit $?
fi

# === Pre-flight checks ===
say "Pre-flight checks"
command -v bash >/dev/null 2>&1 || {
  echo "❌ 需要 bash"
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "❌ 需要 python3"
  exit 1
}
BASH_VER=$(bash -c 'echo ${BASH_VERSION}' | cut -d. -f1)
if [ "${BASH_VER:-0}" -lt 4 ]; then
  echo "⚠️  bash 4+ 推荐 (你的是 $BASH_VER), 老版本可能部分功能不工作"
fi
PY_VER=$(python3 -c 'import sys; print(sys.version_info[0])')
if [ "${PY_VER:-0}" -lt 3 ]; then
  echo "❌ 需要 python 3+"
  exit 1
fi

# === Step 1: 准备目录 ===
say "Step 1: 创建目录"
run mkdir -p "$RELAY_HOME"
run mkdir -p "$RELAY_DIR"
run mkdir -p "$BIN_DIR"

# === Step 2: 复制核心脚本 ===
say "Step 2: 复制 src/lib/ 到 $RELAY_HOME"
for src in "$REPO_ROOT/src/lib/"*.sh; do
  [ -f "$src" ] || continue
  bn=$(basename "$src")
  run cp -f "$src" "$RELAY_HOME/$bn"
  run chmod +x "$RELAY_HOME/$bn"
  echo "  ✓ $bn"
done

# 复制 Python 核心
for src in "$REPO_ROOT/src/lib/"*.py; do
  [ -f "$src" ] || continue
  bn=$(basename "$src")
  run cp -f "$src" "$RELAY_HOME/$bn"
  echo "  ✓ $bn"
done

# === Step 3: 复制 adapter scripts ===
say "Step 3: 复制 Claude Code adapter"
ADAPTER_DIR="$RELAY_HOME/relay-card-claude-adapter"
run mkdir -p "$ADAPTER_DIR"
for src in "$REPO_ROOT/src/adapters/claude-code/"*.sh; do
  [ -f "$src" ] || continue
  bn=$(basename "$src")
  run cp -f "$src" "$ADAPTER_DIR/$bn"
  run chmod +x "$ADAPTER_DIR/$bn"
  echo "  ✓ adapter/$bn"
done

# === Step 4: 装 PATH 命令 ===
say "Step 4: 装 PATH 命令到 $BIN_DIR"
for src in "$REPO_ROOT/bin/"*; do
  [ -f "$src" ] || continue
  bn=$(basename "$src")
  run ln -sf "$src" "$BIN_DIR/$bn"
  echo "  ✓ $BIN_DIR/$bn → $src"
done

# === Step 5: 配 Claude Code hooks ===
say "Step 5: 配置 Claude Code hooks"
if [ -f "$SETTINGS_FILE" ]; then
  # 备份
  if [ "$DRY_RUN" = "0" ]; then
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.bak.$(date +%Y%m%d-%H%M%S)"
  fi
  echo "  ✓ 已备份 $SETTINGS_FILE"

  # 用 Python 合并 hooks 配置 (幂等)
  HOOK_SNIPPET="$REPO_ROOT/src/adapters/claude-code/settings.hooks.json"
  if [ -f "$HOOK_SNIPPET" ]; then
    if [ "$DRY_RUN" = "0" ]; then
      python3 -c "
import json, sys

settings_path = '$SETTINGS_FILE'
snippet_path = '$HOOK_SNIPPET'

with open(settings_path) as f:
    settings = json.load(f)
with open(snippet_path) as f:
    snippet = json.load(f)

# 幂等合并: PreCompact + SessionStart
if 'hooks' not in settings:
    settings['hooks'] = {}

for event, hook_list in snippet.get('hooks', {}).items():
    if event not in settings['hooks']:
        settings['hooks'][event] = []
    # 检查是否已装 (按 command 字段去重)
    existing_cmds = set()
    for entry in settings['hooks'][event]:
        for h in entry.get('hooks', []):
            existing_cmds.add(h.get('command', ''))
    for new_entry in hook_list:
        should_add = True
        for h in new_entry.get('hooks', []):
            if h.get('command', '') in existing_cmds:
                should_add = False
                break
        if should_add:
            settings['hooks'][event].append(new_entry)

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
print('  ✓ hooks 已合并到 settings.json')
"
    else
      echo "  [DRY-RUN] 合并 hooks 到 $SETTINGS_FILE"
    fi
  fi
else
  echo "  ⚠️  $SETTINGS_FILE 不存在, 跳过 hooks 配置"
  echo "      (Claude Code 用户: 请创建此文件并手动配 hooks, 见 docs/adapters.md)"
fi

# === Step 6: 自检 ===
say "Step 6: 自检"
if [ "$DRY_RUN" = "0" ]; then
  if bash "$RELAY_HOME/relay-card-sanitize.sh" --test >/dev/null 2>&1; then
    echo "  ✅ sanitize 自检通过"
  else
    echo "  ⚠️  sanitize 自检失败, 详见: bash $RELAY_HOME/relay-card-sanitize.sh --test"
  fi
fi

# === Done ===
cat <<EOF

════════════════════════════════════════
✅ Relay Card 安装完成
════════════════════════════════════════
📁 核心脚本:  $RELAY_HOME
📂 卡片目录:  $RELAY_DIR
🔧 PATH 命令: $BIN_DIR
⚙️  配置:     $SETTINGS_FILE (已备份)

下一步:
  1. 把 $BIN_DIR 加到 PATH (如果还没加)
       echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.zshrc && source ~/.zshrc
  2. 验证: relay-save --auto
  3. 跑 /compact 看 PreCompact 触发

卸载: $0 --uninstall
════════════════════════════════════════
EOF
