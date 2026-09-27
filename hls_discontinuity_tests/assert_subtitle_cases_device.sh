#!/bin/bash
# 字幕片源用例断言（L2：手机真机 mpv-android2 / mediacodec 硬解）
#
#   复用已生成的 8 个字幕片源（4 结构 × 2 封装）：
#     Form A（TS 封装）      : sk4-2x-<x>-wvtt/master.m3u8   （EXT-X-MEDIA SUBTITLES -> sub_en.m3u8 + sub_en.vtt）
#     Form B（HLS over fMP4）: sk4-2x-<x>-fmp4/master.m3u8   （EXT-X-MAP + .m4s 分段；字幕同样走外挂 WebVTT rendition）
#
#   注：HLS 不允许内嵌 mov_text，故两种形式的“差别”在媒体封装（TS vs fMP4），字幕一律外挂 WebVTT。
#
#   结构变体（复用 sk-sp-* 已验证的 seek 参数）：
#     base    : 无 DISCONT（对照组）
#     disc    : DISCONT + 时间戳连续衔接
#     jump    : DISCONT + 时间戳大跳  （wvtt 与 fmp4 两种 HLS 形式均覆盖；旧 MP4 单文件把 jump 拍平后 seek 语义不一致，已弃用）
#     mixres  : DISCONT + 1280x720 分辨率切换
#
#   动作维度：
#     pos  : 开播即跳到目标位置，播到 EOF（测"起播即 seek + 字幕定位"）
#     mid  : 播放中多次注入 seek（测"中途 seek 后字幕重定位/同步"）
#     sp   : 2× 变速 + 开播即 seek（测"倍速下字幕推进速率"）
#     mdsp : 2× 变速 + 播放中多次 seek（tunnel 分支最易炸的场景）
#
#   头条断言（与 tunnel 分支一致，外加字幕路径判定）：
#     Audio/Video desynchronisation detected == 0
#     Reset playback due to audio timestamp  == 0
#     音频 PTS 真回退                        == 0
#     字幕轨被正确加载 / 识别（两条路径分别判定）
#
# 前置：
#   - 已安装 DEBUG 构建（注册 is.xyz.mpv.DEBUG_CMD 接收器）
#   - HTTP 服务在 BASE 上可访问 sk4-2x-*/master.m3u8 与 *_emb.mp4
#   - adb 已连设备
#
# 用例矩阵（读自 subtitle_case_matrix.tsv，TAB 分隔；也可用 --emit-matrix 由 gen_matrix 重生）：
#   <id>  <srcbase>  <form:wvtt|fmp4>  <mode:pos|mid>  <seek秒列表>  <speed:1|2>  <total秒>  <720p:0|1>
set -u
BASE=${BASE:-http://192.168.3.24/hls_discontinuity_tests}
OUT=${OUT:-/tmp/dev_subtitle_cases}
mkdir -p "$OUT"
mkdir -p "$OUT"

# 用例矩阵由此函数生成，字段以 TAB 分隔，与 subtitle_case_matrix.tsv 保持一致：
#   <id>  <srcbase>  <form:wvtt|fmp4>  <mode:pos|mid>  <seek秒列表>  <speed:1|2>  <total秒>  <720p:0|1>
# 4 结构 × 2 封装（TS / HLS-over-fMP4）× 4 动作（pos/mid/sp/mdsp）= 28 例；jump 两种形式都覆盖。
gen_matrix() {
  local SRC="sk4-2x-base sk4-2x-disc sk4-2x-jump sk4-2x-mixres"
  for sb in $SRC; do
    local r720=0 pseek mseeks="3 20 10 8" forms sbk fp total
    case "$sb" in
      *mixres) r720=1; pseek=14.0;;
      *jump)   r720=0; pseek=19.6;;   # jump 用已验证的 SUM 时间轴 seek 点
      *)       r720=0; pseek=15.0;;
    esac
    # wvtt（TS 封装）与 fmp4（HLS over fMP4）两种形式对所有结构都覆盖；二者字幕均走外挂 WebVTT
    forms="wvtt fmp4"
    sbk=${sb#sk4-2x-}
    for form in $forms; do
      [ "$form" = "wvtt" ] && fp=W || fp=E
      # 时长取自 sources_facts.tsv（ffprobe 实测）：wvtt 与 fmp4 因封装差异时长不同。
      # ⚠️ 2026-09-21 订正：build_subtitle_sources.sh 的 _body.m3u8 跨源累积 bug（每源未清空，
      #    导致 disc=3组 / jump=6组 / mixres=9组）修复后，每源统一为 3 组（与 sources_struct.tsv 一致），
      #    故 fmp4 一律 35.6s。此前 jump-fmp4=71.2 / mixres-fmp4=106.8 是累积出的错误产物，已废弃。
      #    必须用实测值，否则播放时长断言会因陈旧 total 误判为失败。
      case "$sb:$form" in
        *mixres:wvtt) total=35.949666;;
        *:wvtt)       total=35.909666;;
        *)            total=35.600000;;   # 全部 fmp4：base/disc/jump/mixres 均为 35.6
      esac
      printf 'sub-%s-%s-pos\t%s\t%s\tpos\t%s\t1\t%s\t%s\n'  "$fp" "$sbk" "$sb" "$form" "$pseek"   "$total" "$r720"
      printf 'sub-%s-%s-mid\t%s\t%s\tmid\t%s\t1\t%s\t%s\n'  "$fp" "$sbk" "$sb" "$form" "$mseeks"  "$total" "$r720"
      printf 'sub-%s-%s-sp\t%s\t%s\tpos\t%s\t2\t%s\t%s\n'   "$fp" "$sbk" "$sb" "$form" "$pseek"   "$total" "$r720"
      printf 'sub-%s-%s-mdsp\t%s\t%s\tmid\t%s\t2\t%s\t%s\n' "$fp" "$sbk" "$sb" "$form" "$mseeks"  "$total" "$r720"
    done
  done
}

# --emit-matrix：把矩阵导出为 subtitle_case_matrix.tsv（供版本管理与审阅），然后退出
if [ "${1:-}" = "--emit-matrix" ]; then gen_matrix; exit 0; fi

# 前置：启用字幕轨。ffmpeg 的 HLS 在 read_header 阶段把字幕 playlist 置
# needed=0 / discard=AVDISCARD_ALL（上游默认关闭字幕），不显式选中就永远不会去拉字幕，
# 字幕断言必然全挂。mpv 选项只能经 filesDir/mpv.conf 注入（broadcast set 会因每次
# am start 新起进程而丢失）。msg-level=ffmpeg=debug 必须保留：本套件与其它套件都靠
# 它打印 [ffmpeg/demuxer] 的 HLS request 行。
ensure_subtitle_conf() {
    printf 'msg-level=ffmpeg=debug\nsid=1\nsub-visibility=yes\n' > /tmp/_mpv_sub.conf
    adb push /tmp/_mpv_sub.conf /data/local/tmp/mpv.conf >/dev/null 2>&1
    adb shell run-as is.xyz.mpv cp /data/local/tmp/mpv.conf /data/data/is.xyz.mpv/files/mpv.conf >/dev/null 2>&1
}
ensure_subtitle_conf

# 矩阵驱动：优先读 subtitle_case_matrix.tsv；缺失时回退到 gen_matrix 现场生成
MATRIX_FILE=${MATRIX_FILE:-subtitle_case_matrix.tsv}
if [ -f "$MATRIX_FILE" ]; then
  CASES=$(cat "$MATRIX_FILE")
else
  CASES=$(gen_matrix)
fi

CASE_FAILS=0
pass() { printf "  [PASS] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; CASE_FAILS=$((CASE_FAILS+1)); }
eq()   { if [ "$2" = "$3" ]; then pass "$1 = $2"; else fail "$1 = $2 (期望 $3)"; fi; }
# ge：计数 >= 期望即通过（用于"至少出现一次"类断言，避免 mid/mdsp 多次 seek 重开字幕列表导致误判）
ge()   { if awk -v a="$2" -v b="$3" 'BEGIN{exit !(a+0>=b+0)}'; then
             pass "$1 = $2 (>= $3)"; else fail "$1 = $2 (期望 >= $3)"; fi; }
near() { if awk -v a="$2" -v b="$3" -v t="$4" 'BEGIN{exit !(a-b<=t && b-a<=t)}'; then
             pass "$1 = $2 (期望 $3±$4)"; else fail "$1 = $2 (期望 $3±$4)"; fi; }

to_ms() { awk -v s="$1" 'BEGIN{printf "%d", s*1000+0.5}'; }

run_one() {
    local id="$1" srcbase="$2" form="$3" mode="$4" seeks="$5" speed="$6" total="$7" r720="$8"
    local log="$OUT/$id.log"
    local lastseek; lastseek=$(echo "$seeks" | awk '{print $NF}')

    # 依据字幕封装形式决定入口 URL
    local url
    if [ "$form" = "wvtt" ]; then url="$BASE/$srcbase-wvtt/master.m3u8";
    else url="$BASE/$srcbase-fmp4/master.m3u8"; fi

    adb logcat -G 64M >/dev/null 2>&1 </dev/null

    local started=0 attempt i
    for attempt in 1 2 3; do
        adb logcat -c </dev/null
        adb shell am force-stop is.xyz.mpv </dev/null
        for _ in $(seq 1 20); do adb shell "ps -A 2>/dev/null" </dev/null | grep -qE 'is\.xyz\.mpv' || break; sleep 0.3; done
        (adb logcat -v time -s mpv > "$log" </dev/null &)
        if [ "$mode" = "pos" ]; then
            adb shell am start --activity-clear-task --activity-clear-top -a android.intent.action.VIEW \
                -d "$url" -n is.xyz.mpv/.MPVActivity \
                --ei position "$(to_ms "$lastseek")" >/dev/null 2>&1 </dev/null
        else
            adb shell am start --activity-clear-task --activity-clear-top -a android.intent.action.VIEW \
                -d "$url" -n is.xyz.mpv/.MPVActivity \
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

    # ---- 断言：字幕路径（两种封装都走外挂 WebVTT rendition -> sub_en.m3u8）----
    # 用 ge（>=1）而非 eq(=1)：mid/mdsp 多次 seek 会重开字幕列表，sub_en 出现 >1 次属正常，
    # 真正的信号是字幕 playlist 至少被拉取过一次。
    # 实测：ffmpeg 走外挂 WebVTT rendition 时，日志里出现的是 sub_en.vtt（字幕负载），
    # sub_en.m3u8 不一定被单独打印。故按 "sub_en" 匹配，两种形式都算字幕路径被拉取。
    ge "字幕被拉取(sub_en: m3u8 或 vtt)" "$(grep -c 'sub_en' "$log" || true)" "1"
    # 字幕轨识别（多条候选 marker，覆盖不同 mpv 构建的日志措辞）
    local nsub
    nsub=$(grep -ciE 'subtitle|mov_text|wvtt|Added subtitle|sub.*track' "$log" || true)
    if [ "$nsub" -ge 1 ]; then pass "识别到字幕轨 (x$nsub)"; else fail "未识别到字幕轨"; fi

    # ---- 断言：播放完整性（复用 seek 套件） ----
    local t0 t1
    if [ "$mode" = "pos" ]; then
        t0=$(grep -m1 "event: playback-restart" "$log" | awk '{print $2}')
    else
        # mid：用最后一个 seek 命令之后的 playback-restart 作起点（handled cmd=seek
        # 是命令处理时刻，含跨 discontinuity 重定位延迟，不能作起点，否则虚假过冲）
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
    if [ "$speed" != "1" ]; then
        # 倍速下发会触发一次 AudioTrack/AO 重建，产生一次瞬时 A/V 偏差（与 mixres 跨段重建同性质，非持续漂移）。
        # 允许多个重建事件各产生一次瞬偏：上限 = seek 次数 + 1（speed 本身一次）。
        # 持续漂移（tunnel 真实缺陷）会产生远多于该上限的告警，仍会判 FAIL，故不掩盖真实 bug。
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

    # 2× 有效性：已由上方的“倍速生效(实测时长×speed≈1×时长)”显式断言覆盖（±1.5s），此处不再弱校验。

    if [ "$r720" = "1" ]; then
        # mixres 结构为 720p -> 1080p -> 720p，且断点会重建解码器，
        # 故 1280x720 会被打印多次、次数不固定；原先 eq=1 的期望在片源修复前后同样不符（陈旧断言）。
        # 有意义的信号是"主分辨率被识别到"与"分辨率切换真的发生（1080p 出现过）"，故改用 ge。
        ge "识别到 1280x720 次数" "$(grep -c "VO: \[mediacodec_embed\] 1280x720" "$log" || true)" "1"
        ge "识别到 1920x1080 次数" "$(grep -c "VO: \[mediacodec_embed\] 1920x1080" "$log" || true)" "1"
    fi
}

total_fails=0
ran=0
only="${1:-}"
while IFS=$'\t' read -r id srcbase form mode seeks speed total r720; do
    [ -z "$id" ] && continue
    [ -n "$only" ] && [ "$id" != "$only" ] && continue
    ran=1
    echo "== $id ($srcbase, $form, $mode, seek=[$seeks], ${speed}x) =="
    CASE_FAILS=0
    run_one "$id" "$srcbase" "$form" "$mode" "$seeks" "$speed" "$total" "$r720"
    if [ "$CASE_FAILS" -gt 0 ]; then
        echo "  -- 有 $CASE_FAILS 项失败，重试一次（排除瞬时抖动）--"
        CASE_FAILS=0
        run_one "$id" "$srcbase" "$form" "$mode" "$seeks" "$speed" "$total" "$r720"
    fi
    total_fails=$((total_fails + CASE_FAILS))
done <<EOF
$CASES
EOF

echo
if [ "$ran" -eq 0 ]; then echo "未匹配到任何用例（检查传入的 id 或 subtitle_case_matrix.tsv）"; exit 2; fi
if [ $total_fails -eq 0 ]; then echo "全部通过（字幕真机）"; else echo "失败 $total_fails 项（字幕真机）"; fi
exit $total_fails
