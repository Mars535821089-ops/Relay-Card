#!/bin/bash
# 接力卡端到端集成测试
# ============================================================================
# 模拟真实用户场景: 写卡 → 列卡 → 归档 → 脱敏 → 统计
# ============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
export RELAY_HOME="$REPO_ROOT/src/lib"
export RELAY_DIR="$TEST_ROOT/relay-cards"
mkdir -p "$RELAY_DIR"

echo "════════════════════════════════════════"
echo "🧪 集成测试"
echo "════════════════════════════════════════"
echo "REPO_ROOT: $REPO_ROOT"
echo "TEST_ROOT: $TEST_ROOT"
echo "RELAY_DIR: $RELAY_DIR"
echo "════════════════════════════════════════"

# Step 1: 创建测试 git 仓库
cd "$TEST_ROOT"
git init -q sample-project
cd sample-project
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Sample" > README.md
git add README.md
git commit -qm "Initial commit"

echo "📦 Step 1: 写一张自动卡"
bash "$RELAY_HOME/relay-card-write.sh" --auto
sleep 1

echo "📦 Step 2: 写一张手动卡 (JSON stdin)"
cat <<EOF | bash "$RELAY_HOME/relay-card-write.sh"
{
  "title": "user-auth-feature",
  "goal": "实现用户登录功能",
  "done": ["设计 schema", "写密码哈希工具"],
  "todo": ["实现 /login endpoint"],
  "decisions": ["使用 bcrypt"],
  "pits": ["pyjwt 2.x 与 1.x 签名不同"]
}
EOF
sleep 1

echo "📦 Step 3: 写第二张手动卡"
cat <<EOF | bash "$RELAY_HOME/relay-card-write.sh"
{
  "title": "pricing-feature",
  "goal": "实现定价控制台",
  "done": ["数据模型", "API"],
  "todo": ["UI 调整"]
}
EOF

echo "📦 Step 4: 验证卡片生成"
CARD_COUNT=$(ls -1 "$RELAY_DIR"/[0-9]*.md | wc -l | tr -d ' ')
if [ "$CARD_COUNT" -ne 3 ]; then
  echo "❌ 期望 3 张卡, 实际 $CARD_COUNT"
  exit 1
fi
echo "  ✅ 3 张卡已生成"

echo "📦 Step 5: 验证 latest.md"
[ -f "$RELAY_DIR/latest.md" ]
grep -q "user-auth-feature" "$RELAY_DIR/latest.md" || grep -q "pricing-feature" "$RELAY_DIR/latest.md"
echo "  ✅ latest.md 已生成"

echo "📦 Step 6: 跑脱敏自检"
bash "$RELAY_HOME/relay-card-sanitize.sh" --test >/dev/null
echo "  ✅ sanitize 自检通过"

echo "📦 Step 7: 跑统计"
bash "$RELAY_HOME/relay-card-stats.sh" > "$TEST_ROOT/stats.md"
grep -q "总卡数" "$TEST_ROOT/stats.md"
echo "  ✅ stats 输出正常"

echo "📦 Step 8: 跑归档 (演练)"
bash "$RELAY_HOME/relay-card-archive.sh" --dry-run --keep 2 >/dev/null
echo "  ✅ archive dry-run 通过"

echo "📦 Step 9: 跑错误日志测试"
bash "$RELAY_HOME/relay-card-errors.sh" test >/dev/null
[ -f "$RELAY_DIR/.errors.log" ]
echo "  ✅ errors log 工作正常"

echo "════════════════════════════════════════"
echo "✅ 所有集成测试通过"
echo "════════════════════════════════════════"

# 清理
rm -rf "$TEST_ROOT"
exit 0