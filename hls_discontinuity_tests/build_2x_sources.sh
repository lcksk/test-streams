#!/bin/bash
# 用 rmdmy 这套干净 720p HLS 基础片源构造 sk4-2x-{base,disc,jump,mixres}
#
# 媒体：rmdmy/009.ts..029.ts（h264 1280x720 25fps + aac，自带 index.m3u8）
#  ── 已实测干净（concat 009/010/011 后：坏包=0、视频 PTS 跳变=0、音频 PTS 跳变=0）
#  ── 自带 aac 音轨，无需再合成
# 内容块（3 段，取自 rmdmy）：
#   A = 009.ts  B = 010.ts  C = 011.ts
#
# 片源验收标准（本脚本 + verify_sources.sh 强制，任一条不过即坏源）：
#   S1 无坏包    ：每个视频包 pts-dts <= 0.5s
#   S2 视频时间轴：段内相邻 PTS 跳变 <= 1 帧（禁 >=5s 跳变，否则 mpv demux_lavf 置
#                  ts_resets_possible=1 → player/video.c:398 容差 5s 内判“假定不连续”）
#   S3 音频时间轴：相邻包 PTS 跳变 <= 0.1s
#   S4 时间轴连续：base/disc/mixres 段界严格首尾相接（<=1 帧，无 gap 无重叠）
#                  jump 仅在两处段界故意留 50s 大跳（0 / 60 / 120）
#   S5 分辨率    ：base/disc/jump = 1280x720；mixres = 1280x720 → 1920x1080 → 1280x720
#   S6 时长      ：写入 sources_facts.tsv（用例禁止硬编码时长）
#
# 注：原 O_Neg_1__st.ts 自带 1 个坏包（pts=53.014 dts=41.931, Δ=+11.083），会单点
#     触发 mpv “假定不连续”→ A/V 不同步误报，故弃用，改成本地干净源。
set -e
cd "$(cd "$(dirname "$0")" && pwd)"
FF=${FF:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffmpeg}
FP=${FP:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffprobe}
RMDMY=${RMDMY:-rmdmy}
FPS=25
A=009; B=010; C=011
FACTS=sources_facts.tsv
TMP=$(mktemp -d /tmp/build2x.XXXXXX); trap 'rm -rf "$TMP"' EXIT

die() { printf '  [FATAL] %s\n' "$*" >&2; exit 1; }

first_pts(){ $FP -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null | grep -v N/A | head -1; }
last_pts() { $FP -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null | grep -v N/A | tail -1; }
res_of()  { $FP -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$1" 2>/dev/null | head -1 | sed 's/,/x/'; }
fdur()    { $FP -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null; }
n_badpkt(){ $FP -v error -select_streams v:0 -show_entries packet=pts_time,dts_time -of csv=p=0 "$1" 2>/dev/null | awk -F, '{if($1!="N/A"&&$2!="N/A"&&$1-$2>0.5)n++}END{print n+0}'; }
n_vjump() { $FP -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null | awk -F, 'BEGIN{t=1.0}{if($1!="N/A"){if(N>0&&($1-p>t||$1-p<-t))n++;p=$1;N++}}END{print n+0}'; }
n_ajump() { $FP -v error -select_streams a:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null | awk -F, 'BEGIN{t=0.1}{if($1!="N/A"){if(N>0&&($1-p>t||$1-p<-t))n++;p=$1;N++}}END{print n+0}'; }

# 把一段媒体重编码后摆放到 start_pts 位置写出。
# 关键：re-encode 后内容自然从 0 起，用非负 offset 定位（ffmpeg 会把负值
#       output_ts_offset 钳为 0，故一律传累计非负位置）。
# 重编码视频(libx264)可彻底消除 TS-AAC 分组帧的“伪 PTS 跳变”，且分辨率可控
# （mixres 中间段转 1080p）。音频重编码(aac)保证逐帧干净 PTS。
place() { # place <raw_in> <out> <start_pts>  (start_pts >= 0)
  $FF -y -i "$1" -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 96k \
      -output_ts_offset "$3" -muxdelay 0 -muxpreload 0 -f mpegts "$2" >/dev/null 2>&1
}
# 转码成不同分辨率（仅 mixres 的中间段用）。
# 注意：-c:a copy 把 AAC 拷进新 TS 会损坏音轨（"channel element not allocated"），
# 故音频也重编码。
transcale() { # transcale <raw_in> <out> <WxH>
  local w=${3%x*} h=${3#*x}
  $FF -y -i "$1" -vf "scale=$w:$h" -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 96k \
      -bsf:a aac_adtstoasc -muxdelay 0 -muxpreload 0 -f mpegts "$2" >/dev/null 2>&1
}

check() { # check <file> <expect_res> ; 输出 FAIL 原因，0=通过
  local f="$1" res="$2" bad vj aj r
  bad=$(n_badpkt "$f"); vj=$(n_vjump "$f"); aj=$(n_ajump "$f"); r=$(res_of "$f")
  [ "$bad" = "0" ] || { echo "S1 坏包=$bad"; return 1; }
  [ "$vj"  = "0" ] || { echo "S2 视频PTS跳变=$vj"; return 1; }
  [ "$aj"  = "0" ] || { echo "S3 音频PTS跳变=$aj"; return 1; }
  [ "$r" = "$res" ] || { echo "S5 分辨率=$r(期望 $res)"; return 1; }
  return 0
}

# 组装一个结构。参数：<name> <mode:continuous|jump> <A_raw> <B_raw> <C_raw> <B_res_for_mixres>
# 注：base/disc/mixres 用 continuous；jump 用 jump。
build_struct() {
  local name="$1" mode="$2" a_raw="$3" b_raw="$4" c_raw="$5" b_res="${6:-1280x720}"
  local d="$name"; mkdir -p "$d"; rm -f "$d"/*.ts "$d"/*.m3u8
  echo "== $name（$mode）=="

  # 中间段按 mixres 需要转分辨率
  local b_for_place="$b_raw"
  if [ "$b_res" != "1280x720" ]; then
    transcale "$b_raw" "$TMP/b_alt.ts" "$b_res"
    b_for_place="$TMP/b_alt.ts"
  fi

  # 摆放：re-encode 后内容从 0 起，用非负 offset 定位。
  # continuous：各段首尾相接（段界容差 0.5s，远小于 mpv 的 5s discontinuity 阈值）；
  # jump：0 / 60 / 120（段界故意大跳，测试 discontinuity）。
  if [ "$mode" = "jump" ]; then
    place "$a_raw"       "$d/s_a.ts" 0
    place "$b_for_place" "$d/s_b.ts" 60
    place "$c_raw"       "$d/s_c.ts" 120
  else
    place "$a_raw"       "$d/s_a.ts" 0
    local endA; endA=$(awk -v l="$(last_pts "$d/s_a.ts")" -v fr="$FPS" 'BEGIN{printf "%.6f", l+1/fr}')
    place "$b_for_place" "$d/s_b.ts" "$endA"
    local endB; endB=$(awk -v l="$(last_pts "$d/s_b.ts")" -v fr="$FPS" 'BEGIN{printf "%.6f", l+1/fr}')
    place "$c_raw"       "$d/s_c.ts" "$endB"
  fi
  local why
  why=$(check "$d/s_a.ts" 1280x720) || die "$name/s_a 验收失败：$why"
  why=$(check "$d/s_b.ts" "$b_res") || die "$name/s_b 验收失败：$why"
  why=$(check "$d/s_c.ts" 1280x720) || die "$name/s_c 验收失败：$why"

  # S4 连续性检查（仅 continuous 模式）
  if [ "$mode" = "continuous" ]; then
    local fb lc endA endB
    fb=$(first_pts "$d/s_b.ts"); lc=$(first_pts "$d/s_c.ts")
    endA=$(awk -v l="$(last_pts "$d/s_a.ts")" -v fr="$FPS" 'BEGIN{printf "%.6f", l+1/fr}')
    endB=$(awk -v l="$(last_pts "$d/s_b.ts")" -v fr="$FPS" 'BEGIN{printf "%.6f", l+1/fr}')
    awk -v a="$fb" -v b="$endA" 'BEGIN{d=a-b;if(d<0)d=-d;exit !(d<=0.5)}' \
      || die "$name S4 违反：s_b 首=$fb 未接 s_a 末=$endA (Δ=$(awk -v a="$fb" -v b="$endA" 'BEGIN{printf "%.3f",a-b}'))"
    awk -v a="$lc" -v b="$endB" 'BEGIN{d=a-b;if(d<0)d=-d;exit !(d<=0.5)}' \
      || die "$name S4 违反：s_c 首=$lc 未接 s_b 末=$endB (Δ=$(awk -v a="$lc" -v b="$endB" 'BEGIN{printf "%.3f",a-b}'))"
  fi

  # playlists：所有结构都用 3 段 + index.m3u8；
  # base 不带 DISCONT（对照组），其余在段界插入 DISCONT（disc_count = 段数-1 = 2）
  local total disc
  [ "$name" = "sk4-2x-base" ] && disc=0 || disc=2
  write_index "$d" "$disc" s_a.ts s_b.ts s_c.ts
  # total = playlist 时长（各段 EXTINF 之和），与段间 50s 大跳无关；
  # 用作用例里“播放总时长/seek 目标”的依据，必须与断言脚本一致
  total=$(fdur "$d/index.m3u8")
  write_index "$d" "$disc" s_a.ts s_b.ts s_c.ts
  local alt="-"; [ "$b_res" != "1280x720" ] && alt="$b_res"
  printf '%s\tts\tindex.m3u8\t%s\t3\t%d\t1280x720\t%s\t-\n' "$d" "$total" "$disc" "$alt" >> "$FACTS"
  printf '    总时长 %ss | DISCONT=%d | 中间段分辨率=%s\n' "$total" "$disc" "$b_res"
}

# 写 index.m3u8。disc_count=插入的 #EXT-X-DISCONTINUITY 数量（base=0，其余=2）
write_index() {
  local d="$1" dc="$2"; shift 2; local s dur max=0 n=$#
  for s in "$@"; do
    dur=$($FP -v error -show_entries format=duration -of csv=p=0 "$d/$s")
    max=$(awk -v a="$max" -v b="$dur" 'BEGIN{printf "%d", (b>a? b+0.999: a)}')
  done
  { echo "#EXTM3U"; echo "#EXT-X-VERSION:3"; echo "#EXT-X-MEDIA-SEQUENCE:0"
    echo "#EXT-X-TARGETDURATION:$max"
    local i=0
    for s in "$@"; do
      i=$((i+1))
      dur=$($FP -v error -show_entries format=duration -of csv=p=0 "$d/$s")
      echo "#EXTINF:${dur},"; echo "$s"
      if [ "$i" -lt "$n" ] && [ "$i" -le "$dc" ]; then echo "#EXT-X-DISCONTINUITY"; fi
    done
    echo "#EXT-X-ENDLIST"; } > "$d/index.m3u8"
}

# ── 主流程 ────────────────────────────────────────────────────────────────
: > "$FACTS"
[ -f "$RMDMY/$A.ts" ] || die "找不到 $RMDMY/$A.ts"
echo "基础片源：$RMDMY/{$A,$B,$C}.ts"
echo "  A 分辨率=$(res_of "$RMDMY/$A.ts")  B 分辨率=$(res_of "$RMDMY/$B.ts")  C 分辨率=$(res_of "$RMDMY/$C.ts")"

build_struct sk4-2x-base    continuous "$RMDMY/$A.ts" "$RMDMY/$B.ts" "$RMDMY/$C.ts" 1280x720
build_struct sk4-2x-disc    continuous "$RMDMY/$A.ts" "$RMDMY/$B.ts" "$RMDMY/$C.ts" 1280x720
build_struct sk4-2x-jump    jump       "$RMDMY/$A.ts" "$RMDMY/$B.ts" "$RMDMY/$C.ts" 1280x720
build_struct sk4-2x-mixres  continuous "$RMDMY/$A.ts" "$RMDMY/$B.ts" "$RMDMY/$C.ts" 1920x1080

echo
echo "===== 片源事实($FACTS) ====="
column -t -s $'\t' "$FACTS"
# 另存一份纯结构源事实，供 build_subtitle_sources.sh 拼接字幕形式行
cp "$FACTS" sources_struct.tsv
echo
echo "===== 交给 verify_sources.sh 复验 ====="
exec ./verify_sources.sh source
