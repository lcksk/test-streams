#!/bin/bash
# 构造 seek + discontinuity 测试源（SK0..SK3），全部 -c copy，不重编码。
#
# 素材（同规格：7680x4320 / 30fps / HE-AAC 48000 stereo）：
#   hls_dump_file_6.ts  10.562s  start 57.671
#   hls_dump_file_7.ts   8.809s  start 68.124
#   hls_dump_file_8.ts  10.038s  start 76.828
# 可用 720p 段：rmdmy/009.ts（1280x720 h264 / aac 44100 stereo）
#
# 生成物：
#   sk0-base/     6+7+8 连续拼接成单文件，无 DISCONT（seek 基线）
#   sk1-disc/     6 #D 7 #D 8，DISCONT + 时间戳连续
#   sk2-disc-jump/ 6 #D 7(+60s) #D 8(+120s)，DISCONT + 时间戳大跳
#   sk3-mixres/   8K(6) #D 720p(009) #D 8K(8)，分辨率交替 + DISCONT
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
FF=${FF:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffmpeg}
FP=${FP:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffprobe}
S6=hls_dump_file_6.ts
S7=hls_dump_file_7.ts
S8=hls_dump_file_8.ts
S720=rmdmy/009.ts

# rebase <src> <start_seconds> <out>
#   把输出时间轴的起点设为 <start_seconds>（必须为正值！负数会被 mpegts 夹紧成 0，
#   导致各段都归零→DISCONTINUITY 后时间戳递减→seek 失效）。
#   -muxdelay 0 -muxpreload 0 让 -output_ts_offset 精确生效（否则会被 muxer 默认回绕叠加）。
rebase() {
    $FF -y -i "$1" -c copy -muxdelay 0 -muxpreload 0 -output_ts_offset "$2" -f mpegts "$3" >/dev/null 2>&1
}
m3u8_disc() { # m3u8_disc <dir> <seg1> <seg2> <seg3>  (每段之间插 DISCONTINUITY)
    local d="$1"; shift
    {
        echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-MEDIA-SEQUENCE:0"
        echo "#EXT-X-TARGETDURATION:20"
        for s in "$@"; do
            local dur; dur=$($FP -v error -show_entries format=duration -of csv=p=0 "$d/$s")
            echo "#EXTINF:${dur},"; echo "$s"
            echo "#EXT-X-DISCONTINUITY"
        done
        echo "#EXT-X-ENDLIST"
    } > "$d/index.m3u8"
}
m3u8_single() { # m3u8_single <dir> <seg>
    local d="$1" s="$2"
    local dur; dur=$($FP -v error -show_entries format=duration -of csv=p=0 "$d/$s")
    { echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-MEDIA-SEQUENCE:0"
      echo "#EXT-X-TARGETDURATION:20"
      echo "#EXTINF:${dur},"; echo "$s"; echo "#EXT-X-ENDLIST"; } > "$d/index.m3u8"
}

# ---------- SK0-base：连续拼接成单文件（无 DISCONT） ----------
echo "== SK0-base =="
mkdir -p sk0-base
# 三段各 rebase 到连续时间轴：seg6→1000, seg7→1010.562, seg8→1019.371
rebase "$S6" 0        sk0-base/_s6.ts   # 起点 0
rebase "$S7" 10.562   sk0-base/_s7.ts   # 起点 10.562（接 seg6 末尾）
rebase "$S8" 19.371   sk0-base/_s8.ts   # 起点 19.371
$FF -y -f concat -safe 0 -i <(printf "file '%s/sk0-base/_s6.ts'\nfile '%s/sk0-base/_s7.ts'\nfile '%s/sk0-base/_s8.ts'\n" "$PWD" "$PWD" "$PWD") \
    -c copy -f mpegts -muxdelay 0 -muxpreload 0 sk0-base/SK0.ts >/dev/null 2>&1
rm -f sk0-base/_s6.ts sk0-base/_s7.ts sk0-base/_s8.ts
m3u8_single sk0-base SK0.ts

# ---------- SK1-disc：6 #D 7 #D 8，时间戳连续递增（段间衔接，不回落到 0）----------
# 各段 rebase 到连续时间轴：seg6→0, seg7→10.562, seg8→19.371
echo "== SK1-disc =="
mkdir -p sk1-disc
rebase "$S6" 0        sk1-disc/s6.ts        # 起点 0
rebase "$S7" 10.562   sk1-disc/s7.ts        # 起点 10.562
rebase "$S8" 19.371   sk1-disc/s8.ts        # 起点 19.371
m3u8_disc sk1-disc s6.ts s7.ts s8.ts

# ---------- SK2-disc-jump：6 #D 7(+60) #D 8(+120)，DISCONT + 时间戳大跳 ----------
echo "== SK2-disc-jump =="
mkdir -p sk2-disc-jump
rebase "$S6" 0     sk2-disc-jump/s6.ts     # 起点 0
rebase "$S7" 60    sk2-disc-jump/s7.ts     # 起点 60（大跳）
rebase "$S8" 120   sk2-disc-jump/s8.ts     # 起点 120（大跳）
m3u8_disc sk2-disc-jump s6.ts s7.ts s8.ts

# ---------- SK3-mixres：8K(6) #D 720p(009) #D 8K(8)，时间戳连续递增 ----------
# seg6→0, 720p→10.562, seg8→20.635（=10.562+10.073），分辨率交替且时间轴连续
echo "== SK3-mixres =="
mkdir -p sk3-mixres
rebase "$S6" 0        sk3-mixres/s6.ts       # 起点 0
rebase "$S720" 10.562 sk3-mixres/s720.ts       # 起点 10.562
rebase "$S8" 20.635   sk3-mixres/s8.ts         # 起点 20.635
m3u8_disc sk3-mixres s6.ts s720.ts s8.ts

echo "== 构造完成 =="
for d in sk0-base sk1-disc sk2-disc-jump sk3-mixres; do
    echo "--- $d ---"
    cat "$d/index.m3u8"
    echo "总时长: $($FP -v error -show_entries format=duration -of csv=p=0 "$d/index.m3u8" | head -1)"
    echo "DISCONT 通告: $($FP -v error -show_packets -of json "$d/index.m3u8" 2>/dev/null | grep -c '"Discontinuity"' || true)"
done
