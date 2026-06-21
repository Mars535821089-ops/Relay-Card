#!/bin/bash# 接力任务卡生成器 (Relay Task Card Generator)
# ============================================================================
# 用途: 在上下文即将耗尽 / 即将 compact 之前，自动生成可交接的任务卡
# 触发: Claude Code PreCompact hook (auto/manual)
# 输出:
#   1. 写入 $RELAY_DIR/YYYYMMDD-HHMMSS-{branch}.md
#   2. 卡片内容打印到 stdout (Claude 看到后会立刻接力摘要)
#   3. 通过 JSON hookSpecificOutput.additionalContext 注入到上下文
#
# 这是 Relay Card 框架的 PreCompact adapter 实现。
# 适配器仅与 AI 工具事件层打交道,核心逻辑走 src/lib/relay-card-write.sh。
# ============================================================================

set -euo pipefail

RELAY_HOME="${RELAY_HOME:-$HOME/.claude/hooks}"
RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
CORE_WRITE="$RELAY_HOME/relay-card-write.sh"

# 从 stdin 提取 session_id + transcript_path (PreCompact hook 提供)
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

# 提取 hook payload
SESSION_ID=""
TRANSCRIPT_PATH=""
if [ -n "$STDIN_DATA" ]; then
  PARSED=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    sid = d.get('session_id', 'unknown')[:8]
    tp = d.get('transcript_path', '')
    print(f'{sid}|{tp}')
except Exception:
    print('unknown|')
" 2>/dev/null || echo "unknown|")
  SESSION_ID="${PARSED%%|*}"
  TRANSCRIPT_PATH="${PARSED##*|}"
fi

# session_id 拿不到时用 PID + 纳秒保底
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "unknown" ]; then
  SESSION_ID="pid$$-$(date +%N 2>/dev/null | cut -c1-6 || echo "fallback")"
fi

# 把 transcript_path 通过 env 传给 core (它会用 @transcript:xxx 协议)
export TRANSCRIPT_PATH
export CLAUDE_SESSION_ID="$SESSION_ID"

# 调用 core 写接力卡
if [ -x "$CORE_WRITE" ]; then
  bash "$CORE_WRITE" --auto
else
  echo "❌ 找不到 $CORE_WRITE" >&2
  exit 2
fi

# === PreCompact 专有: 输出 JSON hook payload ===
# 用 Python json.dumps 避免 bash 字符串替换吞掉反斜杠/$
CARD_FILE=$(ls -1t "$RELAY_DIR"/[0-9]*.md 2>/dev/null | head -1)
BRANCH=$(git rev-parse --show-current 2>/dev/null || echo "no-git")
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT_NAME=$(basename "$PROJECT_ROOT" 2>/dev/null || echo "unknown")

if [ -n "$CARD_FILE" ] && [ -f "$CARD_FILE" ]; then
  KEYWORDS=$(grep -m1 '🏷️ \*\*关键词\*\*' "$CARD_FILE" 2>/dev/null | sed -E 's/.*关键词\*\*:[[:space:]]*//' | head -c 120)
  [ -z "$KEYWORDS" ] && KEYWORDS="_(未提取)_"
else
  CARD_FILE="$RELAY_DIR/(未生成)"
  KEYWORDS="_(未提取)_"
fi

CARD_FILE="$CARD_FILE" \
BRANCH="$BRANCH" \
PROJECT_NAME="$PROJECT_NAME" \
KEYWORDS="$KEYWORDS" \
python3 <<'PYEOF'
import json, os
out = {
    "systemMessage": f"🏃 接力卡已生成: {os.environ['CARD_FILE']}",
    "hookSpecificOutput": {
        "hookEventName": "PreCompact",
        "additionalContext": (
            f"接力卡已保存到 {os.environ['CARD_FILE']}\n\n"
            f"关键词: {os.environ['KEYWORDS']}\n"
            f"分支: {os.environ['BRANCH']}\n"
            f"项目: {os.environ['PROJECT_NAME']}\n\n"
            "紧凑后请 AI 读取此文件继续工作。"
        )
    }
}
print(json.dumps(out, ensure_ascii=False))
PYEOF