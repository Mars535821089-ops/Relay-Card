#!/bin/bash
# 接力卡索引生成器 (Relay Card Indexer) - 工具无关
# ============================================================================
# 用途: 重建 $RELAY_DIR/latest.md, 列出最近 N 张卡片
#
# 调用:
#   bash relay-card-index.sh        # 默认 5 张
#   bash relay-card-index.sh 10     # 显示 10 张
# ============================================================================

set -euo pipefail

RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
LATEST="$RELAY_DIR/latest.md"
KEEP_RECENT="${1:-5}"

mkdir -p "$RELAY_DIR"

# 按文件名 (YYYYMMDD-HHMMSS) 排序; mtime 不可靠
CARDS=$(find "$RELAY_DIR" -maxdepth 1 -name "[0-9]*.md" -type f 2>/dev/null | sort -r | head -n "$KEEP_RECENT")

TMP="${LATEST}.tmp.$$"
{
  echo "📋 接力卡清单 (按时间倒序, 最多 $KEEP_RECENT 张)"
  echo ""
  i=0
  echo "$CARDS" | while IFS= read -r f; do
    [ -z "$f" ] && continue
    i=$((i+1))
    bn=$(basename "$f")
    time_label=$(echo "$bn" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2}).*/\1-\2-\3 \4:\5:\6/')
    project=$(grep -oE '项目根.*`[^`]+' "$f" 2>/dev/null | head -1 | sed -E 's/.*`([^`]+).*/\1/' | xargs basename 2>/dev/null || true)
    [ -z "$project" ] && project="?"
    branch=$(grep -oE '当前分支.*`[^`]+' "$f" 2>/dev/null | head -1 | sed -E 's/.*`([^`]+).*/\1/' || true)
    [ -z "$branch" ] && branch="?"
    goal=$(awk '/## 🎯 当前任务/{flag=1;next} /^---/{if(flag)exit} flag' "$f" 2>/dev/null | grep -v '^$' | head -3 | tr '\n' ';' | cut -c1-100 || true)
    [ -z "$goal" ] && goal="(无任务描述)"
    project_e=$(printf '%s' "$project" | sed 's/|/\\|/g')
    branch_e=$(printf '%s' "$branch" | sed 's/|/\\|/g')
    goal_e=$(printf '%s' "$goal" | sed 's/|/\\|/g')
    echo "### #$i  \`$bn\`"
    echo ""
    echo "- **时间**: $time_label"
    echo "- **项目**: $project_e"
    echo "- **分支**: \`$branch_e\`"
    echo "- **任务**: $goal_e"
    echo "- **路径**: \`$f\`"
    echo ""
  done
  echo "---"
  echo "**操作指南:**"
  echo "- 让 AI 读最新一张卡: \`~/.relay-cards/latest.md\`"
  echo "- 或直接读路径里那张完整卡"
} > "$TMP"
mv -f "$TMP" "$LATEST"

echo "✅ latest.md 已刷新 ($KEEP_RECENT 张)" >&2