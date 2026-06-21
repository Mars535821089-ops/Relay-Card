#!/bin/bash
# 接力卡写入器 (Relay Card Writer) - 工具无关核心
# ============================================================================
# 用途: 让 AI/用户在任意时刻存档接力卡
# 调用:
#   bash relay-card-write.sh --auto                                    # 机械快照
#   cat payload.json | bash relay-card-write.sh                        # 主动写
#
# 输入 JSON 字段:
#   title       - 卡片标题 (≤30 字符)
#   goal        - 当前任务的一句话描述
#   done[]      - 已完成列表
#   todo[]      - 待办列表
#   decisions[] - 关键决策列表
#   pits[]      - 踩过的坑列表
#   priority[]  - 对应 todo[] 的 P0/P1/P2 优先级
#
# 输出:
#   - 写入 $RELAY_DIR/YYYYMMDD-HHMMSS-{sid}-{prefix}-{branch}.md
#   - 调 relay-card-index.sh 刷新 latest.md
#   - 调 relay-card-sanitize.sh 脱敏
# ============================================================================

set -euo pipefail

RELAY_HOME="${RELAY_HOME:-$HOME/.relay-card/hooks}"
RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$RELAY_DIR"

# === 时间戳和 session_id ===
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ISO_TIME=$(date '+%Y-%m-%d %H:%M:%S %z')

SESSION_ID="${CLAUDE_SESSION_ID:-${CLAUDE_SESSION:-unknown}}"
SESSION_ID=$(printf '%s' "$SESSION_ID" | head -c 8)
if [ "$SESSION_ID" = "unknown" ] || [ -z "$SESSION_ID" ]; then
  SESSION_ID="pid$$-$(date +%N 2>/dev/null | cut -c1-6 || echo "fallback")"
fi

# === Git 状态 ===
BRANCH=$(git rev-parse --show-current 2>/dev/null || echo "no-git")
BRANCH_SAFE=$(printf '%s' "$BRANCH" | tr -cd 'a-zA-Z0-9._-' | head -c 40)
BRANCH_SAFE="${BRANCH_SAFE:-no-branch}"
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJECT_NAME=$(basename "$PROJECT_ROOT" 2>/dev/null || echo "unknown")

GIT_STATUS=$(git status --short 2>/dev/null | head -20 || true)
DIFF_STAT=$(git diff --stat 2>/dev/null | head -10 || true)
STAGED_STAT=$(git diff --cached --stat 2>/dev/null | head -10 || true)
RECENT_LOG=$(git log --oneline -5 2>/dev/null || echo "  (no commits)")
[ -z "$GIT_STATUS" ] && GIT_STATUS="  (clean)"

# 最近编辑文件
RECENT_FILES=$(find "$PROJECT_ROOT" -type f \( -name "*.md" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.swift" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.rs" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/venv/*" -not -path "*/__pycache__/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.relay-cards/*" -not -path "*/relay-cards/*" \
  -mmin -120 2>/dev/null | head -10 || true)

# === 解析 stdin ===
STDIN_DATA=""
if [ ! -t 0 ]; then
  STDIN_DATA=$(cat)
fi

MODE="${1:-stdin}"
TITLE=""
DONE_ITEMS=""
TODO_ITEMS=""
DECISIONS=""
PITS=""

# === 关键词提取 (中英 n-gram + 停用词) ===
extract_keywords() {
  local corpus="$1"
  KEYWORDS_CORPUS="$corpus" python3 -c "
import os, re, sys

corpus_hint = os.environ.get('KEYWORDS_CORPUS', '') or ''

ZH_STOP = set('的 一 是 在 了 和 与 及 或 但 而 也 都 这 那 你 我 他 她 它 我们 你们 他们 自己 一个 一些 什么 怎么 哪 哪里 那些 这些 然后 现在 之前 之后 可以 应该 需要 必须 可能 没有 已经 正在 真的 还是 比如 例如 如果 因为 所以 但是 不过 然而 因此 于是'.split())
EN_STOP = set('the a an is are was were be been being have has had do does did will would should could may might can this that these those i you he she it we they my your his her our their me him them what which who where when why how and or but if then so because of in on at to for with from by as about into through during before after above below up down out off over under again further than once here there all any both each few more most other some such no nor not only own same than too very just don now will'.split())

text = ''
if corpus_hint.startswith('@transcript:'):
    tp = corpus_hint[len('@transcript:'):]
    try:
        with open(tp, 'r', errors='ignore') as f:
            lines = []
            for line in f:
                line = line.strip()
                if not line: continue
                try:
                    msg = json.loads(line)
                    if msg.get('type') == 'assistant':
                        content = msg.get('message', {}).get('content', [])
                        if isinstance(content, list):
                            for c in content:
                                if c.get('type') == 'text':
                                    lines.append(c.get('text',''))
                        elif isinstance(content, str):
                            lines.append(content)
                except: pass
        text = '\n'.join(lines[-10:])
    except Exception:
        text = ''
else:
    text = corpus_hint

if not text or len(text.strip()) < 3:
    print('_(自动提取失败)_')
    sys.exit(0)

tokens = {}
en_pat = re.compile(r'[A-Za-z][A-Za-z0-9_\-\.]{1,}')
for m in en_pat.finditer(text):
    w = m.group(0).lower()
    if w in EN_STOP or len(w) < 2 or w.isdigit(): continue
    tokens[w] = tokens.get(w, 0) + 1

zh_segs = re.findall(r'[一-鿿]+', text)
for seg in zh_segs:
    for i in range(len(seg) - 1):
        w = seg[i:i+2]
        if w in ZH_STOP: continue
        tokens[w] = tokens.get(w, 0) + 1
    for i in range(len(seg) - 2):
        w = seg[i:i+3]
        if w in ZH_STOP: continue
        tokens[w] = tokens.get(w, 0) + 1

if not tokens:
    print('_(自动提取失败)_')
    sys.exit(0)

top = sorted(tokens.items(), key=lambda kv: (-kv[1], -len(kv[0])))[:8]
print(', '.join(w for w, _ in top))
" 2>/dev/null || echo "_(自动提取失败)_"
}

if [ "$MODE" = "--auto" ] || [ -z "$STDIN_DATA" ]; then
  # 自动模式
  TITLE="auto-snapshot"
  DONE_ITEMS="- (自动模式: 未指定, 详见 git 状态)"
  TODO_ITEMS="- (自动模式: 请在新 session 开头回顾后填写)"
  DECISIONS="- (无记录)"
  PITS="- (无记录)"

  KEYWORDS_CORPUS=""
  TP="${TRANSCRIPT_PATH:-${CLAUDE_TRANSCRIPT_PATH:-}}"
  if [ -n "$TP" ] && [ -f "$TP" ]; then
    KEYWORDS_CORPUS="@transcript:$TP"
  else
    KEYWORDS_CORPUS="$PROJECT_NAME $BRANCH"
  fi
else
  # stdin 模式
  TITLE=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  print(d.get('title', 'manual-card')[:60])
except Exception:
  print('parse-error')
" 2>/dev/null || echo "parse-error")
  TITLE_SAFE=$(printf '%s' "$TITLE" | tr -cd 'a-zA-Z0-9._-' | head -c 30)
  TITLE_SAFE="${TITLE_SAFE:-manual}"

  # === Lint: TITLE 不可含混淆词 (避免关键词匹配误判) ===
  if printf '%s' "$TITLE" | grep -qE '也聊了|顺便|顺带|也看了|还看了|顺带也|也提了|主要.*也'; then
    echo "❌ relay-card-write.sh: TITLE 含混淆词 (也/顺便/顺带/还看了/也提了)" >&2
    echo "   TITLE: $TITLE" >&2
    echo "   建议: rewrite 时只写主任务, 不写'也聊了 X'/'顺带 X'/'顺便 X'" >&2
    exit 2
  fi

  DONE_ITEMS=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  items = d.get('done', [])
  print('\n'.join(f'- [x] {x}' for x in items) if items else '- (无)')
except Exception:
  print('- (解析失败)')
" 2>/dev/null || echo "- (解析失败)")

  TODO_ITEMS=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  items = d.get('todo', [])
  if items:
    for i, x in enumerate(items):
      p = d.get('priority', [])
      priority = p[i] if i < len(p) else 'P1'
      print(f'- [ ] **{priority}**: {x}')
  else:
    print('- (无)')
except Exception:
  print('- (解析失败)')
" 2>/dev/null || echo "- (解析失败)")

  DECISIONS=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  items = d.get('decisions', [])
  print('\n'.join(f'- {x}' for x in items) if items else '- (无记录)')
except Exception:
  print('- (解析失败)')
" 2>/dev/null || echo "- (解析失败)")

  PITS=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  items = d.get('pits', [])
  print('\n'.join(f'- {x}' for x in items) if items else '- (无记录)')
except Exception:
  print('- (解析失败)')
" 2>/dev/null || echo "- (解析失败)")

  # 关键词语料: title 加权 3x (用户口语化主任务词排第一)
  KEYWORDS_CORPUS=$(printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  parts = [d.get('title','')] * 3
  parts.append(d.get('goal',''))
  for k in ('done','todo','decisions','pits'):
    v = d.get(k, [])
    if isinstance(v, list): parts.extend(str(x) for x in v)
  print(' '.join(p for p in parts if p))
except Exception:
  print('')
" 2>/dev/null || echo "")
fi

KEYWORDS=$(extract_keywords "$KEYWORDS_CORPUS")
[ -z "$KEYWORDS" ] && KEYWORDS="_(自动提取失败)_"

# 拼接文件名前缀
if [ "$MODE" = "--auto" ] || [ -z "$STDIN_DATA" ]; then
  PREFIX="auto"
else
  PREFIX="${TITLE_SAFE:-manual}"
fi

CARD_FILE="$RELAY_DIR/${TIMESTAMP}-${SESSION_ID}-${PREFIX}-${BRANCH_SAFE}.md"

# === 写卡片 ===
cat > "$CARD_FILE" <<EOF
# 🏃 接力任务卡 / Relay Task Card

> ⏰ **写入方式**: $([ "$MODE" = "--auto" ] && echo "自动快照" || echo "主动调用")
> 📅 **生成时间**: $ISO_TIME
> 🌿 **当前分支**: \`$BRANCH\`
> 📁 **项目根**: \`$PROJECT_ROOT\`
> 🏷️ **关键词**: $KEYWORDS

---

## 🎯 当前任务

$([ -n "$STDIN_DATA" ] && [ "$MODE" != "--auto" ] && printf '%s' "$STDIN_DATA" | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  print(d.get('goal', '_(未填)_'))
except Exception:
  print('_(未填)_')
" 2>/dev/null || echo "_自动模式, 需新 session 开头回顾_")

---

## ✅ 已完成

$DONE_ITEMS

---

## 🔄 进行中 / 待办

$TODO_ITEMS

---

## 💡 关键决策

$DECISIONS

---

## 🚧 遇到的坑

$PITS

---

## 📂 工作区状态

### 未提交修改
\`\`\`
$GIT_STATUS
\`\`\`

### Diff 摘要
\`\`\`
$([ -n "$DIFF_STAT" ] && echo "$DIFF_STAT" || echo "(无 diff)")
\`\`\`

### 最近 5 次提交
\`\`\`
$RECENT_LOG
\`\`\`

$([ -n "$RECENT_FILES" ] && cat <<FILES

### 最近 2 小时编辑过的文件
$RECENT_FILES
FILES
)

---

## 🏷️ 关键词 (供自动匹配用)

\`$KEYWORDS\`

---

## 🚀 接力指南

**最快入口** —— 对新 session 说:
> "读取 \`$CARD_FILE\` 继续之前的工作"
> "读取 \`~/.relay-cards/latest.md\` 继续"

---

_本卡片由 Relay Card 自动生成 (v0.6)_
_历史卡片: \`$RELAY_DIR/\`_
EOF

# === 刷新 latest.md 索引 ===
INDEXER="$SCRIPT_DIR/relay-card-index.sh"
if [ -x "$INDEXER" ]; then
  bash "$INDEXER" 5 2>/dev/null || true
fi

# === 敏感信息脱敏 ===
SANITIZER="$SCRIPT_DIR/relay-card-sanitize.sh"
if [ -x "$SANITIZER" ]; then
  TMP_CLEAN="${CARD_FILE}.clean.$$"
  if bash "$SANITIZER" < "$CARD_FILE" > "$TMP_CLEAN" 2>/dev/null; then
    mv -f "$TMP_CLEAN" "$CARD_FILE"
  else
    rm -f "$TMP_CLEAN"
  fi
fi

# === 输出结果 ===
echo "════════════════════════════════════════"
echo "✅ 接力卡已生成"
echo "════════════════════════════════════════"
echo "📁 $CARD_FILE"
echo "🌿 $BRANCH ($PROJECT_NAME)"
echo "════════════════════════════════════════"