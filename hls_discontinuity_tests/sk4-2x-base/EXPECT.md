# sk4-2x-base — SK4-2x-base（rmdmy 结构源, 无 DISCONT, 字幕套件 base） ／ 字幕结构源 base（无 DISCONT）

本目录是 **seek + discontinuity 套件** 与 **subtitle + discontinuity 套件** 的共用结构源：既被 `sk-sp-*` 用例（2× + 跨 DISCONT 边界 seek）复用，也被字幕 32 矩阵例（4 结构 × 2 封装 × 4 动作）复用。

## 源构造（特征）

- 素材：rmdmy 009/010/011.ts（720p h264 / aac 44100）
- 重编码摆放到非负连续时间轴，无 DISCONT
- 总时长 ~35.9s，结构源只含 index.m3u8 + s_*.ts

## 一、Seek + Discontinuity 用法（2× 变速 + 跨 DISCONT 边界 seek）

覆盖场景：seek 套件 sk-sp-00a（2× + 起播即 seek 15.0）；字幕套件 sub-{W,E}-base-*（4 动作）

- **A/V 不同步 `desynchronisation` == 0**（头条）
- `Reset playback due to audio timestamp` == 0；音频 PTS 真回退 == 0
- seek 后播放时长 near `(total-lastseek)/speed`（±6s）；硬解健康；`event: end-file`（播放完整结束）== 1
- 运行：`bash assert_seek_cases_device.sh sk-sp-*`

## 二、Subtitle + Discontinuity 用法（tunnel 直通下外挂 WebVTT）

- 无 DISCONT（对照组）
- pseek=15.0
- r720=0

- **Form A `wvtt`（TS 封装）**：`sk4-2x-base-wvtt/master.m3u8`
- **Form B `fmp4`（HLS over fMP4）**：`sk4-2x-base-fmp4/master.m3u8`
- **4 动作**：`pos` 起播即 seek / `mid` 播放中多次 seek / `sp` 2×+起播即 seek / `mdsp` 2×+播放中多次 seek

**前置（必须，否则字幕断言必然全挂）**：ffmpeg 的 HLS 在 `read_header` 阶段把字幕 playlist
置 `needed=0`、流 `discard=AVDISCARD_ALL`（**上游默认关闭字幕**），读取循环只处理
`pls->needed` 的 playlist，`read_subtitle_packet()` 不会被调用、字幕永不去拉。
必须经 `mpv.conf` 显式启用：`sid=1` + `sub-visibility=yes`（`msg-level=ffmpeg=debug` 需保留，
靠它打印 HLS request 行）。`assert_subtitle_cases_device.sh` 已内置 `ensure_subtitle_conf()` 自动推送。

**已修复（2026-09-25）：开播即 seek 时字幕不会被拉取。** 根因：`hls_read_seek` 对字幕 playlist
用 `find_timestamp_in_playlist` 映射 `cur_seq_no`，但字幕 playlist 的段时序与主媒体不对应，
使 `current_segment(pls)->url` 越界/为 NULL，`init_subtitle_context` 打开子 demuxer 失败（日志 `Format webvtt
detected only with low score`）。修复：`hls_read_seek` 对 `is_subtitle` playlist 改为关闭子 demuxer 并从首段
（`start_seq_no`）重新读取。修复后 position=0 与 position>0 均能拉取 `sub_en.vtt`（已真机验证）。

判定：字幕被拉取(sub_en)≥1（须先启用字幕，见前置）；字幕轨识别≥1；**A/V 不同步==0**；Reset playback==0；音频PTS真回退==0；播放完整；硬解健康；mixres 用 `VO: [mediacodec_embed]` 行识别 1280x720 与 1920x1080；**已知问题**：开播即 seek 时字幕不拉取。

运行：`bash assert_subtitle_cases_device.sh sub-W-<b>-<act>` / `sub-E-<b>-<act>`（需 DEBUG apk）
