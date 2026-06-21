#!/usr/bin/env bats
# ============================================================================
# relay-card-errors.sh 单元测试
# ============================================================================

setup() {
  export RELAY_HOME="$BATS_TEST_DIRNAME/../../src/lib"
  export RELAY_DIR="$BATS_TEST_TMPDIR/relay-cards"
  mkdir -p "$RELAY_DIR"
}

teardown() {
  rm -rf "$RELAY_DIR"
}

@test "errors: test subcommand writes a log entry" {
  bash "$RELAY_HOME/relay-card-errors.sh" test >/dev/null 2>&1
  [ -f "$RELAY_DIR/.errors.log" ]
  grep -q "test-script" "$RELAY_DIR/.errors.log"
}

@test "errors: tail shows recent entries" {
  bash "$RELAY_HOME/relay-card-errors.sh" test >/dev/null 2>&1
  run bash "$RELAY_HOME/relay-card-errors.sh" tail 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"test-script"* ]]
}

@test "errors: stats aggregates by script" {
  bash "$RELAY_HOME/relay-card-errors.sh" test >/dev/null 2>&1
  run bash "$RELAY_HOME/relay-card-errors.sh" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"总错误数"* ]]
}

@test "errors: clear backs up and removes log" {
  bash "$RELAY_HOME/relay-card-errors.sh" test >/dev/null 2>&1
  bash "$RELAY_HOME/relay-card-errors.sh" clear >/dev/null 2>&1
  [ ! -f "$RELAY_DIR/.errors.log" ]
  # 备份应存在
  ls "$RELAY_DIR"/.errors.log.cleared-* >/dev/null 2>&1
}

@test "errors: trap source mode works" {
  # Source the file then trigger a failing command
  source "$RELAY_HOME/relay-card-errors.sh"
  relay_trap_init "test-source-mode"

  ( false ) || true  # 触发 ERR 但不退出

  [ -f "$RELAY_DIR/.errors.log" ]
}