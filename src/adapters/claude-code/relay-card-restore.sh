# 接力卡恢复器 (Relay Card Restore)
# ============================================================================
# 用途: SessionStart 时注入接力卡 #1 路径 (OPT-IN 原则)
#
# OPT-IN 原则:
#   - 默认不读接力卡 (避免浪费 token)
#   - 只有 user 说 "继续 XXX" / 敲 /relay-restore 才读
#   - 接力卡存在 ≠ 应该读接力卡
#
# 输出: 200 字节 JSON (含 system message + additionalContext 提示)
# ============================================================================

set -euo pipefail

RELAY_HOME="${RELAY_HOME:-$HOME/.claude/hooks}"
RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"

if [ ! -d "$RELAY_DIR" ]; then
  echo '{"systemMessage":"无接力卡","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
  exit 0
fi

TOP_FILE=$(ls -1t "$RELAY_DIR"/[0-9]*.md 2>/dev/null | head -1 || true)

if [ -z "$TOP_FILE" ] || [ ! -f "$TOP_FILE" ]; then
  echo '{"systemMessage":"无接力卡","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
  exit 0
fi

export TOP_FILE
python3 << 'PYEOF'
import json, os
top = os.environ["TOP_FILE"]
bn = os.path.basename(top).replace(".md", "")

# 抽 goal (第一行非空非 # 的内容)
goal = ""
try:
    with open(top, "r", encoding="utf-8") as f:
        in_goal = False
        for line in f:
            if "## 当前任务" in line or "## 🎯 当前任务" in line:
                in_goal = True
                continue
            if in_goal:
                if line.strip().startswith("---"):
                    break
                if line.strip() and not line.strip().startswith("#"):
                    goal = line.strip()[:100]
                    break
except Exception:
    goal = "(无任务)"

system_msg = f"接力卡 #1 存在 (opt-in, 默认不读): {bn}"
if goal and goal != "(无任务)":
    system_msg += f" — {goal}"

additional = (
    f"接力卡文件: {top}\n"
    f"**OPT-IN 原则**: 默认不读接力卡。接力卡存在 ≠ 应该读接力卡。\n"
    f"**触发条件** (满足任一才 Read):\n"
    f"  - user 说 '继续 XXX' / '接着 X' / '接 #N'\n"
    f"  - user 主动敲 /relay-restore slash command\n"
    f"**不要 Read** (即使存在接力卡):\n"
    f"  - user 问新问题 / 让搜互联网 / 做与接力卡无关的事\n"
    f"  - user 明确说 '不需要继续' / '这是新内容' / /clear 后\n"
    f"  - 接力卡 goal 段任务 ≠ user 当前意图时\n"
    f"**关键词越级 (user 说 '继续 XXX' 时)**:\n"
    f"  1. `grep -liEr 'XXX' ~/.relay-cards/ --include='[0-9]*.md' | head -5` 找候选\n"
    f"  2. 对每张候选 `awk '/## 🎯 当前任务/,/^---/{{print; if(/^---/)exit}}'` 抽 goal 段\n"
    f"  3. 选 goal 段主任务最匹配的那张 → Read 它续上下文, 跳过 #1。"
)

out = {
    "systemMessage": system_msg,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": additional,
    }
}
print(json.dumps(out, ensure_ascii=False))
PYEOF