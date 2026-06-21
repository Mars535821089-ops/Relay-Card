# Relay Card 接力卡框架

> **为 AI 长任务而生的上下文接力机制**。在上下文耗尽前自动存档，新 session 一键续上。

[English](README.md) | 简体中文

## 什么是接力卡？

当 AI 编程助手（Claude Code、Cursor、Aider、Cline 等）的对话上下文即将耗尽或被压缩（compact）时，**当前任务、已完成、待办、关键决策、踩过的坑** 这些信息会全部丢失——下一个 session 必须从头开始。

**接力卡**就是在这一刻自动生成的一张「可交接任务清单」，把刚才的进度和上下文抽出来写到磁盘，新 session 开头只要读这张卡，就能无缝衔接。

## 它解决什么问题？

| 痛点 | 接力卡方案 |
|------|----------|
| 跑了一小时长任务，compact 后 Claude 完全忘了刚才聊到哪 | 自动从对话历史抽 done / todo / decisions |
| 多 terminal 并行时不知道哪张卡对应哪个工作区 | 每张卡带 `项目 + 分支 + 关键词`，歧义时让用户选 |
| 写卡时不小心把 API key 抄进去了 | 内置脱敏器，写卡前自动擦除 |
| relay-cards 目录无限膨胀 | 三级归档：活跃 / 月归档 / 压缩，磁盘可控 |
| 重要决策、坑容易在下一个 session 重蹈覆辙 | 卡里专门有「关键决策」和「踩过的坑」两段 |
| 不同 AI 工具（CC/Cursor/Aider）都得自己写一套 | 框架与工具解耦，CC 是首个 adapter |

## 🚀 5 分钟上手（Claude Code）

```bash
# 1. 克隆
git clone https://github.com/Mars535821089-ops/Relay-Card.git
cd relay-card

# 2. 安装
bash scripts/install.sh

# 3. 验证（生成一张测试卡）
bash ~/.claude/hooks/relay-card-write.sh --auto

# 4. 强制跑一次 PreCompact 试试
#    在 Claude Code 里输入 /compact 看效果
```

完成后 CC 会自动在以下场景生成接力卡：

- 上下文快满 / `/compact` 触发 **PreCompact** hook
- 任意时刻 Claude 主动调 `relay-card-write.sh`
- 手动跑 `bash relay-card-archive.sh` 归档

新 session 启动时（**SessionStart** hook）会通过 system message 提示「接力卡 #1 存在（opt-in）」——但**不会强制读取**，遵循 OPT-IN 原则：

- 你说「继续 XXX」→ Claude 用关键词匹配找对应卡读
- 你敲 `/relay-restore` → Claude 强制读最新卡
- 你说「不需要继续」→ Claude 忽略接力卡

## 🛠️ 进阶用法

### 1. 主动写卡（推荐关键节点调）

```bash
cat <<'EOF' | bash ~/.claude/hooks/relay-card-write.sh
{
  "title": "实现用户登录",
  "goal": "用 FastAPI + JWT 实现用户注册/登录",
  "done": ["设计完 schema", "写完密码哈希工具", "调通 /register"],
  "todo": ["实现 /login", "加 token 刷新", "写测试"],
  "decisions": ["选 bcrypt 不用 argon2 (项目统一)", "JWT 24h 过期"],
  "pits": ["pyjwt 1.x vs 2.x 签名 padding 行为不同, 锁定 2.8+"]
}
EOF
```

### 2. 智能恢复（关键词越级）

接力卡目录里有 5+ 张卡时，SessionStart 的 system message 会列出候选。

你说「继续 pricing」→ Claude 自动 `grep -liEr 'pricing' ~/.claude/relay-cards/ --include='*.md'` 找匹配卡 → 读它。

### 3. 归档策略

```bash
# 演练
bash relay-card-archive.sh --dry-run

# 活跃区保留 10 张, 90 天以上的归档, 自动压缩
bash relay-card-archive.sh --keep 10 --max-age 90 --compress

# 钉住重要卡
touch ~/.claude/relay-cards/20260612-important-card.md.pin
```

### 4. 批量脱敏（清理老卡里的泄漏）

```bash
bash relay-card-sanitize-all.sh --dry-run   # 看哪些会改
bash relay-card-sanitize-all.sh            # 真改（带 .bak 备份）
```

### 5. 看统计

```bash
bash relay-card-stats.sh          # markdown 报告
bash relay-card-stats.sh --json   # 给脚本用
```

## 🏗️ 架构

```
┌────────────────────────────────────────────────────┐
│  AI 工具 Adapter 层 (Claude Code / Cursor / Aider) │  ← 工具特异
│    src/adapters/claude-code/                       │
└─────────────────┬──────────────────────────────────┘
                  │ 标准 JSON 事件
                  ▼
┌────────────────────────────────────────────────────┐
│  事件路由层                                        │
│    PreCompact  →  relay-card.sh   (自动存档)       │
│    SessionStart → relay-card-restore.sh (注入路径) │
│    主动写      →  relay-card-write.sh              │
└─────────────────┬──────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────┐
│  核心层 (工具无关)                                 │
│    write / index / archive / sanitize / stats /    │
│    errors / sanitize.py (Python 内核)              │
│    src/lib/                                        │
└─────────────────┬──────────────────────────────────┘
                  │
                  ▼
┌────────────────────────────────────────────────────┐
│  持久层                                            │
│    ~/.relay-cards/                                 │
│      ├─ YYYYMMDD-HHMMSS-sid-prefix-branch.md      │
│      ├─ latest.md (索引)                          │
│      └─ archive/YYYY-MM/  (月归档)                │
└────────────────────────────────────────────────────┘
```

## 🧪 开发

```bash
# 本地跑测试
make test

# lint (shellcheck + shfmt)
make lint

# 安装为 Claude Code hooks
make install

# 清理
make clean
```

CI 在每次 push 跑：
- shellcheck 静态检查
- bats 单元测试
- 安装到临时目录 + 跑通端到端

## 🌍 多 AI 工具支持

| 工具 | Adapter 状态 |
|------|------------|
| Claude Code | ✅ 完整实现 |
| Cursor | 🚧 计划中（PR 欢迎） |
| Aider | 🚧 计划中 |
| Cline / Continue.dev | 📝 通过 generic adapter 兼容 |

写新 adapter 只需 50 行：监听工具事件 → 转成标准 JSON → 喂给 `relay-card-write.sh` 的 stdin。详见 [docs/adapters.md](docs/adapters.md)。

## 🌟 它是怎么演化出来的

> 2026-06-14 v1：手写模板，git status 5 行——空卡
> 2026-06-15 v2：自动抽 transcript，加上 done/todo/decisions
> 2026-06-15 v3：扩触发词，加 quality 评分
> 2026-06-15 v4：把所有字段塞 system context，1.6KB → 5KB 转义，1M 模型慢响应
> 2026-06-15 v5：v4-minimal 200 字节，只输出 #1 路径 + 触发词提示
> 2026-06-16 v6：关键词提取、goal 段 lint 防混淆、self-refine 强化

更多踩坑见 [docs/why-relay-card.md](docs/why-relay-card.md) 和 [docs/pitfalls.md](docs/pitfalls.md)。

## 🤝 贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。提 PR 前请先跑 `make test` 全绿。

## 📜 许可

[MIT License](LICENSE) © 2026 Relay Card Contributors
