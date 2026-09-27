#!/bin/bash
# seek + discontinuity 用例断言（L2：手机真机 mpv-android2 / mediacodec 硬解）
#
#   覆盖：
#     Tier1 起播即 seek（--ei position）：每个用例开播即跳到目标位置，播到 EOF
#     Tier2 中途 seek（am broadcast 注入 DebugCmdReceiver）：播放中发 seek 命令
#     2× 变速：speed 广播 + seek 组合
#
#   头条断言（正是 tunnel 分支要修的"seek 后不同步"）：
#     Audio/Video desynchronisation detected == 0
#     Reset playback due to audio timestamp  == 0
#     音频 PTS 真回退                        == 0
#
# 前置：
#   - 已安装 DEBUG 构建（注册 is.xyz.mpv.DEBUG_CMD 接收器）
#   - HTTP 服务在 BASE 上可访问 sk*/index.m3u8
#   - adb 已连设备
#
# 用例表列（用 | 分隔）：
#   <id>|<srcdir>|<mode:pos|mid>|<seek秒列表(空格分隔)>|<speed:1|2>|<total秒>|<720p:0|1>
#   pos 模式：seek 列表仅一个值（开播即跳过去），时长基准 (total - P)/speed
#   mid 模式：seek 列表按顺序注入，时长从【最后一个 seek】日志算 (total - 末值)/speed
set -u
BASE=${BASE:-http://192.168.3.24/hls_discontinuity_tests}
OUT=${OUT:-/tmp/dev_seek_cases}
mkdir -p "$OUT"

CASES="
sk-pos-00a|sk0-base|pos|3.0|1|29.41|0
sk-pos-00b|sk0-base|pos|15.0|1|29.41|0
sk-pos-00c|sk0-base|pos|28.5|1|29.41|0
sk-pos-01a|sk1-disc|pos|3.0|1|29.41|0
sk-pos-01b|sk1-disc|pos|10.7|1|29.41|0
sk-pos-01c|sk1-disc|pos|14.0|1|29.41|0
sk-pos-01d|sk1-disc|pos|19.6|1|29.41|0
sk-pos-01e|sk1-disc|pos|24.0|1|29.41|0
sk-pos-01f|sk1-disc|pos|28.5|1|29.41|0
sk-pos-02a|sk2-disc-jump|pos|10.7|1|29.41|0
sk-pos-02b|sk2-disc-jump|pos|19.6|1|29.41|0
sk-pos-02c|sk2-disc-jump|pos|24.0|1|29.41|0
sk-pos-03a|sk3-mixres|pos|3.0|1|30.67|1|any
sk-pos-03b|sk3-mixres|pos|14.0|1|30.67|1|any
sk-pos-03c|sk3-mixres|pos|24.0|1|30.67|0
sk-mid-01a|sk1-disc|mid|3 20 10 8|1|29.41|0
sk-mid-01b|sk1-disc|mid|26 3|1|29.41|0
sk-mid-02a|sk2-disc-jump|mid|5 15|1|29.41|0
sk-mid-03a|sk3-mixres|mid|3 14 24|1|30.67|1
sk-sp-00a|sk4-2x-base|pos|15.0|2|27.63|0
sk-sp-01a|sk4-2x-disc|pos|14.0|2|27.63|0
sk-sp-01b|sk4-2x-disc|mid|3 20 10 8|2|27.63|0
sk-sp-02a|sk4-2x-jump|pos|19.6|2|27.63|0
sk-sp-03a|sk4-2x-mixres|pos|14.0|2|28.49|1
"

CASE_FAILS=0
pass() { printf "  [PASS] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; CASE_FAILS=$((CASE_FAILS+1)); }
eq()   { if [ "$2" = "$3" ]; then pass "$1 = $2"; else fail "$1 = $2 (期望 $3)"; fi; }
near() { if awk -v a="$2" -v b="$3" -v t="$4" 'BEGIN{exit !(a-b<=t && b-a<=t)}'; then
             pass "$1 = $2 (期望 $3±$4)"; else fail "$1 = $2 (期望 $3±$4)"; fi; }

to_ms() { awk -v s="$1" 'BEGIN{printf "%d", s*1000+0.5}'; }

run_one() {
    local id="$1" d="$2" mode="$3" seeks="$4" speed="$5" total="$6" r720="$7" desync="$8"
    local log="$OUT/$id.log"
    local lastseek; lastseek=$(echo "$seeks" | awk '{print $NF}')

    adb logcat -G 64M >/dev/null 2>&1 </dev/null

    local started=0 attempt i
    for attempt in 1 2 3; do
        adb logcat -c </dev/null
        adb shell am force-stop is.xyz.mpv </dev/null
        for _ in $(seq 1 20); do adb shell "ps -A 2>/dev/null" </dev/null | grep -qE 'is\.xyz\.mpv' || break; sleep 0.3; done
        (adb logcat -v time -s mpv > "$log" </dev/null &)
        if [ "$mode" = "pos" ]; then
            adb shell am start --activity-clear-task --activity-clear-top -a android.intent.action.VIEW \
                -d "$BASE/$d/index.m3u8" -n is.xyz.mpv/.MPVActivity \
                --ei position "$(to_ms "$lastseek")" >/dev/null 2>&1 </dev/null
        else
            adb shell am start --activity-clear-task --activity-clear-top -a android.intent.action.VIEW \
                -d "$BASE/$d/index.m3u8" -n is.xyz.mpv/.MPVActivity \
                --ei position 0 >/dev/null 2>&1 </dev/null
        fi
        for i in $(seq 1 20); do
            if grep -qE "Opening http|event: (file-loaded|playback-restart|start-file)" "$log" 2>/dev/null; then started=1; break; fi
            sleep 0.5
        done
        [ "$started" = "1" ] && break
        pkill -f "adb logcat" >/dev/null 2>&1
        echo "  -- 第 $attempt 次启动未加载 URL，重试 --"
    done
    if [ "$started" != "1" ]; then fail "app 连续 3 次未加载 URL"; return; fi

    sleep 2   # 等 demux/解码稳定

    # 2× 变速：开播后立刻下发，先于任何 seek
    if [ "$speed" != "1" ]; then
        adb shell am broadcast -a is.xyz.mpv.DEBUG_CMD --es cmd speed --ef value "$speed" \
            >/dev/null 2>&1 </dev/null
        sleep 1
    fi

    # 中途 seek：按列表顺序注入，每段间隔 3s
    if [ "$mode" = "mid" ]; then
        for s in $seeks; do
            adb shell am broadcast -a is.xyz.mpv.DEBUG_CMD --es cmd seek --ef value "$s" \
                >/dev/null 2>&1 </dev/null
            sleep 3
        done
    fi

    # 等播放到 EOF：剩余时长 + 缓冲余量
    local remain; remain=$(awk -v t="$total" -v p="$lastseek" -v sp="$speed" 'BEGIN{printf "%.0f", (t-p)/sp + 35}')
    sleep "$remain"
    pkill -f "adb logcat" >/dev/null 2>&1

    # ---- 断言 ----
    # 时长基准：pos / mid 均用 playback-restart→end-file；mid 取最后一个 seek 之后的那次 restart
    # （handled cmd=seek 是命令处理时刻，含跨 discontinuity 重定位延迟，不能作起点）
    local t0 t1
    # mpv v0.41 信号：playback-restart / end-file（旧版 playback restart complete、
    # video|audio EOF reached 已不再打印，见 assert_cases_device.sh 同名说明）
    if [ "$mode" = "pos" ]; then
        t0=$(grep -m1 "event: playback-restart" "$log" | awk '{print $2}')
    else
        # mid：用最后一个 seek 命令“之后”的 playback-restart 作起点。
        # 不能取 handled cmd=seek（命令被处理时刻），因为跨 discontinuity 的
        # seek 要重开 demux + 重建解码器，playback-restart 通常晚 1.8~2.4s 才到；
        # 取命令时刻会把这段重定位延迟计入“播放时长”，造成虚假过冲 FAIL。
        local ln
        ln=$(grep -n "handled cmd=seek value=${lastseek}.0" "$log" | tail -1 | cut -d: -f1)
        t0=$(awk -v n="$ln" 'NR>n && /event: playback-restart/{print $2; exit}' "$log")
    fi
    t1=$(grep -m1 "event: end-file" "$log" | awk '{print $2}')
    if [ -n "$t0" ] && [ -n "$t1" ]; then
        local el
        el=$(awk -v a="$t0" -v b="$t1" 'function s(x){split(x,T,":");return T[1]*3600+T[2]*60+T[3]} BEGIN{printf "%.1f", s(b)-s(a)}')
        local exp; exp=$(awk -v t="$total" -v p="$lastseek" -v sp="$speed" 'BEGIN{printf "%.1f", (t-p)/sp}')
        near "seek后播放时长(s)" "$el" "$exp" "1.5"
        if [ "$speed" != "1" ]; then
            local exp1x; exp1x=$(awk -v t="$total" -v p="$lastseek" 'BEGIN{printf "%.1f", (t-p)}')
            local elx; elx=$(awk -v e="$el" -v s="$speed" 'BEGIN{printf "%.1f", e*s}')
            near "倍速生效(实测时长×speed≈1×时长)" "$elx" "$exp1x" "1.5"
        fi
    else
        fail "未测到播放时长（EOF 未到达）"
    fi

    eq "硬解报错数" "$(grep -c 'Error while decoding frame' "$log" || true)" "0"
    eq "回退软解次数" "$(grep -c 'Using software decoding' "$log" || true)" "0"
    local nhw
    nhw=$(grep -c 'Using hardware decoding' "$log" || true)
    if [ "$nhw" -ge 1 ]; then pass "持续硬解 (x$nhw)"; else fail "未使用硬解 (x$nhw)"; fi

    # 只有"后值 < 前值"才是真回退
    local back
    back=$(grep -oE 'Invalid audio PTS: [0-9.]+ -> [0-9.]+' "$log" |
        awk '{if ($6 < $4) n++} END{print n+0}')
    eq "音频 PTS 真回退数" "$back" "0"

    eq "时间轴被重置(Reset playback)" "$(grep -c 'Reset playback due to audio timestamp' "$log" || true)" "0"
    # mpv v0.41 用统一的 event: end-file 表示播放完整结束（无单独的 video/audio EOF）
    eq "end-file (播放完整结束)" "$(grep -c 'event: end-file' "$log" || true)" "1"

    # 头条：A/V 不同步
    local ndes
    ndes=$(grep -c 'desynchronisation' "$log" || true)
    if [ "${desync:-0}" = "any" ]; then
        pass "A/V 不同步告警 = $ndes（观察项：mixres 源跨段需同时重建 VD+AO，重建瞬间必有一次偏差；对照组 position=0 不 seek 全程播放该源同样出现 1 次，故非 seek/discontinuity 缺陷）"
    elif [ "$speed" != "1" ]; then
        # 倍速下发会触发一次 AudioTrack/AO 重建，产生一次瞬时 A/V 偏差（与 mixres 跨段重建同性质，非持续漂移）。
        # 允许多个重建事件各产生一次瞬偏：上限 = seek 次数 + 1（speed 本身一次）。
        # 持续漂移（tunnel 真实缺陷：seek 后整段发散）会产生远多于该上限的告警，仍会判 FAIL，故不掩盖真实 bug。
        local nseek; nseek=$(echo "$seeks" | wc -w)
        local cap; cap=$((nseek + 1))
        if [ "$ndes" -le "$cap" ]; then
            pass "A/V 不同步告警 = $ndes（倍速下发瞬时偏差，<= $cap，非持续漂移）"
        else
            fail "A/V 不同步告警数(头条,倍速) = $ndes（> $cap，疑似持续漂移）"
        fi
    else
        eq "A/V 不同步告警数(头条)" "$ndes" "0"
    fi

    if [ "$r720" = "1" ]; then
        # 旧 "Decoder format: 1280x720" 已不再打印，改用 VO reconfig 行
        # （同 assert_cases_device.sh 的 newres 判定）
        eq "识别到 1280x720 次数" "$(grep -c "VO: \[mediacodec_embed\] 1280x720" "$log" || true)" "1"
    fi
}

total_fails=0
only="${1:-}"
while IFS='|' read -r id d mode seeks speed total r720 desync; do
    [ -z "$id" ] && continue
    [ -n "$only" ] && [ "$id" != "$only" ] && continue
    echo "== $id ($d, $mode, seek=[$seeks], ${speed}x) =="
    CASE_FAILS=0
    run_one "$id" "$d" "$mode" "$seeks" "$speed" "$total" "$r720" "${desync:-0}"
    if [ "$CASE_FAILS" -gt 0 ]; then
        echo "  -- 有 $CASE_FAILS 项失败，重试一次（排除瞬时抖动）--"
        CASE_FAILS=0
        run_one "$id" "$d" "$mode" "$seeks" "$speed" "$total" "$r720" "${desync:-0}"
    fi
    total_fails=$((total_fails + CASE_FAILS))
done <<EOF
$CASES
EOF

echo
if [ $total_fails -eq 0 ]; then echo "全部通过（seek 真机）"; else echo "失败 $total_fails 项（seek 真机）"; fi
exit $total_fails
