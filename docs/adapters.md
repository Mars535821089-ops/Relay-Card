# Adapter 编写指南

> 想让 Relay Card 支持新 AI 工具？读这一篇就够了。

## 什么是 Adapter？

Adapter 是 Relay Card 三层架构里的**工具特异层**。它只做一件事：

> **监听 AI 工具的事件 → 转成标准 JSON → 喂给 Relay Card Core**

## 工具无关的标准 JSON

不管 AI 工具是 CC / Cursor / Aider，都用同一个 JSON 格式：

```json
{
  "title": "卡片标题 (≤30 字符)",
  "goal": "当前任务的一句话描述",
  "done": ["已完成 1", "已完成 2"],
  "todo": ["待办 1", "待办 2"],
  "decisions": ["决策 1: 为什么", "决策 2: 为什么"],
  "pits": ["坑 1: 怎么避", "坑 2: 怎么避"],
  "priority": ["P0", "P1", "P2"]
}
```

喂给 `relay-card-write.sh` 的 stdin：

```bash
cat <<'EOF' | bash relay-card-write.sh
{
  "title": "...",
  "goal": "...",
  "done": [...],
  "todo": [...]
}
EOF
```

或机械快照：

```bash
bash relay-card-write.sh --auto
```

## 三类事件映射

每个 AI 工具至少要实现**两类事件**（可选第三类）：

### 1. 自动存档触发（Compact 事件）

AI 工具压缩上下文时调用 → Core 写接力卡。

| AI 工具 | 触发源 |
|---------|--------|
| Claude Code | PreCompact hook |
| Cursor | (未来) on-context-rotate |
| Aider | (未来) /save |

### 2. 会话启动注入（SessionStart 事件）

新 session 启动时调用 → Core 提示接力卡存在（**OPT-IN 原则**，不强制读）。

| AI 工具 | 触发源 |
|---------|--------|
| Claude Code | SessionStart hook |
| Cursor | (未来) on-load |
| Aider | (未来) /resume |

### 3. 主动存档（用户/AI 触发）

可选。AI 在关键时刻主动存档 → Core 写接力卡。

| AI 工具 | 触发源 |
|---------|--------|
| Claude Code | `/relay-save` slash + Claude 主动调 `relay-card-write.sh` |
| Cursor | (未来) Cmd-S 钩子 |
| Aider | (未来) /save 命令 |

## Claude Code Adapter 实现（参考）

`src/adapters/claude-code/` 已有完整实现，关键代码：

### PreCompact handler

```bash
#!/bin/bash
# 监听 CC PreCompact hook → 写接力卡
# stdin 是 hook payload (含 session_id + transcript_path)

set -e
HOOK_HOME="${HOOK_HOME:-$HOME/.claude/hooks}"
"$HOOK_HOME/relay-card.sh"  # 自动从 stdin 读 hook payload
```

### SessionStart handler

```bash
#!/bin/bash
# 监听 CC SessionStart hook → 注入接力卡 #1 路径 (OPT-IN)
set -e
HOOK_HOME="${HOOK_HOME:-$HOME/.claude/hooks}"
"$HOOK_HOME/relay-card-restore.sh"  # 输出 200 字节 JSON
```

### settings.json 注入

```json
{
  "hooks": {
    "PreCompact": [{
      "hooks": [{
        "type": "command",
        "command": "bash \"$HOME/.claude/hooks/relay-card.sh\"",
        "timeout": 15
      }]
    }],
    "SessionStart": [{
      "hooks": [
        {
          "type": "command",
          "command": "bash \"$HOME/.claude/hooks/relay-card-restore.sh\"",
          "timeout": 5
        }
      ]
    }]
  }
}
```

## 写你的 Cursor Adapter（示例骨架）

```python
# src/adapters/cursor/extension.py
import json
import subprocess
from pathlib import Path

RELAY_HOME = Path.home() / ".claude" / "hooks"
WRITE_SCRIPT = RELAY_HOME / "relay-card-write.sh"


def on_context_compact(transcript: str, current_branch: str, project_name: str):
    """Cursor 压缩上下文时调用"""
    payload = {
        "title": f"{project_name}-compact",
        "goal": extract_last_goal(transcript),
        "done": extract_done_signals(transcript),
        "todo": extract_todo_signals(transcript),
        "decisions": extract_decision_signals(transcript),
        "pits": [],
    }
    stdin = json.dumps(payload)
    subprocess.run(["bash", str(WRITE_SCRIPT)], input=stdin, text=True)


def on_session_start():
    """Cursor 启动新会话时调用"""
    subprocess.run(
        ["bash", str(RELAY_HOME / "relay-card-restore.sh")],
        check=True, capture_output=True
    )


def extract_last_goal(transcript: str) -> str:
    # TODO: 用你的工具特有方式抽 "current task"
    return "(待实现)"


def extract_done_signals(transcript: str) -> list[str]:
    # TODO: 从 transcript 抽 "completed" 信号
    return []


# 类似 extract_todo_signals / extract_decision_signals ...
```

## 测试你的 Adapter

1. **手动 smoke test**：

```bash
# 模拟事件
echo '{"session_id":"test","transcript_path":"/dev/null"}' | \
  bash src/adapters/claude-code/relay-card.sh
ls -la ~/.relay-cards/
```

2. **bats 集成测试**：

```bash
# tests/adapters/cursor.bats
@test "cursor adapter: on_context_compact writes a card" {
  run bash src/adapters/cursor/extension.sh --simulate
  [ "$status" -eq 0 ]
  [ -f "$RELAY_DIR"/*.md ]
}
```

3. **CI**：在 `.github/workflows/ci.yml` 的 matrix 里加 `cursor` job。

## 提交 Adapter 到 Relay Card

1. Fork → 在 `src/adapters/` 下新建你的工具目录
2. 写 README.md 说明怎么装/怎么测
3. 写 `tests/adapters/{name}.bats`
4. 在 `src/adapters/README.md` 表格里加一行
5. 提 PR，CI 全绿 + maintainer review 后合并

## 常见问题

**Q: 我的工具没有 compact 事件，怎么办？**
A: 用「文件 mtime 触发」或「周期轮询 (每 10 分钟)」代替。精度差但能用。

**Q: 我的工具没有 transcript_path，怎么抽对话内容？**
A: 跳过 transcript 抽取，强制用机械快照 (`--auto`)，用户在卡片里手填。

**Q: 我想让 AI 在关键时刻主动存档（不只是 compact），怎么做？**
A: 实现「触发词回调」—— 比如 `if "checkpoint" in last_user_msg` 就调 write。

**Q: 多用户协作时一张卡会被覆盖吗？**
A: 不会。文件名带 session_id + nanosecond，多人并发写不会撞名。

---

**准备好写你的 adapter 了吗？** 提 PR 之前先在 [GitHub Discussions](https://github.com/yourname/relay-card/discussions) 聊聊想法，避免重造轮子。