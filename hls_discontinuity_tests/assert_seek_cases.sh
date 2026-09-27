#!/bin/bash
# seek + discontinuity 用例断言（L1：demuxer / 源正确性，host 全自动）
#
#   验证 SK0..SK3 四个源本身的构造是否正确：
#     - dts 不回退
#     - 总时长 == 各段之和
#     - 视频帧数 / 音频包数 == 各段之和（拼接不丢包）
#     - DISCONTINUITY 通告数 == 断点数 × 2
#     - SK3 额外：解码时能识别到 1280x720 的 reinit
#
# 注意：必须用旧版 ffprobe（/home/lck/work/build/ffmpeg-hls-disc/ffprobe），
#       新版 ffprobe 不再在 packet json 里输出 "Discontinuity" 字段。
set -u
FP=${FP:-/home/lck/work/build/ffmpeg-hls-disc/ffprobe}
FF=${FF:-/home/lck/work/build/ffmpeg-hls-disc/ffmpeg}
cd "$(cd "$(dirname "$0")" && pwd)"

fails=0
pass() { printf "  \033[32m[PASS]\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m[FAIL]\033[0m %s\n" "$1"; fails=$((fails+1)); }
eq()   { if [ "$2" = "$3" ]; then pass "$1 = $2"; else fail "$1 = $2 (期望 $3)"; fi; }
near() { if awk -v a="$2" -v b="$3" -v t="$4" 'BEGIN{exit !(a-b<=t && b-a<=t)}'; then
            pass "$1 = $2 (期望 $3±$4)"; else fail "$1 = $2 (期望 $3±$4)"; fi; }

# 期望表：<源> <断点数> <期望时长s> <是否出现新分辨率(1/0)>
EXPECT="
sk0-base       0 29.41 0
sk1-disc       2 29.41 0
sk2-disc-jump  2 29.41 0
sk3-mixres     2 30.67 1
"

# 取 m3u8 里列出的所有段文件名
segs_of() { # segs_of <m3u8>  -> 每行一个段
    grep -v '^#' "$1" | grep -v '^$' | sed 's/,*$//'
}

while read -r d ndisc dexp newres; do
    [ -z "$d" ] && continue
    m3u8="$d/index.m3u8"
    echo "== $d =="

    # 1) dts 不回退
    back=$($FP -v error -show_entries packet=stream_index,dts -of csv=p=0 "$m3u8" 2>/dev/null |
        awk -F, '{if($2=="N/A")next; if(p[$1]!="" && $2<p[$1]) b++; p[$1]=$2} END{print b+0}')
    eq "dts 回退数" "$back" "0"

    # 2) 总时长 == 各段之和
    dur=$($FP -v error -show_entries format=duration -of csv=p=0 "$m3u8" 2>/dev/null | head -1)
    near "总时长(s)" "$(printf '%.2f' "$dur")" "$dexp" "0.30"

    # 3) 帧数 / 包数 == 各段之和（拼接不丢包）
    #    整体读（playlist 当作一个文件）
    vf=$($FP -v error -select_streams v -count_frames -show_entries stream=nb_read_frames \
        -of default=nw=1:nk=1 "$m3u8" 2>/dev/null | head -1)
    ap=$($FP -v error -select_streams a -count_packets -show_entries stream=nb_read_packets \
        -of default=nw=1:nk=1 "$m3u8" 2>/dev/null | head -1)
    #    各段独立求和
    svf=0; sap=0
    while read -r s; do
        [ -z "$s" ] && continue
        svf=$((svf + $($FP -v error -select_streams v -count_frames -show_entries stream=nb_read_frames \
            -of default=nw=1:nk=1 "$d/$s" 2>/dev/null | head -1)))
        sap=$((sap + $($FP -v error -select_streams a -count_packets -show_entries stream=nb_read_packets \
            -of default=nw=1:nk=1 "$d/$s" 2>/dev/null | head -1)))
    done < <(segs_of "$m3u8")
    # 视频帧 sum 断言：仅对单分辨率源可靠。
    # 跨分辨率 playlist 下 ffprobe 的 nb_read_frames 会漏掉中间段（HLS reinit 测量假象），
    # 该场景的视频完整性由 device L2 的 video EOF 真实验证，此处只做信息输出。
    if [ "$newres" = "0" ]; then
        eq "视频帧数(总和校验)" "$vf" "$svf"
    else
        printf "  \033[33m[INFO]\033[0m 视频帧数 整playlist=%s 各段和=%s（跨分辨率 HLS 测量假象，跳过严格比对，见 device L2）\n" "$vf" "$svf"
    fi
    eq "音频包数(总和校验)" "$ap" "$sap"

    # 4) DISCONTINUITY 通告数 == 断点数 × 2
    nnotice=$($FP -v error -show_packets -of json "$m3u8" 2>/dev/null | grep -c '"Discontinuity"' || true)
    eq "DISCONT 通告条数" "$nnotice" "$((ndisc * 2))"

    # 5) SK3：解码识别到 1280x720 的 reinit
    if [ "$newres" = "1" ]; then
        got=$($FF -v debug -i "$m3u8" -f null - 2>&1 | grep -c "Reinit context to 1280x720" || true)
        if [ "$got" -ge 1 ]; then pass "识别到 1280x720 reinit (x$got)"
        else fail "未出现 Reinit context to 1280x720（分辨率变化没被识别）"; fi
    fi
done <<EOF
$EXPECT
EOF

echo
if [ $fails -eq 0 ]; then echo "全部通过 (seek L1)"; else echo "失败 $fails 项 (seek L1)"; fi
exit $fails
