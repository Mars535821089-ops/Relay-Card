# 贡献指南

感谢你考虑为 Relay Card 做贡献！

## 开发环境

- macOS / Linux (WSL 也行)
- Bash 4.0+（macOS 自带 3.2，新功能靠 bash 4+ 兼容写法）
- Python 3.8+（仅 sanitize.py 需要）
- `make` / `shellcheck` / `shfmt` / `bats`（CI 会装）

## 快速开始

```bash
git clone https://github.com/yourname/relay-card.git
cd relay-card
make install   # 装到 ~/.relay-card/ 软链
make test      # 跑单元测试
make lint      # 跑 shellcheck
```

## 提 PR 流程

1. Fork → 改代码 → 跑 `make test && make lint` 全绿
2. 在 `CHANGELOG.md` 加一行（格式见现有条目）
3. PR 标题用 `feat:` / `fix:` / `docs:` / `test:` / `refactor:` 前缀
4. PR 描述里贴：动机、变更点、测试证据（`make test` 输出）、关联 issue

## 代码规范

- Shell 脚本走 shellcheck 严格模式
- 用 `set -euo pipefail`（bash 4+ 才有的 `pipefail` 兼容写法）
- 函数命名小写 + 下划线
- 路径用变量，不用写死 `/Users/xxx`
- 引用环境变量用 `"${VAR:-default}"`

## 目录结构约定

```
src/
  lib/                  # 工具无关核心
  adapters/
    claude-code/        # Claude Code 特异
    generic/            # 通用 JSON 接口
bin/                    # 装到 PATH 的命令
scripts/                # 安装/卸载/CI 工具
tests/                  # bats 单元测试
docs/                   # 设计文档
```

## 跑测试

```bash
make test                # 全套
make test-unit           # 单元
make test-integration    # 端到端
```

## 写新 Adapter

参见 [docs/adapters.md](docs/adapters.md)。新 adapter 必须：

1. 只跟 AI 工具的事件层打交道（不写核心逻辑）
2. 把工具事件转成标准 JSON 喂给 `relay-card-write.sh` stdin
3. 不修改 `src/lib/` 下的任何文件
4. 配 `tests/adapters/{name}.bats` 测试

## 报告 Bug

[GitHub Issues](https://github.com/yourname/relay-card/issues) 提单时附：

- 你的 OS + Bash 版本（`bash --version`）
- Relay Card 版本（`bash relay-card.sh --version` 如果有）
- 复现命令
- 期望 vs 实际
- 错误日志：`bash relay-card-errors.sh tail 20`

## 安全问题

**不要**在 GitHub Issues 公开讨论安全问题。发邮件到 [security contact TBD]。
