#!/bin/bash
# 针对无 discontinuity 的长视频，隔离"变速"变量：
#   Phase A: 仅切倍速（不 seek），看变速本身是否就触发不同步/视频 PTS 异常
#   Phase B: 变速 + 多次 seek 交错，看组合场景
URL="http://192.168.3.24/standard_vod/hls/rmdmy/index.m3u8"
OUT=/tmp/rmdmy_speed_seek.log
PROG=/tmp/rmdmy_progress.txt
: > "$PROG"
echo "开始: $URL" | tee -a "$PROG"

adb logcat -G 64M >/dev/null 2>&1
adb logcat -c
adb shell am force-stop is.xyz.mpv
sleep 1
(adb logcat -v time -s mpv > "$OUT" 2>&1 &)
adb shell am start -a android.intent.action.VIEW -d "$URL" -n is.xyz.mpv/.MPVActivity >/dev/null 2>&1

# 等待加载
for i in $(seq 1 60); do
  grep -q "Opening http.*rmdmy" "$OUT" 2>/dev/null && { echo "已加载 URL ($(date +%T))" | tee -a "$PROG"; break; }
  sleep 0.5
done
sleep 3

sp() { adb shell am broadcast -a is.xyz.mpv.DEBUG_CMD --es cmd speed --ef value "$1" >/dev/null 2>&1; echo "  [speed=$1]" | tee -a "$PROG"; }
sk() { adb shell am broadcast -a is.xyz.mpv.DEBUG_CMD --es cmd seek --ef value "$1" >/dev/null 2>&1; echo "  [seek=$1]" | tee -a "$PROG"; }

echo "=== Phase A: 仅变速（无 seek），隔离变速本身 ===" | tee -a "$PROG"
for s in 2.0 0.5 1.5 4.0 1.0 3.0 0.75 2.0 1.0; do
  sp "$s"; sleep 4
done

echo "=== Phase B: 变速 + 多次 seek 交错 ===" | tee -a "$PROG"
seeks=(5 20 40 60 90 120 150 180)
speeds=(2.0 0.5 3.0 1.5 4.0 1.0 2.0 0.75)
for i in $(seq 0 7); do
  echo "--- round $i ---" | tee -a "$PROG"
  sp "${speeds[$i]}"; sleep 3
  sk "${seeks[$i]}"; sleep 5
done

sleep 4
pkill -f "adb logcat" >/dev/null 2>&1
echo "完成，日志: $OUT" | tee -a "$PROG"
