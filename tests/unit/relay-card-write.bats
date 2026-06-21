#!/usr/bin/env bats
# ============================================================================
# relay-card-write.sh 单元测试
# ============================================================================

setup() {
  export RELAY_HOME="$BATS_TEST_DIRNAME/../src/lib"
  export RELAY_DIR="$BATS_TEST_TMPDIR/relay-cards"
  mkdir -p "$RELAY_DIR"

  cd "$BATS_TEST_TMPDIR"
  git init -q .
  git config user.email "test@example.com"
  git config user.name "test"
}

teardown() {
  rm -rf "$RELAY_DIR"
}

@test "relay-card-write: --auto creates a card" {
  run bash "$RELAY_HOME/relay-card-write.sh" --auto
  [ "$status" -eq 0 ]
  [ -n "$(ls -A "$RELAY_DIR"/[0-9]*.md 2>/dev/null)" ]
}

@test "relay-card-write: stdin JSON creates structured card" {
  cat <<EOF | bash "$RELAY_HOME/relay-card-write.sh"
{
  "title": "test-feature",
  "goal": "implement feature X",
  "done": ["step 1", "step 2"],
  "todo": ["step 3"],
  "decisions": ["use Y instead of Z"],
  "pits": ["Y requires Python 3.10+"]
}
EOF

  CARD=$(ls "$RELAY_DIR"/[0-9]*.md | head -1)
  [ -f "$CARD" ]
  grep -q "test-feature" "$CARD"
  grep -q "implement feature X" "$CARD"
  grep -q "step 1" "$CARD"
  grep -q "step 2" "$CARD"
  grep -q "step 3" "$CARD"
  grep -q "use Y instead of Z" "$CARD"
}

@test "relay-card-write: rejects confusing TITLE" {
  run bash "$RELAY_HOME/relay-card-write.sh" <<'EOF'
{"title": "实现 pricing (顺便看 comfyui)", "goal": "定价", "done": [], "todo": []}
EOF
  [ "$status" -eq 2 ]
}

@test "relay-card-write: malformed JSON doesn't crash" {
  run bash "$RELAY_HOME/relay-card-write.sh" <<< 'not json'
  # 应能容忍, 走 fallback
  [ "$status" -eq 0 ] || [ "$status" -eq 2 ]
}

@test "relay-card-write: updates latest.md" {
  bash "$RELAY_HOME/relay-card-write.sh" --auto
  [ -f "$RELAY_DIR/latest.md" ]
  grep -q "接力卡清单" "$RELAY_DIR/latest.md"
}