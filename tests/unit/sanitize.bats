#!/usr/bin/env bats
# ============================================================================
# relay_card_sanitize.py 单元测试
# ============================================================================

setup() {
  export PY_CORE="$BATS_TEST_DIRNAME/../../src/lib/relay_card_sanitize.py"
}

@test "sanitize: redacts sk- prefix" {
  result=$(echo "key is sk-1234567890abcdef1234567890abcdef here" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:api-key]"* ]]
  [[ "$result" != *"sk-1234567890abcdef"* ]]
}

@test "sanitize: redacts ghp_ GitHub tokens" {
  result=$(echo "token ghp_abcdefghijklmnopqrstuvwxyz1234567890" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:github-token]"* ]]
}

@test "sanitize: redacts emails" {
  result=$(echo "contact user@example.com" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:email@example.com]"* ]]
  [[ "$result" != *"user@"* ]]
}

@test "sanitize: redacts AWS keys" {
  result=$(echo "AKIA1234567890ABCDEF" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:aws-akid]"* ]]
}

@test "sanitize: redacts JWT tokens" {
  result=$(echo "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:jwt]"* ]]
}

@test "sanitize: idempotent on already-redacted text" {
  INPUT="before [REDACTED:api-key] after sk-1234567890abcdef1234567890abcdef"
  result=$(echo "$INPUT" | python3 "$PY_CORE" 2>/dev/null)
  # 第一次的 [REDACTED:api-key] 应保留, 新的 sk- 也应被脱敏
  [[ "$result" == *"[REDACTED:api-key]"* ]]
  [[ "$result" != *"sk-1234567890"* ]]
}

@test "sanitize: leaves normal text alone" {
  result=$(echo "Hello world, this is a normal message" | python3 "$PY_CORE" 2>/dev/null)
  [ "$result" = "Hello world, this is a normal message" ]
}

@test "sanitize: redacts private key block" {
  result=$(printf '%s' '-----BEGIN RSA PRIVATE KEY-----'"$IFS"'abcdef123' "$IFS"'-----END RSA PRIVATE KEY-----' | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:private-key-block]"* ]]
}

@test "sanitize: redacts Bearer tokens" {
  result=$(echo "Authorization: Bearer abc123xyz456def789ghi012jkl" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"[REDACTED:bearer-token]"* ]]
}

@test "sanitize: redacts ENV-style secrets" {
  result=$(echo "OPENAI_API_KEY=sk-proj-xxxxxxxxxxxxx" | python3 "$PY_CORE" 2>/dev/null)
  [[ "$result" == *"REDACTED"* ]]
}