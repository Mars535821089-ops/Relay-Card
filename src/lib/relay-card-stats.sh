#!/bin/bash
# 接力卡使用统计 - 工具无关
# ============================================================================
# 统计项:
#   - 总卡数 (活跃 + 归档)
#   - 本月 / 本周 / 今天卡数
#   - 项目分布 Top 5
#   - 平均写卡间隔
#   - 平均待办密度
#
# 用法:
#   bash relay-card-stats.sh           # markdown 输出
#   bash relay-card-stats.sh --json    # JSON 输出
# ============================================================================

set -euo pipefail

RELAY_DIR="${RELAY_DIR:-$HOME/.relay-cards}"

if [ ! -d "$RELAY_DIR" ]; then
  echo "❌ 接力卡目录不存在: $RELAY_DIR"
  exit 1
fi

FORMAT="${1:-md}"
if [ "$FORMAT" = "--json" ]; then FORMAT="json"; fi

python3 -c "
import os, re, json, sys, glob
from collections import Counter, defaultdict
from datetime import datetime, timedelta

RELAY_DIR = '$RELAY_DIR'
FORMAT = '$FORMAT'
now = datetime.now()

# 收集所有卡 (活跃 + 归档)
active = sorted(glob.glob(os.path.join(RELAY_DIR, '[0-9]*.md')))
archived = sorted(glob.glob(os.path.join(RELAY_DIR, 'archive', '**', '[0-9]*.md*'), recursive=True))
all_cards = active + archived

# === 读 .restore.log 统计 restore 触发 ===
restore_log = os.path.join(RELAY_DIR, '.restore.log')
restore_total = 0
restore_today = 0
restore_this_week = 0
restore_rec_dist = Counter()
restore_proj_dist = Counter()
if os.path.exists(restore_log):
    with open(restore_log, 'r', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split('\t')
            if len(parts) < 2: continue
            ts_str = parts[0]
            try:
                ts = datetime.fromisoformat(ts_str.split('+')[0].split('Z')[0])
            except: continue
            restore_total += 1
            if ts.date() == now.date():
                restore_today += 1
            if (now - ts).days < 7:
                restore_this_week += 1
            for p in parts[1:]:
                if p.startswith('rec='):
                    restore_rec_dist[p[4:]] += 1
                elif p.startswith('project='):
                    restore_proj_dist[p[8:]] += 1

if not all_cards:
    print('❌ 无卡')
    sys.exit(0)

def parse_ts(p):
    bn = os.path.basename(p)
    m = re.match(r'(\d{8})-(\d{6})', bn)
    if not m: return None
    try:
        return datetime.strptime(f'{m.group(1)}{m.group(2)}', '%Y%m%d%H%M%S')
    except: return None

cards = []
for p in all_cards:
    ts = parse_ts(p)
    if ts: cards.append((ts, p))
cards.sort()

proj_cnt = Counter()
todo_cnt_total = 0
todo_cards = 0
for ts, p in cards:
    try:
        with open(p, 'r', errors='ignore') as f:
            content = f.read()
        m = re.search(r'项目根.*?\`([^\`]+)\`', content)
        if m:
            proj_cnt[os.path.basename(m.group(1))] += 1
        todo_section = re.search(r'## 🔄 进行中.*?(?=^## |\Z)', content, re.MULTILINE | re.DOTALL)
        if todo_section:
            n = len(re.findall(r'^- \[ \]', todo_section.group(), re.MULTILINE))
            todo_cnt_total += n
            todo_cards += 1
    except: pass

today = sum(1 for ts, _ in cards if ts.date() == now.date())
this_week = sum(1 for ts, _ in cards if (now - ts).days < 7)
this_month = sum(1 for ts, _ in cards if ts.year == now.year and ts.month == now.month)

intervals = []
for i in range(1, len(cards)):
    delta = (cards[i][0] - cards[i-1][0]).total_seconds() / 60
    if 0 < delta < 7*24*60:
        intervals.append(delta)
avg_interval_min = sum(intervals) / len(intervals) if intervals else 0

avg_todo = todo_cnt_total / todo_cards if todo_cards else 0

data = {
    'total': len(cards),
    'active': len(active),
    'archived': len(archived),
    'today': today,
    'this_week': this_week,
    'this_month': this_month,
    'avg_interval_minutes': round(avg_interval_min, 1),
    'avg_todo_density': round(avg_todo, 1),
    'top_projects': proj_cnt.most_common(5),
    'first_card_ts': cards[0][0].isoformat() if cards else None,
    'latest_card_ts': cards[-1][0].isoformat() if cards else None,
    'restore': {
        'total': restore_total,
        'today': restore_today,
        'this_week': restore_this_week,
        'rec_dist': dict(restore_rec_dist),
        'top_projects': restore_proj_dist.most_common(3),
    },
}

if FORMAT == 'json':
    print(json.dumps(data, ensure_ascii=False, indent=2))
else:
    print('# 📊 接力卡使用统计')
    print()
    print(f'_生成时间: {now.strftime(\"%Y-%m-%d %H:%M:%S\")}_')
    print()
    print('## 总览')
    print()
    print(f'| 指标 | 值 |')
    print(f'|---|---|')
    print(f'| 总卡数 | **{data[\"total\"]}** ({data[\"active\"]} 活跃 + {data[\"archived\"]} 归档) |')
    print(f'| 今天 | {data[\"today\"]} |')
    print(f'| 本周 | {data[\"this_week\"]} |')
    print(f'| 本月 | {data[\"this_month\"]} |')
    print(f'| 平均写卡间隔 | {data[\"avg_interval_minutes\"]} 分钟 |')
    print(f'| 平均待办密度 | {data[\"avg_todo_density\"]} 条/张 |')
    print(f'| 首张时间 | {data[\"first_card_ts\"] or \"-\"} |')
    print(f'| 最新时间 | {data[\"latest_card_ts\"] or \"-\"} |')
    print()
    print('## Restore 触发统计 (SessionStart 时)')
    if restore_total > 0:
        print()
        print(f'| 指标 | 值 |')
        print(f'|---|---|')
        print(f'| 累计触发 | {restore_total} 次 |')
        print(f'| 今日触发 | {restore_today} 次 |')
        print(f'| 本周触发 | {restore_this_week} 次 |')
        if restore_rec_dist:
            print()
            print('**推荐等级分布**:')
            for r, c in sorted(restore_rec_dist.items(), key=lambda x: -x[1]):
                bar = '█' * min(c, 20)
                print(f'  {r:6s} ×{c}  {bar}')
        if restore_proj_dist:
            print()
            print('**Top 项目 (Restore 触发时所在)**:')
            for p, c in restore_proj_dist.most_common(3):
                print(f'  - {p} ×{c}')
    else:
        print()
        print('_(无 .restore.log 数据, 需新 session 触发)_')
    print()
    print('## 项目分布 Top 5')
    print()
    if proj_cnt:
        print('| 项目 | 卡数 | 占比 |')
        print('|---|---:|---:|')
        for proj, cnt in data['top_projects']:
            pct = cnt / data['total'] * 100
            bar = '█' * int(pct / 5)
            print(f'| \`{proj}\` | {cnt} | {pct:.1f}% {bar} |')
    else:
        print('_(无项目数据)_')
    print()
    print('## 写卡趋势 (近 14 天)')
    print()
    day_cnt = defaultdict(int)
    for ts, _ in cards:
        day_cnt[ts.date().isoformat()] += 1
    days_back = 14
    max_daily = 1
    for i in range(days_back):
        d = (now - timedelta(days=i)).date().isoformat()
        max_daily = max(max_daily, day_cnt.get(d, 0))
    for i in range(days_back - 1, -1, -1):
        d = (now - timedelta(days=i)).date().isoformat()
        c = day_cnt.get(d, 0)
        bar_len = int(c / max_daily * 20) if max_daily > 0 else 0
        bar = '█' * bar_len
        marker = ' ←今天' if i == 0 else ''
        print(f'  {d}  {c:2d}  \`{bar:<20s}\`{marker}')
    print()
    print('---')
    print(f'_数据源: \`{RELAY_DIR}/\` (含 archive)_')
"