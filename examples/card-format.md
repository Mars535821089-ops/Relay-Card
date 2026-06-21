# 示例接力卡

这是 Relay Card 生成的标准卡片格式示例。

## 文件命名

```
YYYYMMDD-HHMMSS-{session_id}-{prefix}-{branch}.md
```

例：

```
20260621-150000-a1b2c3d4-user-auth-feat-login.md
```

## 标准卡片结构

```markdown
# 🏃 接力任务卡 / Relay Task Card

> ⏰ **写入方式**: 主动调用
> 📅 **生成时间**: 2026-06-21 15:00:00 +0800
> 🌿 **当前分支**: `feat-login`
> 📁 **项目根**: `/Users/.../my-project`
> 🏷️ **关键词**: 用户, 登录, 认证, bcrypt, jwt

---

## 🎯 当前任务

实现用户登录功能（FastAPI + JWT）

---

## ✅ 已完成

- [x] 设计 schema
- [x] 写密码哈希工具
- [x] 调通 /register

---

## 🔄 进行中 / 待办

- [ ] **P0**: 实现 /login endpoint
- [ ] **P1**: 加 token 刷新
- [ ] **P2**: 写测试

---

## 💡 关键决策

- 选 bcrypt 不用 argon2 (项目统一)
- JWT 24h 过期

---

## 🚧 遇到的坑

- pyjwt 2.x 与 1.x 签名 padding 行为不同, 锁定 2.8+

---

## 📂 工作区状态

### 未提交修改
```

 M src/auth/login.py
 M tests/test_auth.py

```

### Diff 摘要
```

 src/auth/login.py     | 12 ++++++------
 tests/test_auth.py    |  4 ++--
 2 files changed, 8 insertions(+), 8 deletions(-)

```

### 最近 5 次提交
```

a1b2c3d feat: add bcrypt helpers
d4e5f6g refactor: split auth module
h7i8j9k docs: update README
l0m1n2o fix: handle empty password
p3q4r5s initial commit

```

---

## 🏷️ 关键词 (供自动匹配用)

`用户, 登录, 认证, bcrypt, jwt`

---

## 🚀 接力指南

**最快入口** —— 对新 session 说:
> "读取 `~/.relay-cards/...` 继续之前的工作"
> "读取 `~/.relay-cards/latest.md` 继续"

---

_本卡片由 Relay Card 自动生成 (v0.6)_
_历史卡片: `~/.relay-cards/`_
```

## 关键词设计原则

1. **goal 段必须纯净** — 不含「也/顺便/顺带/还看了」等混淆词
2. **关键词来自对话** — 自动从 transcript 抽中英 n-gram top 8
3. **title 加权 3x** — 让用户口语化主任务词排在前面
4. **OPT-IN 读取** — 用户说「继续 XXX」才用关键词匹配找卡