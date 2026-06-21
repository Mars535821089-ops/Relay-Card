# Relay Card — AI 上下文接力框架

> 在 AI 长任务上下文耗尽 / compact 之前，自动生成可交接的任务卡，让下一个 session 一键接力。

**Relay Card** 是一个跨 AI 工具的「上下文接力」机制：当你的 AI 编程助手（Claude Code、Cursor、Aider、Cline 等）的对话上下文即将耗尽或被压缩时，自动从对话历史、git 状态、未保存修改中提取出**当前任务、已完成、待办、关键决策、踩过的坑**，生成一张可读的接力卡；新 session 开头只要读这张卡，就能无缝衔接上下文。

## ✨ 核心特性

- 🏃 **自动触发** — 监听 AI 工具的 compact 事件，无需手动介入
- 🎯 **智能抽取** — 从对话历史中按中英文 n-gram + 关键词匹配，自动识别目标 / 进度 / 决策
- 🔒 **敏感信息脱敏** — 内置脱敏器，写卡前自动擦除 API key、邮箱、JWT、私钥、AWS 凭据等
- 📦 **自动归档** — 活跃区 / 归档区 / 压缩区三级管理，磁盘不爆
- 🛡️ **钉住保护** — `.pin` 文件防止重要卡被自动归档
- 🔌 **工具无关** — 首个实现支持 Claude Code，框架可扩展到其他 AI 工具
- 🌏 **多语言友好** — 关键词提取同时支持中文 n-gram 和英文 word boundary

## 🚀 快速开始

### Claude Code 用户

```bash
# 一键安装
curl -fsSL https://raw.githubusercontent.com/Mars535821089-ops/Relay-Card/main/scripts/install.sh | bash

# 验证安装
bash ~/.claude/hooks/relay-card.sh --test   # 跑一次自检
```

安装后会自动配置 Claude Code 的 `PreCompact` 和 `SessionStart` hooks，无需改任何设置。

### 其它 AI 工具

参见 [docs/adapters.md](docs/adapters.md) 编写自己的 adapter，框架提供与工具无关的核心 API。

## 📖 使用方法

| 场景 | 操作 |
|------|------|
| AI 主动写卡 | `cat payload.json \| bash ~/.claude/hooks/relay-card-write.sh` |
| 机械快照 | `bash ~/.claude/hooks/relay-card-write.sh --auto` |
| 列出最近卡 | `cat ~/.claude/relay-cards/latest.md` |
| 恢复上下文 | 用户在新 session 说「继续 XXX」或敲 `/relay-restore` |
| 归档旧卡 | `bash ~/.claude/hooks/relay-card-archive.sh` |
| 看使用统计 | `bash ~/.claude/hooks/relay-card-stats.sh` |
| 批量脱敏 | `bash ~/.claude/hooks/relay-card-sanitize-all.sh --dry-run` |

详见 [docs/usage.md](docs/usage.md)。

## 🏗️ 架构

```
┌─────────────────────────────────────────────┐
│  AI Tool Adapter (Claude Code / Cursor /)   │  ← 工具特异
├─────────────────────────────────────────────┤
│  Hook Handlers (PreCompact / SessionStart)  │  ← 事件层
├─────────────────────────────────────────────┤
│  Core: write / restore / archive / sanitize │  ← 工具无关
├─────────────────────────────────────────────┤
│  Storage: ~/.relay-cards/ (markdown + meta) │  ← 持久层
└─────────────────────────────────────────────┘
```

每个 AI 工具只需要写一个 adapter，把工具事件转成标准 JSON 喂给 Core。

## 🧰 CLI 速查

```bash
# 写卡
bash relay-card-write.sh --auto                                    # 自动快照
cat '{"goal":"...","done":[...]}' | bash relay-card-write.sh       # 主动写

# 索引
bash relay-card-index.sh 5                                         # 重生成 latest.md

# 归档
bash relay-card-archive.sh --dry-run                               # 演练
bash relay-card-archive.sh --keep 20 --max-age 60                 # 真归档
bash relay-card-archive.sh --compress                             # 压缩老卡

# 脱敏
cat file.md | bash relay-card-sanitize.sh                         # 流式
bash relay-card-sanitize.sh file.md                               # 原地
bash relay-card-sanitize.sh --test                                # 自检
bash relay-card-sanitize-all.sh                                   # 批量

# 错误日志
bash relay-card-errors.sh tail 20
bash relay-card-errors.sh stats

# 统计
bash relay-card-stats.sh                                          # markdown
bash relay-card-stats.sh --json                                   # JSON
```

## 🌟 故事：为什么需要它

> 2026-06-14：我第一次跑长任务到 80% 上下文时，CC 自动 compact，结果**关键决策、坑、待办全没了**——下一轮 Claude 完全不知道刚才聊到哪。
>
> 接下来一周我手工写接力卡：v1 是空的，v2 加了 git 状态，v3 加了关键词，v4 把 1.6KB 中文转义成 5KB `\uXXXX` 塞进 system context，触发 1M 模型慢响应/500；v5 改 minimal 200 字节，v6 加 n-gram + lint。
>
> **8 天从 v1 到 v6，本质就一个需求：别让我重头来过。**
>
> 这就是 Relay Card 存在的意义。

更多故事见 [docs/why-relay-card.md](docs/why-relay-card.md)。

## 🌍 多语言

- [English](README.md)（本文档）
- [简体中文](docs/README.zh-CN.md)

## 🤝 贡献

欢迎 PR！参见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 📜 许可

[MIT License](LICENSE) © 2026 Relay Card Contributors
