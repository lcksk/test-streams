#!/bin/bash
# A/V desync 诊断：对照实验采集（不做 PASS/FAIL，只列出关键事件）
# 用法: ./diag_discont_seek.sh
set -u
BASE=${BASE:-http://192.168.3.24/hls_discontinuity_tests}
OUT=${OUT:-/tmp/diag_discont}; mkdir -p "$OUT"

# label|srcdir|position_ms|wait_sec
CONTROLS="
C9-r720-noseek|sk1-720p|0|40
C10-r720-seek15|sk1-720p|15000|26
C11-r720-seek12|sk1-720p|12000|28
"

while IFS='|' read -r label d pos wait; do
    [ -z "$label" ] && continue
    log="$OUT/$label.log"
    adb logcat -G 64M >/dev/null 2>&1 </dev/null
    adb logcat -c </dev/null
    adb shell am force-stop is.xyz.mpv </dev/null
    sleep 2
    (adb logcat -v time -s mpv > "$log" </dev/null &)
    adb shell am start -a android.intent.action.VIEW -d "$BASE/$d/index.m3u8" \
        -n is.xyz.mpv/.MPVActivity --ei position "$pos" >/dev/null 2>&1 </dev/null
    sleep "$wait"
    pkill -f "adb logcat" >/dev/null 2>&1
    echo "########## $label  ($d @ ${pos}ms) ##########"
    echo "-- reconfig 序列 --"; grep -oE 'reconfig to [0-9]+x[0-9]+' "$log" | uniq -c || true
    echo "-- Invalid audio PTS --"; grep -E 'Invalid audio PTS' "$log" || echo "(无)"
    echo "-- desync 计数 --"; grep -c 'desynchron' "$log" || true
    echo "-- audio underrun 计数 --"; grep -c 'underrun' "$log" || true
    echo "-- restart/EOF --"; grep -E 'playback restart complete|video EOF reached|audio EOF reached' "$log" | head -6 || true
    echo
done <<EOF
$CONTROLS
EOF
echo "日志目录: $OUT"
