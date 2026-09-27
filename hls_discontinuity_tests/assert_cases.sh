#!/bin/bash
# HLS discontinuity 用例断言脚本（L1：demuxer / 播放器可观测行为，全自动）
#
#   ./assert_cases.sh            # 全部用例
#   ./assert_cases.sh case05     # 只跑指定用例
#
# 期望值来自各分片单独测量的和（见期望表），判据见每个用例的 EXPECT.md。
set -u
FP=${FP:-/home/lck/work/build/ffmpeg-hls-disc/ffprobe}
FF=${FF:-/home/lck/work/build/ffmpeg-hls-disc/ffmpeg}
cd "$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf "  \033[32m[PASS]\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m[FAIL]\033[0m %s\n" "$1"; fails=$((fails+1)); }
eq()   { if [ "$2" = "$3" ]; then pass "$1 = $2"; else fail "$1 = $2 (期望 $3)"; fi; }
near() { # near <名> <实测> <期望> <容差>
    if awk -v a="$2" -v b="$3" -v t="$4" 'BEGIN{exit !(a-b<=t && b-a<=t)}'; then
        pass "$1 = $2 (期望 $3±$4)"
    else
        fail "$1 = $2 (期望 $3±$4)"
    fi
}

# 期望表：<用例> <断点数> <视频帧> <音频包> <时长s> <是否出现新分辨率(1/0):新分辨率串>
EXPECT="
case01-fmt-head      1 1019 1665 38.85 1:640x368
case02-fmt-mid       2 1019 1665 38.85 1:640x368
case03-fmt-tail      1 1019 1665 38.85 1:640x368
case04-video-only    1  564  881 20.59 1:640x368
case05-audio-only    1  500  648 20.19 0:-
case06-audio-head    1  955 1432 38.46 0:-
case07-ts-jump-fwd   1  705 1215 28.34 0:-
case08-ts-jump-back  1  705 1215 28.34 0:-
case09-ts-restart    1  705 1215 28.34 0:-
case10-ts-only       2  890 1533 35.80 0:-
case11-multi-disc    3 1003 1728 40.32 0:-
case12-fmt-and-ts    1  564  881 20.59 1:640x368
case13-disc-at-start 0  705 1215 28.34 0:-
case14-disc-every-ts-fwd   3 1003 1728 40.32 0:-
case15-disc-every-ts-alt   3 1003 1728 40.32 0:-
case16-disc-every-fmt-alt  3 1333 2115 49.36 1:640x368
case17-disc-every-audio-alt 3 1205 1649 48.58 0:-
case18-cross-all           3 1269 1882 48.97 1:640x368
case19-disc-every-plain    5 1645 2834 66.14 0:-
case20-dup-repeat-disc     2  750 1293 30.22 0:-
case21-dup-repeat-nodisc   0  750 1293 30.22 0:- any
case22-dup-repeat-offset   2  750 1293 30.22 0:-
case23-dup-interleave-disc 3 1410 2430 56.68 0:-
case24-dup-then-fmt        2  878 1331 31.10 1:640x368
case25-dup-mixed-ts        2  750 1293 30.22 0:-
"

only="${1:-}"
while read -r d ndisc vexp aexp dexp newres expback; do
    [ -z "$d" ] && continue
    [ -n "$only" ] && [ "$d" != "$only" ] && continue
    expback=${expback:-0}
    m3u8="$d/index.m3u8"
    echo "== $d =="

    # 1) 时间轴：dts 不得回退（"any" = 观察项：未打 DISCONT 的重复分片，预期会有回退）
    back=$($FP -v error -show_entries packet=stream_index,dts -of csv=p=0 "$m3u8" 2>/dev/null |
        awk -F, '{if($2=="N/A")next; if(p[$1]!="" && $2<p[$1]) bad++; p[$1]=$2} END{print bad+0}')
    if [ "$expback" = "any" ]; then
        if [ "$back" -gt 0 ]; then pass "dts 回退数 = $back（观察项：无标记，预期有回退）"
        else fail "dts 回退数 = 0（对照设计应出现回退）"; fi
    else
        eq "dts 回退数" "$back" "0"
    fi

    # 2) 总时长 = 各段之和（rebase 后不留空洞也不重叠）
    dur=$($FP -v error -show_entries format=duration -of csv=p=0 "$m3u8" 2>/dev/null | head -1)
    near "总时长(s)" "$(printf '%.2f' "$dur")" "$dexp" "0.30"

    # 3) 完整性：视频帧数 / 音频包数 = 各段之和（不丢包）
    vf=$($FP -v error -select_streams v -count_frames -show_entries stream=nb_read_frames \
        -of default=nw=1:nk=1 "$m3u8" 2>/dev/null | head -1)
    ap=$($FP -v error -select_streams a -count_packets -show_entries stream=nb_read_packets \
        -of default=nw=1:nk=1 "$m3u8" 2>/dev/null | head -1)
    eq "视频帧数" "$vf" "$vexp"
    eq "音频包数" "$ap" "$aexp"

    # 4) 通告条数 = 断点数 × 2（每个断点每条流一条）
    nnotice=$($FP -v error -show_packets -of json "$m3u8" 2>/dev/null | grep -c '"Discontinuity"' || true)
    eq "通告条数" "$nnotice" "$((ndisc * 2))"

    # 5) 格式变化是否真的被识别：期望出现新分辨率的 reinit
    want=${newres%%:*}
    res=${newres#*:}
    if [ "$want" = "1" ]; then
        got=$($FF -v debug -i "$m3u8" -f null - 2>&1 | grep -c "Reinit context to $res" || true)
        if [ "$got" -ge 1 ]; then pass "识别到新分辨率 $res (x$got)"
        else fail "未出现 Reinit context to $res（格式变化没被识别）"; fi
    else
        # 纯时间戳/纯音频用例：不应出现"别的分辨率"的 reinit
        other=$($FF -v debug -i "$m3u8" -f null - 2>&1 |
            grep -oE "Reinit context to [0-9]+x[0-9]+" | sort -u | grep -v "1280x720" | wc -l)
        eq "无新分辨率 reinit" "$other" "0"
    fi
done <<EOF
$EXPECT
EOF

echo
if [ $fails -eq 0 ]; then echo "全部通过 (L1)"; else echo "失败 $fails 项 (L1)"; fi
exit $fails
