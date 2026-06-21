#!/bin/bash
# Release helper — tag and push
# 用法: bash scripts/release.sh [patch|minor|major]
set -euo pipefail

LEVEL="${1:-patch}"
case "$LEVEL" in
  patch | minor | major) ;;
  *)
    echo "用法: $0 [patch|minor|major]"
    exit 1
    ;;
esac

if [ ! -d .git ]; then
  echo "❌ not a git repo"
  exit 1
fi

# Ensure clean tree
if ! git diff --quiet HEAD 2>/dev/null; then
  echo "❌ working tree not clean, commit first"
  exit 1
fi

# 用 Python 处理 version bumping (避开 bash brace expansion 的坑)
LEVEL="$LEVEL" python3 <<'PYEOF'
import os, re, subprocess

level = os.environ['LEVEL']
cur = subprocess.run(['git', 'tag', '--sort=-v:refname'], capture_output=True, text=True).stdout
cur = cur.split('\n')[0] if cur.strip() else 'v0.0.0'
m = re.match(r'v(\d+)\.(\d+)\.(\d+)', cur)
if not m:
    print(f"❌ can't parse current tag: {cur!r}")
    raise SystemExit(1)
major, minor, patch = map(int, m.groups())
if level == 'major':
    major += 1; minor = 0; patch = 0
elif level == 'minor':
    minor += 1; patch = 0
else:
    patch += 1
new = f'v{major}.{minor}.{patch}'
print(f'▶ New version: {new}')
# 写入 .VERSION 供 GitHub Actions 用 (替代 json 解析)
with open('.VERSION', 'w') as f:
    f.write(new + '\n')
# tag
subprocess.run(['git', 'tag', '-a', new, '-m', f'Release {new}'], check=True)
subprocess.run(['git', 'push', 'origin', new], check=True)
print(f'✅ tagged {new}')
PYEOF
