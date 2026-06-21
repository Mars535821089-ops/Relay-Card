# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-06-21

### Added
- Initial open-source release
- 三层架构: AI 工具 Adapter (Claude Code) / 工具无关 Core / Storage
- 接力卡写卡 (`relay-card-write.sh`): JSON stdin / `--auto` 机械快照 / 关键词自动提取
- 接力卡恢复 (`relay-card-restore.sh`): OPT-IN 原则, SessionStart 200 字节 JSON 注入
- 接力卡归档 (`relay-card-archive.sh`): 活跃 → 月归档 → gzip 压缩三级管理
- 接力卡索引 (`relay-card-index.sh`): 重建 latest.md
- 敏感信息脱敏 (`relay_card_sanitize.py`): API key / email / JWT / AWS / 私钥 9 类规则, 幂等保护
- 批量脱敏 (`relay-card-sanitize-all.sh`): 一次性给历史卡片补脱敏
- 统计报表 (`relay-card-stats.sh`): markdown / JSON 双格式
- 错误日志 (`relay-card-errors.sh`): 统一 trap + JSONL + 1000 行自动 rotate
- 中英双语 README (英文 + 简体中文)
- 一键安装/卸载 (`scripts/install.sh` / `uninstall.sh`)
- GitHub Actions CI: shellcheck + shfmt + bats + multi-platform matrix
- 完整测试覆盖: 5 个 bats 单元测试 + 1 个端到端集成测试
- 设计文档: architecture / adapters / usage / CHANGELOG / SECURITY / CONTRIBUTING
- PATH 命令: `relay-save` / `relay-restore` / `relay-list` / `relay-archive` / `relay-sanitize` / `relay-stats`

### Security
- 全面脱敏: 移除所有个人路径 / API key / 模型配置, 默认路径工具无关
- 内置脱敏器: API key (sk-* / sk-ant-* / ghp_* / xoxb-* / AIza*) + Bearer tokens + AWS keys + GitHub tokens + Slack tokens + ENV-style secrets + 私钥块 + 邮箱 + JWT
- idempotent 设计: 已经是 `[REDACTED:xxx]` 的块不会被重复处理

## [Unreleased] - History (供演进参考)

下述版本是私有部署历史, 不在公开发布版本中。

- **v0.6**: 加关键词提取 + goal 段 lint 防混淆词 + self-refine 强化
- **v0.5**: v4-minimal, 把 1.6KB 中文转义成 5KB 触发 1M 模型慢响应问题修复为 200 字节 OPT-IN 注入
- **v0.4**: 完整 JSON 塞 system context (因响应问题被 v0.5 替代)
- **v0.3**: 扩触发词 + 质量评分
- **v0.2**: 自动从 transcript 抽对话内容
- **v0.1**: 初版, 手写模板 + git status 5 行