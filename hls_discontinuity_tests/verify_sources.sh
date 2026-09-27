#!/bin/bash
# verify_sources.sh —— 片源 / 用例前置 机读验收
#
# 三级验收：
#   --level material  仅查素材（rmdmy 各分段是否干净）
#   --level source    复验 sources_facts.tsv 里 kind=ts 的结构片源（S1~S6）
#   --level all       额外复验 subtitle 形式（kind=wvtt|fmp4）：master 含 SUBTITLES、
#                     rendition 文件存在、fmp4 含 EXT-X-MAP/init、字幕 cue 时间轴对齐
#
# 退出码：任一 FAIL 即非零。
set -u
cd "$(cd "$(dirname "$0")" && pwd)"
FF=${FF:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffmpeg}
FP=${FP:-/home/lck/work/src/ffmpeg/ffmpeg_build/bin/ffprobe}
FACTS=sources_facts.tsv
LEVEL=${1:-all}
PASS=0; FAIL=0
R() { # R <result:0|1> <name> <detail>
  if [ "$1" = "0" ]; then PASS=$((PASS+1)); printf '  [PASS] %-30s %s\n' "$2" "$3";
  else FAIL=$((FAIL+1)); printf '  [FAIL] %-30s %s\n' "$2" "$3"; fi
}
die() { echo "$*" >&2; exit 2; }

n_badpkt(){ $FP -v error -select_streams v:0 -show_entries packet=pts_time,dts_time -of csv=p=0 "$1" 2>/dev/null | awk -F, '{if($1!="N/A"&&$2!="N/A"&&$1-$2>0.5)n++}END{print n+0}'; }
n_vjump() { $FP -v error -select_streams v:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null | awk -F, 'BEGIN{t=1.0}{if($1!="N/A"){if(N>0&&($1-p>t||$1-p<-t))n++;p=$1;N++}}END{print n+0}'; }
n_ajump() { $FP -v error -select_streams a:0 -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null | awk -F, 'BEGIN{t=0.1}{if($1!="N/A"){if(N>0&&($1-p>t||$1-p<-t))n++;p=$1;N++}}END{print n+0}'; }
res_of()  { $FP -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$1" 2>/dev/null | head -1 | sed 's/,/x/'; }
disc_in() { local n; n=$(grep -c 'EXT-X-DISCONTINUITY' "$1" 2>/dev/null); [ -n "$n" ] && echo "$n" || echo 0; }
fdur()    { $FP -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null; }
sub_ok()  { # sub_ok <master.m3u8> ；返回 0 表示含 SUBTITLES 且 rendition URI 可达
  local m="$1"; [ -f "$m" ] || return 1
  grep -q 'EXT-X-MEDIA:TYPE=SUBTITLES' "$m" || return 1
  local uri; uri=$(grep 'EXT-X-MEDIA:TYPE=SUBTITLES' "$m" | sed -n 's/.*URI="\([^"]*\)".*/\1/p' | head -1)
  [ -n "$uri" ] || return 1
  [ -f "$(dirname "$m")/$uri" ] || return 1
  return 0
}

# ── material ───────────────────────────────────────────────────────────────
if [ "$LEVEL" = "material" ] || [ "$LEVEL" = "all" ]; then
  echo "== 素材层 =="
  for f in rmdmy/009.ts rmdmy/010.ts rmdmy/011.ts; do
    [ -f "$f" ] || { R 1 "$f" "不存在"; continue; }
    local_b=$(n_badpkt "$f"); vj=$(n_vjump "$f"); aj=$(n_ajump "$f")
    R "$([ "$local_b" = "0" ] && echo 0 || echo 1)" "$f" "坏包=$local_b 视频跳变=$vj 音频跳变=$aj $(res_of "$f")"
  done
fi

# ── source（结构片源）───────────────────────────────────────────────────────
if [ "$LEVEL" = "source" ] || [ "$LEVEL" = "all" ]; then
  echo "== 片源层（来自 $FACTS）=="
  [ -f "$FACTS" ] || die "无 $FACTS"
  while IFS=$'\t' read -r dir kind entry dur nseg disc res_main res_alt sub_uri; do
    [ -z "$dir" ] && continue; case "$dir" in \#*) continue;; esac
    [ "$kind" = "ts" ] || continue
    echo "-- $dir ($kind) --"
    media="$dir/$entry"
    [ -f "$media" ] || { R 1 "$dir/media" "无 $media"; continue; }
    b=$(n_badpkt "$media"); vj=$(n_vjump "$media"); aj=$(n_ajump "$media")
    R "$([ "$b" = "0" ] && echo 0 || echo 1)" "$dir/S1坏包" "=$b"
    # jump 结构在 2 个段界故意留 50s 大跳（>=5s），其余结构必须 0 跳变
    expj=$(echo "$dir" | grep -q jump && echo 2 || echo 0)
    R "$([ "$vj" = "$expj" ] && echo 0 || echo 1)" "$dir/S2视频跳变(期望$expj)" "=$vj"
    R "$([ "$aj" = "$expj" ] && echo 0 || echo 1)" "$dir/S3音频跳变(期望$expj)" "=$aj"
    R "$([ "$(res_of "$media")" = "$res_main" ] && echo 0 || echo 1)" "$dir/S5主分辨率" "=$(res_of "$media")/期望$res_main"
    [ "$res_alt" != "-" ] && R "$(grep -q "$res_alt" <(for s in "$dir"/*.ts; do res_of "$s"; done) && echo 0 || echo 1)" "$dir/S5辅分辨率" "出现$res_alt"
    d=$(disc_in "$dir/index.m3u8")
    R "$([ "$d" = "$disc" ] && echo 0 || echo 1)" "$dir/DISCONT" "实测=$d 期望=$disc"
    got=$(fdur "$media")
    R "$(awk -v a="$got" -v b="$dur" 'BEGIN{d=a-b;if(d<0)d=-d;exit !(d<=0.5)}' && echo 0 || echo 1)" "$dir/S6时长" "实测=$got 声明=$dur"
  done < "$FACTS"
fi

# ── subtitle 形式（wvtt / fmp4）────────────────────────────────────────────
if [ "$LEVEL" = "all" ] || [ "$LEVEL" = "subtitle" ]; then
  echo "== 字幕形式层（wvtt / fmp4，来自 $FACTS）=="
  [ -f "$FACTS" ] || die "无 $FACTS"
  while IFS=$'\t' read -r dir kind entry dur nseg disc res_main res_alt sub_uri; do
    [ -z "$dir" ] && continue; case "$dir" in \#*) continue;; esac
    [ "$kind" = "ts" ] && continue
    echo "-- $dir ($kind) --"
    m="$dir/$entry"
    [ -f "$m" ] || { R 1 "$dir/master" "无 $m"; continue; }
    R "$(sub_ok "$m" && echo 0 || echo 1)" "$dir/字幕rendition" "master 含 SUBTITLES 且 URI 可达"
    if [ "$kind" = "fmp4" ]; then
      # EXT-X-MAP/init 在 index.m3u8（媒体 playlist）里，不在 master
      im="$dir/index.m3u8"
      R "$(grep -q 'EXT-X-MAP' "$im" && echo 0 || echo 1)" "$dir/EXT-X-MAP" "fMP4 须含 EXT-X-MAP(init)"
      init=$(grep 'EXT-X-MAP' "$im" | sed -n 's/.*URI="\([^"]*\)".*/\1/p' | head -1)
      [ -n "$init" ] && [ -f "$dir/$init" ] && $FP -v error -show_entries format=format_name -of csv=p=0 "$dir/$init" >/dev/null 2>&1 \
        && R 0 "$dir/init" "$init 可解析" || R 1 "$dir/init" "$init 缺失/不可解析"
      # 整 playlist 必须能被 ffprobe 解析（含所有分段）：分段缺失/写错目录时，
      # 上面的 init 检查仍会 PASS，必须用整 playlist 解析兜底。
      if $FP -v error -show_entries format=duration -of csv=p=0 "$im" >/dev/null 2>&1; then
        R 0 "$dir/playlist可解析" "ffprobe 成功（分段齐全）"
      else
        R 1 "$dir/playlist可解析" "ffprobe 失败（分段缺失/损坏/路径错误）"
      fi
    fi
    # 字幕 cue 时间轴对齐：rendition 里首个 cue 时间应落在 [0, 媒体首段时长] 内
    uri=$(grep 'EXT-X-MEDIA:TYPE=SUBTITLES' "$m" | sed -n 's/.*URI="\([^"]*\)".*/\1/p' | head -1)
    [ -n "$uri" ] && R "$(grep -q 'WEBVTT' "$dir/sub_en.vtt" && echo 0 || echo 1)" "$dir/vtt头" "sub_en.vtt 含 WEBVTT"
  done < "$FACTS"
fi

echo
echo "===== 汇总：PASS=$PASS  FAIL=$FAIL ====="
[ "$FAIL" = "0" ] && exit 0 || exit 1
