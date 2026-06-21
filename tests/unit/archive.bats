#!/usr/bin/env bats
# ============================================================================
# relay-card-archive.sh 单元测试
# ============================================================================

setup() {
  export RELAY_HOME="$BATS_TEST_DIRNAME/../../src/lib"
  export RELAY_DIR="$BATS_TEST_TMPDIR/relay-cards"
  mkdir -p "$RELAY_DIR"
}

teardown() {
  rm -rf "$RELAY_DIR"
}

@test "archive: --stats prints inventory without modifying" {
  # 创建 3 张测试卡
  for i in 1 2 3; do
    echo "card $i" > "$RELAY_DIR/2026010${i}-120000-test-branch.md"
  done

  run bash "$RELAY_HOME/relay-card-archive.sh" --stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"活跃: 3"* ]]
  # 不应该移动任何文件 (wc -l 输出带前导空格, 用 tr 去空格)
  [ "$(ls "$RELAY_DIR"/*.md | wc -l | tr -d ' ')" = "3" ]
}

@test "archive: --dry-run keeps KEEP_ACTIVE most recent" {
  for i in 1 2 3 4 5; do
    echo "card $i" > "$RELAY_DIR/2026010${i}-120000-test-branch.md"
  done

  run bash "$RELAY_HOME/relay-card-archive.sh" --dry-run --keep 2
  [ "$status" -eq 0 ]
  # dry-run 不应移动任何文件
  [ "$(ls "$RELAY_DIR"/*.md | wc -l | tr -d ' ')" = "5" ]
}

@test "archive: pin protection" {
  echo "old card" > "$RELAY_DIR/20260101-120000-test-branch.md"
  touch "$RELAY_DIR/20260101-120000-test-branch.md.pin"
  echo "newer card" > "$RELAY_DIR/20260105-120000-test-branch.md"

  bash "$RELAY_HOME/relay-card-archive.sh" --keep 1 >/dev/null 2>&1

  # pin 的卡不应被归档
  [ -f "$RELAY_DIR/20260101-120000-test-branch.md" ]
  # newer 卡应被归档（因为只保留 1 张）
  [ ! -f "$RELAY_DIR/20260105-120000-test-branch.md" ]
}