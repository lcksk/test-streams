#!/bin/bash
# fMP4 + EXT-X-DISCONTINUITY 截断回归用例（L1：主机 ffprobe，无需真机）
#
# 背景（实测发现）：
#   ffmpeg hls 解复用器在 discontinuity 处为每个 group 重建 subdemuxer；
#   TS 组能正常续读，但 **fMP4 组会被截断**：带断点的 fMP4 片源一律只解出
#   250 个视频包 / 末包 ~10.06s，而无断点的 fMP4 与全部 TS 片源都是 890 包 / ~35.9s。
#   该截断在主机 ffprobe 上 100% 确定性复现，且与真机实测（disc-fmp4 只播 9.99s）吻合。
#
# 判据（不变量）：
#   任何一个片源，无论封装(TS/fMP4)与断点数量，都应解出完整媒体：
#     - 视频包数 >= MIN_PACKETS (800)
#     - 末包 PTS 折合秒数 >= MIN_SECONDS (30)
#
# 状态（2026-09-21 更新）：fMP4 截断已修复，本脚本 8/8 全绿。
#   修复 = ① t1（`7f9646defb`，给带 init_section 的组也重建子解复用器）
#         ② 片源合规化（build_subtitle_sources.sh 的 _body.m3u8 跨源累积 bug 修复后
#            每源统一 3 组；且每个 EXT-X-MAP 变更前都插 DISCONT，符合 RFC 8216 §4.3.2.3）。
#
# ⚠️ 判据"末包 PTS >= 30s"只在**含 discontinuity patch（会 rebase 时间戳）**的构建下成立：
#    用不含 patch 的上游 ffprobe 跑，fMP4 各组 tfdt=0 且不 rebase，末包仅 ~7.46s，
#    会被误判为 FAIL（包数其实仍是 890，片源无损）。
#
# 用法：
#   FP=<ffprobe> bash assert_fmp4_discontinuity.sh
#   默认 FP=/tmp/ffreview/ffprobe —— out-of-tree 构建的含 t1 版本（buildscripts/deps/ffmpeg）。
#   /tmp 被清理后需重建：
#     mkdir -p /tmp/ffreview && cd /tmp/ffreview && \
#     <mpv-android2>/buildscripts/deps/ffmpeg/configure --prefix=/tmp/ffreview/install --disable-doc && \
#     make -j8 ffprobe
set -u

FP=${FP:-/tmp/ffreview/ffprobe}
SRCDIR=${SRCDIR:-/home/lck/work/webroot/hls_discontinuity_tests}
MIN_PACKETS=${MIN_PACKETS:-800}
MIN_SECONDS=${MIN_SECONDS:-30}
TB=${TB:-90000}   # mpeg-ts / fmp4 视频时基

SOURCES="sk4-2x-base-wvtt sk4-2x-disc-wvtt sk4-2x-jump-wvtt sk4-2x-mixres-wvtt \
         sk4-2x-base-fmp4 sk4-2x-disc-fmp4 sk4-2x-jump-fmp4 sk4-2x-mixres-fmp4"

fails=0
printf '%-22s %8s %10s %10s %8s\n' 片源 DISCONT 视频包数 末包秒 判定

for d in $SOURCES; do
    dir="$SRCDIR/$d"
    if [ ! -d "$dir" ]; then printf '%-22s %8s %10s %10s %8s\n' "$d" - - - 'SKIP'; continue; fi

    # 断点数取自媒体 playlist
    vp="$dir/index.m3u8"
    [ -f "$vp" ] || vp=$(ls "$dir"/*.m3u8 2>/dev/null | grep -v master | grep -v sub_en | head -1)
    discont=$(grep -c 'EXT-X-DISCONTINUITY' "$vp" 2>/dev/null || echo 0)

    url="$dir/master.m3u8"
    [ -f "$url" ] || url="$vp"

    pkts=$($FP -v error -select_streams v:0 -show_entries packet=pts -of csv=p=0 "$url" 2>/dev/null |
           grep -c . || true)
    last=$($FP -v error -select_streams v:0 -show_entries packet=pts -of csv=p=0 "$url" 2>/dev/null |
           grep . | tail -1 | tr -d ',' || true)
    sec=$(awk -v p="${last:-0}" -v tb="$TB" 'BEGIN{printf "%.2f", (p+0)/tb}')

    if [ "${pkts:-0}" -ge "$MIN_PACKETS" ] &&
       awk -v s="$sec" -v m="$MIN_SECONDS" 'BEGIN{exit !(s+0 >= m+0)}'; then
        verdict=PASS
    else
        verdict=FAIL
        fails=$((fails+1))
    fi
    printf '%-22s %8s %10s %10s %8s\n' "$d" "$discont" "${pkts:-0}" "$sec" "$verdict"
done

echo
if [ "$fails" -eq 0 ]; then
    echo "全部通过：fMP4 带断点未被截断（$MIN_PACKETS 包 / ${MIN_SECONDS}s 门槛）"
    exit 0
fi
echo "失败 $fails 项：fMP4 + discontinuity 被截断（期望 >= $MIN_PACKETS 包 且 >= ${MIN_SECONDS}s）"
exit "$fails"
