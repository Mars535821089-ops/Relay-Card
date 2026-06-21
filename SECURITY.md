# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.6.x   | ✅ Active          |
| 0.5.x   | ⚠️ Critical fixes only |
| < 0.5   | ❌ End of life     |

## Reporting a Vulnerability

**Do NOT open a GitHub issue for security vulnerabilities.**

Email: [security contact TBD]  →  48 小时内首次响应

请包含：

1. 漏洞描述 + 复现步骤
2. 影响范围（哪些版本/平台）
3. 你的建议修复方案（如果有）
4. 是否已公开披露

我们承诺：

- 48 小时内首次响应
- 90 天内修复 critical/high 漏洞
- 修复前不发安全公告，避免被恶意利用
- 修复后会在 CHANGELOG 致谢（除非你要求匿名）

## 已知安全设计

### 接力卡内容

接力卡是**纯文本 Markdown**，可能含代码片段、文件路径、错误堆栈。

**默认行为**：

- 写卡时自动过 `relay_card_sanitize.py` 脱敏（API key / email / JWT / AWS / 私钥）
- 旧卡用 `relay-card-sanitize-all.sh --dry-run` 补脱敏
- 写卡路径在用户家目录（`~/.relay-cards/`），权限 `600`

**不会做**：

- 不上传到任何外部服务
- 不读取项目源代码（除了 git 元数据）
- 不读 `.env` / `~/.ssh/` 等敏感路径

### 路径遍历保护

所有 `find` / `mv` / `cp` 操作都限定在 `~/.relay-cards/` 根目录，**不**递归进项目目录。

## 攻击面

| 组件 | 攻击面 | 缓解 |
|------|--------|------|
| `relay-card-write.sh` | stdin JSON 解析 | 走 Python json.loads，捕获异常 |
| `relay-card-sanitize.sh` | 恶意 markdown | 只读 + 写新文件，不原地改直到备份完成 |
| `relay-card-archive.sh` | 路径遍历 | 文件名限制 `[0-9]*.md` glob，pin 检查 |
| `relay-card-restore.sh` | 输出注入 | system message 走 JSON dump，特殊字符自动转义 |
| 归档压缩 | gzip 炸弹 | 单文件大小限制（待实现，#TODO） |

## 致谢

[贡献者列表将随项目成长添加]
