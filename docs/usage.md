# 使用文档

> 完整的使用场景 + 命令清单。

## 安装

参见 [README.md#快速开始](../README.md#快速开始) 或 `scripts/install.sh`。

## 命令总览

### `relay-save` — 主动存档

```bash
# 主动写卡（推荐关键节点调）
cat <<'EOF' | relay-save
{
  "title": "实现用户登录",
  "goal": "用 FastAPI + JWT 实现用户注册/登录",
  "done": ["设计 schema", "写密码哈希工具"],
  "todo": ["实现 /login", "加 token 刷新", "写测试"],
  "decisions": ["选 bcrypt 不用 argon2"],
  "pits": ["pyjwt 1.x vs 2.x 签名 padding 不同"]
}
EOF

# 机械快照（无需 stdin）
relay-save --auto
```

### `relay-list` — 列卡片

```bash
relay-list              # 显示最近 5 张
relay-list 10           # 显示最近 10 张

# 直接读
cat ~/.relay-cards/latest.md
```

### `relay-restore` — 恢复上下文

在新 session 说「继续 XXX」或敲 `/relay-restore`（Claude Code 用户）。

内部流程：
1. SessionStart hook 注入接力卡 #1 路径（200 字节）
2. 用户说「继续 XXX」→ Claude grep 关键词找匹配卡
3. Claude Read 卡片 → 接力成功

### `relay-archive` — 归档

```bash
relay-archive --dry-run            # 演练
relay-archive --keep 10            # 活跃区保留 10 张
relay-archive --max-age 90         # 90 天以上的归档
relay-archive --compress           # 旧归档再 gzip

# 钉住重要卡（永不归档）
touch ~/.relay-cards/20260612-important.md.pin
```

### `relay-sanitize` — 脱敏

```bash
# 流式
cat file.md | relay-sanitize > clean.md

# 原地（带备份）
relay-sanitize file.md

# 自检
relay-sanitize --test
```

### `relay-stats` — 统计

```bash
relay-stats                # markdown 输出
relay-stats --json         # JSON 输出
```

## 配置文件

`~/.claude/settings.json` 里 hooks 段（在 CC 用户那里）：

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
    "SessionStart": [
      {
        "hooks": [{
          "type": "command",
          "command": "bash \"$HOME/.claude/hooks/relay-card-restore.sh\"",
          "timeout": 5
        }]
      },
      {
        "hooks": [{
          "type": "command",
          "command": "bash \"$HOME/.claude/hooks/relay-card-archive.sh\" >/dev/null 2>&1 &"
        }]
      }
    ]
  }
}
```

## 高级用法

### 1. 多 terminal 并行

每个 terminal 独立 session，写卡时文件名带 session_id：

```
20260621-150000-a1b2c3d4-feat-login.md     # terminal 1
20260621-150012-a1b2c3d5-fix-pricing.md    # terminal 2
```

`latest.md` 列出最近 5 张，歧义时 Claude 用关键词匹配挑卡。

### 2. 项目级接力卡（git hook 集成）

```bash
# .git/hooks/post-commit
#!/bin/bash
bash ~/.claude/hooks/relay-card-write.sh --auto
```

每次 commit 自动存档当前 git 状态。

### 3. 接力卡同步到项目仓库

```bash
# 把接力卡当作项目历史的一部分
cd your-project
echo ".relay-cards/" >> .gitignore    # 或保留！
git add .relay-cards/latest.md
git commit -m "chore: 接力卡存档"
```

### 4. CI 集成：失败时自动存档

```yaml
# .github/workflows/relay-card.yml
- name: Save relay card on failure
  if: failure()
  run: bash ~/.claude/hooks/relay-card-write.sh --auto
```

### 5. 定时强制存档

```bash
# crontab -e
*/30 * * * * cd ~/projects/foo && bash ~/.claude/hooks/relay-card-write.sh --auto
```

## 故障排除

### Q: 接力卡是空的？

A: 三种可能：

1. **没有 git repo** — 在项目根跑 `git init`
2. **transcript_path 不存在** — 检查 Claude Code 版本是否支持
3. **质量评分 < 3** — PreCompact 会提示「中/低质」，让 Claude 调 `relay-card-write.sh` 写补丁卡

### Q: 装完不生效？

A: 检查顺序：

```bash
# 1. 文件是否装上了？
ls -la ~/.claude/hooks/relay-card*.sh

# 2. settings.json 里有 hooks 吗？
grep -A2 PreCompact ~/.claude/settings.json

# 3. PATH 有 relay-save 吗？
which relay-save

# 4. 手动跑一次？
bash ~/.claude/hooks/relay-card-write.sh --auto
```

### Q: 卡片太多怎么办？

```bash
# 演练
bash relay-card-archive.sh --dry-run

# 真归档
bash relay-card-archive.sh --keep 5 --max-age 30 --compress
```

### Q: 卸载怎么卸？

```bash
bash scripts/uninstall.sh
# 加 --purge 同时清空历史卡片
```

## 设计哲学

### OPT-IN 原则

接力卡存在 ≠ 应该读接力卡。

- **不强制** — 接力卡不会被自动 Read，避免浪费 token
- **可触发** — 用户说「继续 XXX」才 Read
- **可忽略** — 用户说「不需要继续」就跳过

### Self-Refine 强化

PreCompact 自动存档的质量分三档：

| 分数 | 等级 | 行为 |
|------|------|------|
| ≥ 6 | 🟢 高 | 可跳过补丁卡 |
| 3-5 | 🟡 中 | 必做补丁卡 |
| < 3 | 🔴 低 | 强制补丁卡 |

「补丁卡」是 Claude 主动调 `relay-card-write.sh` 写一张更准的卡，覆盖自动抽的卡。