#!/bin/bash
# 在 build_2x_sources.sh 产出的 4 个结构源之上，构造两种字幕形式：
#
#   Form A（外挂 WebVTT）: <src>-wvtt/
#       master.m3u8         EXT-X-MEDIA SUBTITLES -> sub_en.m3u8
#       index.m3u8 + s_*.ts 视频/音频（TS 分片，保留结构源的 DISCONT）
#       sub_en.m3u8 + sub_en.vtt  外挂字幕
#
#   Form B（HLS over fMP4）: <src>-fmp4/        ← 取代旧的 -emb（单纯 MP4）
#       master.m3u8         同上 + SUBTITLES="subs" -> index.m3u8
#       index.m3u8          EXT-X-MAP:URI="init*.mp4" + 分段 .m4s + 段界 DISCONT
#       init_a/b/c.mp4      各 group 独立 init（mixres 中间段 1080p 即独立 init）
#       sub_en.m3u8 + sub_en.vtt  字幕 rendition（HLS 规定字幕只能走 WebVTT）
#
# 注意：HLS 不允许 mov_text 内嵌（hlsenc 强制字幕走 WebVTT），故两种形式的“差别”
#       在媒体封装（TS vs fMP4 / EXT-X-MAP），字幕一律是外挂 WebVTT rendition。
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
FF=${FF:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffmpeg}
FP=${FP:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffprobe}
FACTS=sources_facts.tsv
[ -f "$FACTS" ] || { echo "请先跑 ./build_2x_sources.sh"; exit 1; }
TMP=$(mktemp -d /tmp/subsrc.XXXXXX); trap 'rm -rf "$TMP"' EXIT
SRCS="sk4-2x-base sk4-2x-disc sk4-2x-jump sk4-2x-mixres"

gen_vtt() { # gen_vtt <out.vtt> <t1> <t2> ...
  local out="$1"; shift; : > "$out"; printf 'WEBVTT\n\n' >> "$out"; local i=1 t
  for t in "$@"; do
    local end=$((t+2))
    printf '%02d:%02d:%02d.000 --> %02d:%02d:%02d.000\nSubtitle cue %d (t=%ss)\n\n' \
      $((t/3600)) $((t%3600/60)) $((t%60)) \
      $((end/3600)) $((end%3600/60)) $((end%60)) "$i" "$t" >> "$out"
    i=$((i+1))
  done
}
fdur() { $FP -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null; }

CUES="2 5 12 15 22 25"   # 字幕 cue 时间点（playlist 时间轴，落在 3 个 group：0-10 / 10-28 / 28-35）

# ── Form A：外挂 WebVTT ──
build_wvtt() {
  local src="$1" d="$1-wvtt"; mkdir -p "$d"; rm -f "$d"/*
  cp "$src/index.m3u8" "$d/index.m3u8"
  cp "$src"/s_*.ts "$d/"
  gen_vtt "$d/sub_en.vtt" $CUES
  local tdur=$(( $(echo $CUES | awk '{print $NF}') + 2 + 1 ))
  { echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-MEDIA-SEQUENCE:0"
    echo "#EXT-X-TARGETDURATION:$tdur"; echo "#EXTINF:${tdur}.000,"; echo "sub_en.vtt"
    echo "#EXT-X-ENDLIST"; } > "$d/sub_en.m3u8"
  { echo "#EXTM3U"
    echo "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"en\",URI=\"sub_en.m3u8\""
    echo "#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS=\"avc1.640028,mp4a.40.2\",RESOLUTION=1280x720,SUBTITLES=\"subs\""
    echo "index.m3u8"; } > "$d/master.m3u8"
  local dur; dur=$(fdur "$d/index.m3u8" || true)
  local disc; disc=$(grep -c 'EXT-X-DISCONTINUITY' "$d/index.m3u8" || true)
  local alt="-"; [ "$src" = "sk4-2x-mixres" ] && alt="1280x720->1920x1080->1280x720" || true
  printf '%s\twvtt\tmaster.m3u8\t%s\t3\t%d\t1280x720\t%s\tsub_en.m3u8\n' "$d" "$dur" "$disc" "$alt" >> "$FACTS"
  echo "  [Form A] $d  dur=$dur disc=$disc"
}

# ── Form B：HLS over fMP4 ──
# base：单 pass 连续 fMP4（1 个 init，tfdt 连续，无 DISCONT）
# disc/jump/mixres：每组独立 pass（各自 init），组装时组间插 DISCONT
#   - jump：每组媒体时间轴已落在 0/60/120，分段 init 的 tfdt 保留 50s 大跳
#   - mixres：中间组是 1080p，独立 init → 分辨率切换可被解码器重建探测到
build_fmp4() {
  local src="$1" d="$1-fmp4"; mkdir -p "$d"; rm -f "$d"/*
  if [ "$src" = "sk4-2x-base" ]; then
    : > "$TMP/list.ts"; for g in a b c; do echo "file '$PWD/$src/s_$g.ts'" >> "$TMP/list.ts"; done
    $FF -y -f concat -safe 0 -i "$TMP/list.ts" -c copy -bsf:a aac_adtstoasc \
        -f hls -hls_time 30 -hls_playlist_type vod -hls_segment_type fmp4 \
        -hls_fmp4_init_filename init.mp4 -hls_segment_filename "$d/s%03d.m4s" \
        "$d/index.m3u8" >/dev/null 2>&1
  else
    local g max=0 map seg ext first=1
    # 每个源必须独立组装：_body 若不清空会跨源累积（disc 跑完 body 留 3 组，
    # jump 再追加变 6 组、mixres 变 9 组），导致片源时长与“每组 3 段”的设计不符。
    : > "$TMP/_body.m3u8"
    for g in a b c; do
      # 每组独立 pass：init / segment / playlist 全部用绝对路径显式落在 $d。
      # 注意 ffmpeg 对 -hls_segment_filename 的相对名会解析到 CWD（而非 playlist 目录），
      # 而 -hls_fmp4_init_filename 的相对名解析到 playlist 目录 —— 二者不一致会导致
      # 分段被写到仓库根目录、最终 index.m3u8 引用的分段缺失、ffprobe 解析失败。
      # cd 进 $d 跑 ffmpeg：hls muxer 把 init/segment 相对名分别解析到 playlist 目录与 CWD，
      # 二者都落在 $d 后，init 与分段就统一在 $d 内（绝对路径反而会被二次嵌套，故不用）。
      ( cd "$d" && $FF -y -i "$PWD/../$src/s_$g.ts" -c copy -bsf:a aac_adtstoasc \
          -f hls -hls_time 30 -hls_playlist_type vod -hls_segment_type fmp4 \
          -hls_fmp4_init_filename "init_$g.mp4" -hls_segment_filename "${g}_%03d.m4s" \
          "_g_$g.m3u8" >/dev/null 2>&1 )
      map=$(grep 'EXT-X-MAP' "$d/_g_$g.m3u8" | sed -n 's/.*URI="\([^"]*\)".*/\1/p' | head -1)
      map=$(basename "$map")
      ext=$(grep 'EXTINF' "$d/_g_$g.m3u8" | sed -n 's/#EXTINF:\([^,]*\),.*/\1/p' | head -1)
      seg=$(grep -A1 'EXTINF' "$d/_g_$g.m3u8" | tail -1)
      seg=$(basename "$seg")
      dur=$(awk -v e="$ext" 'BEGIN{printf "%d", e+0.999}')
      [ "$dur" -gt "$max" ] && max=$dur
      # 组界必须插 DISCONT（首组除外）：
      #   换 init 属 RFC8216 §4.3.2.3 的 "file format" 变化；
      #   各段 tfdt 均为 0（时间戳在分片的 tfdt，不在 init），故每段起点时间戳归零
      #   属 "timestamp sequence" 变化 —— 两者都是 MUST，未标记即 §3 所警告的
      #   "unmarked media discontinuities can trigger playback errors"。
      # 旧写法 [ "$g" != "c" ] 在 c 后不插：单轮时侥幸正确，一旦多轮，
      # 轮次边界 c→a 就会漏标记，播放端不重置解析器而截断。
      if [ "$first" = 1 ]; then first=0; else echo "#EXT-X-DISCONTINUITY" >> "$TMP/_body.m3u8"; fi
      # 累积到最终 index.m3u8（MAP/segment 均用相对名，最终 playlist 也在 $d）
      { echo "#EXT-X-MAP:URI=\"$map\""
        echo "#EXTINF:${ext},"; echo "$seg"; } >> "$TMP/_body.m3u8"
    done
    { echo "#EXTM3U"; echo "#EXT-X-VERSION:7"; echo "#EXT-X-TARGETDURATION:$max"
      echo "#EXT-X-PLAYLIST-TYPE:VOD"; echo "#EXT-X-MEDIA-SEQUENCE:0"
      cat "$TMP/_body.m3u8"; echo "#EXT-X-ENDLIST"; } > "$d/index.m3u8"
    # 清理每组中间 playlist（只保留最终 index.m3u8 + init + 分段）
    rm -f "$d"/_g_*.m3u8
  fi
  # 字幕 rendition
  gen_vtt "$d/sub_en.vtt" $CUES
  local tdur=$(( $(echo $CUES | awk '{print $NF}') + 2 + 1 ))
  { echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-MEDIA-SEQUENCE:0"
    echo "#EXT-X-TARGETDURATION:$tdur"; echo "#EXTINF:${tdur}.000,"; echo "sub_en.vtt"
    echo "#EXT-X-ENDLIST"; } > "$d/sub_en.m3u8"
  { echo "#EXTM3U"
    echo "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"English\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"en\",URI=\"sub_en.m3u8\""
    echo "#EXT-X-STREAM-INF:BANDWIDTH=3000000,CODECS=\"avc1.640028,mp4a.40.2\",RESOLUTION=1280x720,SUBTITLES=\"subs\""
    echo "index.m3u8"; } > "$d/master.m3u8"
  local dur; dur=$(fdur "$d/index.m3u8" || true)
  local disc; disc=$(grep -c 'EXT-X-DISCONTINUITY' "$d/index.m3u8" || true)
  local alt="-"; [ "$src" = "sk4-2x-mixres" ] && alt="1280x720->1920x1080->1280x720" || true
  local ninit; ninit=$(ls "$d"/init*.mp4 2>/dev/null | wc -l)
  printf '%s\tfmp4\tmaster.m3u8\t%s\t3\t%d\t1280x720\t%s\tsub_en.m3u8\n' "$d" "$dur" "$disc" "$alt" >> "$FACTS"
  echo "  [Form B] $d  dur=$dur disc=$disc init数=$ninit"
}

# ── 主流程 ──
# 先恢复结构源事实行（build_2x 写出的 sources_struct.tsv），再追加字幕形式行
: > "$FACTS"
[ -f sources_struct.tsv ] && cat sources_struct.tsv >> "$FACTS"
for src in $SRCS; do
  [ -f "$src/index.m3u8" ] || { echo "缺少 $src，先跑 build_2x_sources.sh"; exit 1; }
  echo "== $src =="
  # 删掉旧的 -emb 形式（用户要求去掉单纯 MP4）
  [ -d "$src-emb" ] && { echo "  删除旧 $src-emb"; rm -rf "$src-emb"; }
  build_wvtt "$src"
  build_fmp4 "$src"
done

echo; echo "===== 片源事实（含字幕形式，$FACTS）====="
column -t -s $'\t' "$FACTS"
echo; echo "===== 交给 verify_sources.sh 复验（含字幕形式层）====="
exec ./verify_sources.sh all
