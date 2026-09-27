#!/bin/bash
# 用例批量运行器：带实时进度与 ETA，可后台运行，进度落盘可随时 tail
#
#   ./run_progress.sh cases                  # 全部 discontinuity 用例
#   ./run_progress.sh seek                   # 全部 seek 用例
#   ./run_progress.sh subtitle               # 全部字幕用例（外部 WebVTT + 内嵌 MP4）
#   ./run_progress.sh cases case05 case06    # 指定用例
#   ./run_progress.sh seek sk-pos-03a
#   ./run_progress.sh subtitle sub-W-base-pos
#
# 进度文件：${PROGRESS:-/tmp/run_progress.txt}
#   tail -f /tmp/run_progress.txt
set -u

MODE=${1:-}
shift 2>/dev/null || true
OUT=${PROGRESS:-/tmp/run_progress.txt}
: > "$OUT"

case "$MODE" in
  cases)
    if [ $# -gt 0 ]; then CASES="$*"
    else CASES=$(ls /tmp/dev_cases/*.log 2>/dev/null | sed 's#.*/##; s#\.log$##' | sort); fi
    RUN="bash assert_cases_device.sh"
    ;;
  seek)
    if [ $# -gt 0 ]; then CASES="$*"
    else CASES=$(ls /tmp/dev_seek_cases/*.log 2>/dev/null | sed 's#.*/##; s#\.log$##' | sort); fi
    RUN="bash assert_seek_cases_device.sh"
    ;;
  subtitle)
    if [ $# -gt 0 ]; then CASES="$*"
    else CASES=$(ls /tmp/dev_subtitle_cases/*.log 2>/dev/null | sed 's#.*/##; s#\.log$##' | sort); fi
    RUN="bash assert_subtitle_cases_device.sh"
    ;;
  *) echo "用法: $0 {cases|seek|subtitle} [用例...]" >&2; exit 2;;
esac

TOTAL=$(echo $CASES | wc -w)
if [ "$TOTAL" -eq 0 ]; then echo "没有用例可跑" >> "$OUT"; exit 1; fi
echo "== 开始 $MODE：共 $TOTAL 例" >> "$OUT"

START=$(date +%s)
I=0; PASS=0; FAIL=0; FAILED=""
for c in $CASES; do
  I=$((I+1))
  echo "[$I/$TOTAL] $c 运行中…" >> "$OUT"
  T0=$(date +%s)
  R=$(timeout 240 $RUN "$c" 2>&1)
  CE=$(( $(date +%s) - T0 ))
  # PASS 需同时满足：脚本报“全部通过” 且 该用例确实被执行过（出现 "== <id> " 头）。
  # 否则“过滤不到用例”会被误判为 PASS（脚本对 0 用例也打印“全部通过”）。
  if echo "$R" | grep -q "全部通过" && echo "$R" | grep -q "== $c "; then
    ST=PASS; PASS=$((PASS+1))
  else
    ST=FAIL; FAIL=$((FAIL+1)); FAILED="$FAILED $c"
    { echo "--- $c 失败项："; echo "$R" | grep -E "^ *\[FAIL\]"; } >> "$OUT"
  fi
  EL=$(( $(date +%s) - START ))
  ETA=$(( EL / I * (TOTAL - I) ))
  printf '[%d/%d] %-26s %s  本用例 %ds | 已用 %dm%02ds | 剩余约 %dm%02ds\n' \
    "$I" "$TOTAL" "$c" "$ST" "$CE" "$((EL/60))" "$((EL%60))" "$((ETA/60))" "$((ETA%60))" >> "$OUT"
done

EL=$(( $(date +%s) - START ))
echo "== 结束：PASS $PASS FAIL $FAIL | 总用时 $((EL/60))m$((EL%60))s" >> "$OUT"
[ -n "$FAILED" ] && echo "== 失败用例：$FAILED" >> "$OUT"
exit 0
