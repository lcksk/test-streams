#!/bin/bash
# 对已有 logcat 日志重新判定（不重播），复用 assert_cases_device.sh 的期望表与判定段。
#
#   ./judge_logs.sh              # 判定 /tmp/dev_cases 下所有已有日志
#   ./judge_logs.sh case05 ...   # 只判定指定用例
#
# 用途：一轮全量跑完后定位失败项，避免为了看失败条目再重播一遍。
set -u
OUT=${OUT:-/tmp/dev_cases}
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/assert_cases_device.sh"

CASES=$(sed -n '/^CASES="/,/^"$/p' "$SRC" | sed '1d;$d')
JUDGE=$(sed -n '/^    # 播放墙钟时长：playback restart complete/,/^}$/p' "$SRC" | sed '$d')

pass() { printf "  [PASS] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; CASE_FAILS=$((CASE_FAILS+1)); }
eq()   { if [ "$2" = "$3" ]; then pass "$1 = $2"; else fail "$1 = $2 (期望 $3)"; fi; }
near() { if awk -v a="$2" -v b="$3" -v t="$4" 'BEGIN{exit !(a-b<=t && b-a<=t)}'; then
             pass "$1 = $2 (期望 $3±$4)"; else fail "$1 = $2 (期望 $3±$4)"; fi; }

judge_one() {
    local d="$1" dur="$2" nvd="$3" nad="$4" newres="$5" newaudio="$6"
    local obs="${7:-0}" desync="${8:-0}"
    local log="$OUT/$d.log"
    if [ ! -s "$log" ]; then echo "  [SKIP] 无日志 $log"; return; fi
    eval "$JUDGE"
}

only="$*"
total_bad=0
while read -r d dur nvd nad newres newaudio obs desync; do
    [ -z "$d" ] && continue
    [ -n "$only" ] && ! echo " $only " | grep -q " $d " && continue
    echo "== $d =="
    CASE_FAILS=0
    judge_one "$d" "$dur" "$nvd" "$nad" "$newres" "$newaudio" "$obs" "$desync"
    [ "$CASE_FAILS" -gt 0 ] && total_bad=$((total_bad + 1))
done <<EOF
$CASES
EOF

echo
echo "失败用例数：$total_bad"
[ "$total_bad" -eq 0 ] && echo "（离线判定：全部通过）"
exit 0
