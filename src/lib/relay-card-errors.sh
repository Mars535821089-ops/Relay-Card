#!/bin/bash
# 接力卡错误日志工具 - 工具无关
# ============================================================================
# 用途:
#   1. 给所有 relay-* 脚本提供统一的错误捕获 wrapper
#   2. 提供查询接口 (tail / stats / clear / test)
#
# 日志位置: $RELAY_DIR/.errors.log (JSONL)
# 日志格式: {"ts":"...","script":"...","exit":N,"msg":"...","cwd":"..."}
#
# 用法:
#   作为 wrapper:
#     source relay-card-errors.sh
#     relay_trap_init "my-script-name"
#
#   作为查询工具:
#     bash relay-card-errors.sh tail [N]       # 最近 N 条 (默认 10)
#     bash relay-card-errors.sh stats          # 按脚本统计
#     bash relay-card-errors.sh clear          # 清空日志
#     bash relay-card-errors.sh test           # 写一条测试日志
# ============================================================================

RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"
ERROR_LOG="$RELAY_DIR/.errors.log"

# === Source 模式: 给其他脚本套 trap ===
relay_trap_init() {
  local script_name="${1:-unknown}"
  set -E
  trap "relay_log_error '$script_name' \$? \"\$BASH_COMMAND\" \$LINENO" ERR
}

# 记录一条错误
relay_log_error() {
  # trap ERR 触发时进入, 关掉 set -e 防递归
  set +e +E
  local script="$1"
  local exit_code="$2"
  local cmd="$3"
  local line="${4:-?}"
  local ts
  ts=$(date '+%Y-%m-%dT%H:%M:%S%z')
  mkdir -p "$RELAY_DIR"
  # 写前检查行数, 超过 1000 自动 rotate (保留最近 500)
  if [ -f "$ERROR_LOG" ]; then
    local lines
    lines=$(wc -l <"$ERROR_LOG" 2>/dev/null | tr -d ' ')
    if [ "${lines:-0}" -gt 1000 ]; then
      local rotate_ts
      rotate_ts=$(date +%Y%m%d-%H%M%S)
      mv "$ERROR_LOG" "${ERROR_LOG}.rotated-${rotate_ts}" 2>/dev/null || true
      tail -n 500 "${ERROR_LOG}.rotated-${rotate_ts}" >"$ERROR_LOG" 2>/dev/null || true
    fi
  fi
  # 用 Python 输出 JSONL, 避免 shell 转义麻烦
  python3 -c "
import json, sys
entry = {
    'ts': '$ts',
    'script': '$script',
    'exit': $exit_code,
    'line': '$line',
    'cmd': '''$cmd'''[:300],
    'cwd': '$PWD'[:200]
}
print(json.dumps(entry, ensure_ascii=False))
" >>"$ERROR_LOG" 2>/dev/null || {
    # Python 失败兜底
    echo "{\"ts\":\"$ts\",\"script\":\"$script\",\"exit\":$exit_code,\"line\":\"$line\",\"cmd\":\"$(echo "$cmd" | head -c 200 | sed 's/\"/\\\"/g')\"}" >>"$ERROR_LOG"
  }
}

# === CLI 模式 ===
cmd_tail() {
  local n="${1:-10}"
  if [ ! -f "$ERROR_LOG" ]; then
    echo "✅ 无错误日志: $ERROR_LOG"
    return 0
  fi
  local total
  total=$(wc -l <"$ERROR_LOG" | tr -d ' ')
  echo "📋 最近 $n 条错误 (共 $total 条) — $ERROR_LOG"
  echo "─────────────────────────────────────────"
  tail -n "$n" "$ERROR_LOG" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        ts = e.get('ts', '?')
        script = e.get('script', '?')
        exit_code = e.get('exit', '?')
        ln = e.get('line', '?')
        cmd = e.get('cmd', '?')[:100]
        print(f'  [{ts}] {script}:{ln} exit={exit_code}')
        print(f'    cmd: {cmd}')
    except Exception as ex:
        print(f'  [parse-error] {line[:120]}')
"
}

cmd_stats() {
  if [ ! -f "$ERROR_LOG" ] || [ ! -s "$ERROR_LOG" ]; then
    echo "✅ 无错误记录"
    return 0
  fi
  echo "📊 错误统计 — $ERROR_LOG"
  echo "─────────────────────────────────────────"
  python3 -c "
import json, sys
from collections import Counter
script_cnt = Counter()
exit_cnt = Counter()
total = 0
with open('$ERROR_LOG') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
            script_cnt[e.get('script', '?')] += 1
            exit_cnt[e.get('exit', '?')] += 1
            total += 1
        except: pass

print(f'总错误数: {total}')
print()
print('按脚本分布:')
for s, c in script_cnt.most_common(10):
    bar = '█' * min(c, 40)
    print(f'  {s:30s} {c:4d}  {bar}')
print()
print('按 exit code:')
for code, c in exit_cnt.most_common(10):
    print(f'  exit={code:4} ×{c}')
"
}

cmd_clear() {
  if [ -f "$ERROR_LOG" ]; then
    local backup="${ERROR_LOG}.cleared-$(date +%Y%m%d-%H%M%S)"
    mv "$ERROR_LOG" "$backup"
    echo "✅ 日志已清空, 备份: $backup"
  else
    echo "无日志可清"
  fi
}

cmd_test() {
  relay_log_error "test-script" 42 "false || true" 99
  echo "✅ 测试错误已写入 $ERROR_LOG"
  cmd_tail 1
}

cmd_help() {
  cat <<EOF
relay-card-errors.sh — 接力卡错误日志

CLI 模式:
  $0 tail [N]    最近 N 条错误 (默认 10)
  $0 stats       按脚本统计
  $0 clear       清空日志 (自动备份)
  $0 test        写一条测试

Source 模式 (给其他脚本套 trap):
  source $0
  relay_trap_init "my-script"
  # 之后任何失败自动记录到 $ERROR_LOG
EOF
}

# 只在直接执行时跑 CLI; source 时不跑
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then
  case "${1:-help}" in
    tail)
      shift
      cmd_tail "${1:-10}"
      ;;
    stats) cmd_stats ;;
    clear) cmd_clear ;;
    test) cmd_test ;;
    help | --help | -h | "") cmd_help ;;
    *)
      echo "未知子命令: $1"
      cmd_help
      exit 1
      ;;
  esac
fi
