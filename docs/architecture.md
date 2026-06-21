# 架构总览

> 完整开源项目（CI + 测试 + 多语言）+ 通用 AI 工具框架 + Claude Code 首个 adapter。

## 设计目标

1. **工具解耦** — Core 不知道 AI 工具存在，只接受标准 JSON / 文件
2. **数据本地** — 接力卡全部存用户家目录，不上传任何外部服务
3. **可扩展** — 新增 AI 工具只需 50 行 adapter
4. **可测试** — Core 全部用 bats 单元测试覆盖，不依赖 Claude Code runtime
5. **可降级** — Python 失败时所有脚本都有 bash 兜底

## 三层架构

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 1: AI 工具 Adapter (工具特异)                          │
│                                                              │
│  - Claude Code: 监听 PreCompact + SessionStart hooks         │
│  - 未来: Cursor / Aider / Cline                              │
│  - 职责: 把工具事件转成标准 JSON → 喂 Core                    │
│                                                              │
│  src/adapters/claude-code/                                   │
│    ├── relay-card.sh         # PreCompact 自动存档入口        │
│    ├── relay-card-restore.sh # SessionStart 注入路径         │
│    └── settings.hooks.json   # 注入到 ~/.claude/settings.json │
└──────────────────────────┬───────────────────────────────────┘
                           │ 标准 JSON
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  Layer 2: Core (工具无关, 可测试)                            │
│                                                              │
│  - 写卡: 解析 stdin JSON → 生成 markdown                     │
│  - 索引: 扫描活跃区 → 生成 latest.md                         │
│  - 归档: 三级管理 (活跃/月归档/压缩)                         │
│  - 脱敏: 写前过滤敏感信息                                    │
│  - 统计: 用 Python 聚合 .restore.log + 卡片元数据            │
│  - 错误: 统一 trap → JSONL 日志                              │
│                                                              │
│  src/lib/                                                    │
│    ├── relay-card-write.sh      # 主动写卡                   │
│    ├── relay-card-index.sh      # 索引生成                   │
│    ├── relay-card-archive.sh    # 归档                       │
│    ├── relay-card-sanitize.sh   # 脱敏 (bash wrapper)        │
│    ├── relay-card-sanitize-all.sh # 批量脱敏                 │
│    ├── relay-card-stats.sh      # 统计                       │
│    ├── relay-card-errors.sh     # 错误日志 (source+CLI)      │
│    └── relay_card_sanitize.py   # 脱敏 Python 内核           │
└──────────────────────────┬───────────────────────────────────┘
                           │ 文件 I/O
                           ▼
┌──────────────────────────────────────────────────────────────┐
│  Layer 3: Storage                                            │
│                                                              │
│  ~/.relay-cards/                                             │
│    ├── YYYYMMDD-HHMMSS-{sid}-{prefix}-{branch}.md  # 单卡   │
│    ├── latest.md                              # 索引 (软链→md)│
│    ├── archive/YYYY-MM/                       # 月归档       │
│    │   └── _compressed/*.gz                    # 压缩归档     │
│    ├── .errors.log        # 错误日志 JSONL                   │
│    ├── .restore.log       # 恢复触发日志 (可选)             │
│    ├── .archive-stamp     # 上次归档时间                     │
│    └── *.pin              # 钉住保护                         │
└──────────────────────────────────────────────────────────────┘
```

## 关键设计决策

### 1. 为什么 Core 与 Adapter 解耦？

**问题**：Claude Code 迟早会改 hooks API，Cursor / Aider 工具的 compact 机制完全不同。

**方案**：Core 只接受文件 I/O + 标准 JSON，不依赖任何 AI 工具 SDK。

**好处**：
- Core 可独立单元测试（不依赖 Claude Code runtime）
- 新 AI 工具只需写一个 adapter，不需要改 Core
- 长期维护成本降低

### 2. 为什么接力卡是 Markdown？

**问题**：JSON / SQLite / TOML / YAML 都比 Markdown「结构化」，为什么用 Markdown？

**答案**：
- **人可读** — 用户能直接在终端 `cat` 看接力卡内容
- **AI 友好** — Claude/GPT 都能直接 Read Markdown
- **diff 友好** — `git diff` 看接力卡变更非常直观
- **无须工具** — 不需要 JSON parser 就能编辑
- **Git 可追踪** — 可以 `git add` 接力卡进项目仓库（如果用户愿意）

代价是结构化查询变难（要 awk/grep），但 Core 的 Python 工具能搞定。

### 3. 为什么用 n-gram 关键词而不是 LLM 抽？

**问题**：SessionStart 时可以调 LLM 抽「当前任务」关键词，但会：

- 每次启动多花 5-10 秒
- 多花 $0.01-0.05 / 启动
- 大模型厂商 down 机时整个机制失效

**方案**：用 Python 中英 n-gram + 停用词，5 行代码，0 延迟，0 成本。

**效果**：从实战经验看，n-gram 命中 80%+ 场景（多 terminal 时靠它挑对卡）。

### 4. 为什么 v4-minimal 是 200 字节不是完整 JSON？

**问题**：v4 把接力卡完整内容塞 `additionalContext`，1.6KB 中文被转义成 5KB `\uXXXX`，1M 模型慢响应/500。

**方案**：v4-minimal 只输出：
- 接力卡 #1 路径（30 字节）
- "接力卡存在 (opt-in, 默认不读)" system message（50 字节）
- 触发 Read 的关键词提示（120 字节）

**好处**：
- SessionStart 几乎零开销
- 用户不主动说「继续 XXX」，接力卡不会被读
- 触发时 Claude 自己用 grep + Read 挑卡，省下「我读了所有接力卡」的 token

### 5. 为什么自检用 `--test` 不写 unit test？

每个 Core 脚本都有 `--test` 自检模式（dry-run + 已知输入 → 已知输出）。

**好处**：
- 装完就能跑（无需 bats / pytest）
- 失败时一眼看出哪坏了
- 给新 adapter 提供模板

**代价**：覆盖率不如专业测试框架，所以同时配 bats 单元测试 + GitHub Actions CI 跑 shellcheck。

## 演进路线

```
v0.1   手写模板 + git status (空卡)
v0.2   自动从 transcript 抽
v0.3   扩触发词 + 质量评分
v0.4   完整 JSON 塞 context (失败案例: 5KB 中文触发 1M 模型慢响应)
v0.5   v4-minimal 200 字节 + OPT-IN 原则
v0.6   n-gram 关键词 + goal 段 lint + self-refine
v0.7   ← 我们在这里 通用框架 + Claude Code adapter
v0.8   (未来) Cursor adapter
v0.9   (未来) Aider adapter
v1.0   (未来) 多语言 UI + Web dashboard
```

## 性能特征

| 操作 | 耗时 | 磁盘 | 备注 |
|------|------|------|------|
| 写一张卡 | < 200ms | ~3-5KB | 含脱敏 |
| 索引 latest.md | < 100ms | ~1KB | 看活跃区 5 张 |
| 归档 100 张卡 | < 1s | 0 (移动) | pin 跳过 |
| 压缩归档 | ~50ms/张 | 0.3x | gzip 默认级别 |
| SessionStart 注入 | < 50ms | 0 | 仅输出 #1 路径 |
| PreCompact 自动存档 | < 500ms | ~5KB | 含 transcript 抽取 |
| stats 统计 | < 500ms | 0 | Python 聚合 |

## 与 AI 工具的事件映射

| AI 工具 | 写卡触发 | 恢复触发 | 主动存档 |
|---------|---------|---------|---------|
| Claude Code | PreCompact hook | SessionStart hook | /relay-save slash |
| Cursor | (未来) auto-save | (未来) on-load | (未来) Cmd-S |
| Aider | (未来) /save | (未来) /resume | (未来) /relay-save |
| Cline | (未来) compact | (未来) start | (未来) /save |

## 不做什么

明确划定边界，避免 scope creep：

- ❌ 不上传卡片到云服务（用户隐私）
- ❌ 不读项目源代码（除了 git 元数据）
- ❌ 不取代 AI 工具的内置 checkpoint 机制（互补）
- ❌ 不强制 OPT-OUT（用户说继续才读）
- ❌ 不读 `.env` / `~/.ssh` 等敏感路径
- ❌ 不做实时同步（接力卡是异步存档）