#!/usr/bin/env bats
# ============================================================================
# relay-card-index.sh 单元测试
# ============================================================================

setup() {
  export RELAY_HOME="$BATS_TEST_DIRNAME/../src/lib"
  export RELAY_DIR="$BATS_TEST_TMPDIR/relay-cards"
  mkdir -p "$RELAY_DIR"
}

teardown() {
  rm -rf "$RELAY_DIR"
}

@test "index: generates latest.md with recent cards" {
  for i in 1 2 3; do
    cat > "$RELAY_DIR/2026010${i}-120000-test-branch.md" <<EOF
# Card $i
> 📁 **项目根**: \`/path/to/project$i\`
> 🌿 **当前分支**: \`feat-$i\`

## 🎯 当前任务

Doing task $i
EOF
  done

  bash "$RELAY_HOME/relay-card-index.sh" 5 >/dev/null 2>&1
  [ -f "$RELAY_DIR/latest.md" ]
  grep -q "接力卡清单" "$RELAY_DIR/latest.md"
  grep -q "project1\|project2\|project3" "$RELAY_DIR/latest.md"
}

@test "index: respects KEEP_RECENT limit" {
  for i in 1 2 3 4 5; do
    echo "card $i" > "$RELAY_DIR/2026010${i}-120000-test.md"
  done

  bash "$RELAY_HOME/relay-card-index.sh" 2 >/dev/null 2>&1
  # latest.md 应只列最近 2 张
  COUNT=$(grep -c "^### #" "$RELAY_DIR/latest.md")
  [ "$COUNT" -le 2 ]
}