#!/bin/bash
# pts_robustness 真机断言（mpv-android2 / mediacodec 硬解）
#
#   测 discontinuity 组内不一致段是否完整播完，重点检测"丢分段 / 没播完"：
#   - 段完整性：日志里 `HLS request for url '...ts'` 去重段数 vs m3u8 的 #EXTINF 段数
#   - duration↔EOF：实际播放时长 = event:end-file - event:start-file，应与 m3u8
#     的 #EXTINF 加总（真实内容时长）对得上；少一段 → 时长直接变短
#
#   判据（全部取自 logcat 产品行为，不依赖调试日志）：
#     0) 用例时长自洽：expected_duration.txt 与 m3u8 的 #EXTINF 加总对得上
#     1) 段完整：请求的 .ts 段数 == m3u8 的 #EXTINF 段数（丢几段=没播完）
#     2) 无网络失败（Failed to open / Timeout）
#     3) 播放到 EOF（event: end-file，回退 Exiting.）
#     4) 实际播放时长 = end-file - start-file ≈ m3u8 实算时长（duration↔EOF 对应）
#     5) A/V 不同步告警 = 0
#     6) 音频 PTS 真回退 = 0（后值 < 前值才算）
#     7) 硬解报错 = 0
#
# 用法：
#   ./assert_pts_robustness_device.sh            # 全部 12 例
#   ./assert_pts_robustness_device.sh p07_...    # 单例
set -u
BASE=${BASE:-http://192.168.3.24/hls_discontinuity_tests}
CASES_DIR=${CASES_DIR:-/home/lck/work/webroot/hls_discontinuity_tests/pts_robustness}
OUT=${OUT:-/tmp/dev_pts}
mkdir -p "$OUT"

# 防熄屏导致 surface 卸载、长片播到一半被中断
adb shell svc power stayon usb >/dev/null 2>&1 </dev/null

CASE_FAILS=0
pass() { printf "  [PASS] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; CASE_FAILS=$((CASE_FAILS+1)); }

run_one() {
    local d="$1" dir="$CASES_DIR/$d"
    local log="$OUT/$d.log"
    local exp_dur exp_seg calc_dur m3u8="$dir/index.m3u8"
    exp_dur=$(cat "$dir/expected_duration.txt" 2>/dev/null || echo 0)
    # 注意：请求日志按 URL 去重计数（下方 grep -oE ... | sort -u），而清单里同一个 URL 可能
    # 出现多次（same_url / 组内重复段用例，如 p02/p07/p09/p12）。期望值必须取"唯一 URI 数"，
    # 若用 #EXTINF 段数会导致这些用例必然被误判成"丢分段"。
    exp_seg=$(grep -vE '^#|^[[:space:]]*$' "$m3u8" 2>/dev/null | sort -u | wc -l)
    # 从 m3u8 重算真实内容时长，作为比对基准（不盲信 expected_duration.txt）
    # 注意 #EXTINF 是冒号格式：#EXTINF:8.008011,
    calc_dur=$(awk '/#EXTINF:/{d=$0; sub(/.*:/,"",d); sub(/,.*/,"",d); s+=d+0} END{printf "%.6f", s}' "$m3u8" 2>/dev/null)

    adb logcat -G 64M >/dev/null 2>&1 </dev/null
    local started=0 attempt i
    for attempt in 1 2 3; do
        adb logcat -c </dev/null
        adb shell am force-stop is.xyz.mpv </dev/null
        for _ in $(seq 1 20); do adb shell "ps -A 2>/dev/null" </dev/null | grep -qE 'is\.xyz\.mpv' || break; sleep 0.3; done
        (adb logcat -v time -s mpv > "$log" </dev/null &)
        adb shell am start --activity-clear-task --activity-clear-top -a android.intent.action.VIEW \
            -d "$BASE/pts_robustness/$d/index.m3u8" -n is.xyz.mpv/.MPVActivity --ei position 0 \
            >/dev/null 2>&1 </dev/null
        for i in $(seq 1 120); do
            if grep -qE "Opening http|event: (file-loaded|playback-restart|start-file)" "$log" 2>/dev/null; then started=1; break; fi
            sleep 0.5
        done
        [ "$started" = "1" ] && break
        pkill -f "adb logcat" >/dev/null 2>&1
        echo "  -- 第 $attempt 次启动未加载 URL，重试 --"
    done
    if [ "$started" != "1" ]; then
        fail "app 连续 3 次未加载 URL"
        return
    fi

    sleep "$(awk -v d="$exp_dur" 'BEGIN{print d + 15}')"
    pkill -f "adb logcat" >/dev/null 2>&1

    # 0) 用例时长自洽：expected_duration.txt 应与 m3u8 的 #EXTINF 加总一致
    if [ -z "$calc_dur" ]; then
        fail "找不到 $m3u8，无法重算时长"
    elif awk -v a="$calc_dur" -v b="$exp_dur" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d>0.05)}'; then
        fail "用例时长不自洽：m3u8 实算 $calc_dur s ≠ expected_duration.txt $exp_dur s（差>0.05）"
    else
        pass "用例时长自洽：m3u8 $calc_dur s ≈ expected_duration.txt $exp_dur s"
    fi

    # 1) 丢分段检测
    local got_seg
    got_seg=$(grep -oE "Opening http[^ ]*\.ts" "$log" 2>/dev/null | sort -u | wc -l)
    if [ "$got_seg" -lt "$exp_seg" ]; then
        fail "丢分段：请求 $got_seg / 期望 $exp_seg 段"
    else
        pass "段完整：请求 $got_seg / $exp_seg 段"
    fi

    # 2) 网络失败
    if grep -q "Failed to open\|Timeout was reached" "$log" 2>/dev/null; then
        fail "网络失败（Failed to open / Timeout）"
    else
        pass "无网络失败"
    fi

    # 3) 播放到 EOF（优先 event: end-file，回退 Exiting.）
    if grep -q "event: end-file" "$log" 2>/dev/null; then
        pass "播放到 EOF (event: end-file)"
    elif grep -q "Exiting." "$log" 2>/dev/null; then
        pass "播放到 EOF (Exiting)"
    else
        fail "未到 EOF（无 end-file / Exiting）"
    fi

    # 4) 实际播放时长 = end-file - start-file，应与 m3u8 实算时长对得上（duration↔EOF）
    local t0 t1 el lo hi
    t0=$(grep -m1 "event: start-file" "$log" | awk '{print $2}')
    [ -z "$t0" ] && t0=$(grep -m1 "Opening http" "$log" | awk '{print $2}')
    t1=$(grep -m1 "event: end-file" "$log" | awk '{print $2}')
    [ -z "$t1" ] && t1=$(grep -m1 "Exiting." "$log" | awk '{print $2}')
    if [ -n "$t0" ] && [ -n "$t1" ] && [ -n "$calc_dur" ]; then
        el=$(awk -v a="$t0" -v b="$t1" 'function s(x){split(x,T,":");return T[1]*3600+T[2]*60+T[3]} BEGIN{printf "%.3f", s(b)-s(a)}')
        lo=$(awk -v d="$calc_dur" 'BEGIN{t=d*0.1+2; printf "%.3f", t}')
        hi=$(awk -v d="$calc_dur" 'BEGIN{t=d*0.15+2; printf "%.3f", t}')
        if awk -v a="$el" -v b="$calc_dur" -v lo="$lo" -v hi="$hi" 'BEGIN{exit !(a>=b-lo && a<=b+hi)}'; then
            pass "实际播放 $el s = m3u8 时长 $calc_dur（容差 [$lo,$hi]），duration 与 EOF 对上"
        else
            fail "实际播放 $el s 偏离 m3u8 时长 $calc_dur（容差 [$lo,$hi]）—— 可能丢分段/未播完"
        fi
    else
        fail "无法测算实际播放时长（缺 start-file/end-file 或 m3u8）"
    fi

    # 5) A/V 不同步
    local ndes
    ndes=$(grep -c 'desynchronisation' "$log" || true)
    if [ "$ndes" = "0" ]; then pass "A/V 不同步告警 = 0"; else fail "A/V 不同步告警 = $ndes"; fi

    # 6) 音频 PTS 真回退（后值 < 前值）
    local back
    back=$(grep -oE 'Invalid audio PTS: [0-9.]+ -> [0-9.]+' "$log" 2>/dev/null |
        awk '{if ($6 < $4) n++} END{print n+0}')
    if [ "$back" = "0" ]; then pass "音频 PTS 真回退 = 0"; else fail "音频 PTS 真回退 = $back"; fi

    # 7) 硬解报错
    local nerr
    nerr=$(grep -c 'Error while decoding frame' "$log" || true)
    if [ "$nerr" = "0" ]; then pass "硬解报错 = 0"; else fail "硬解报错 = $nerr"; fi
}

total_fails=0
only="${1:-}"
for d in "$CASES_DIR"/p*; do
    d=$(basename "$d")
    [ -n "$only" ] && [ "$d" != "$only" ] && continue
    echo "== $d =="
    CASE_FAILS=0
    run_one "$d"
    if [ "$CASE_FAILS" -gt 0 ]; then
        echo "  -- 有 $CASE_FAILS 项失败，重试一次 --"
        CASE_FAILS=0
        run_one "$d"
    fi
    total_fails=$((total_fails + CASE_FAILS))
done
echo
if [ $total_fails -eq 0 ]; then echo "全部通过（pts_robustness 真机）"; else echo "失败 $total_fails 项（pts_robustness 真机）"; fi
exit $total_fails
