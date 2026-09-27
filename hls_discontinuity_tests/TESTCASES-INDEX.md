# HLS discontinuity 测试集 — 测试用例总纲（共纲领）

> 生成时间：2026-09-25  ｜  根目录：`hls_discontinuity_tests/`


本索引汇总四套真机/HLS 测试的全部用例，便于按场景检索特定 case。每个目录级用例都配有 `EXPECT.md`（目的 / 特征 / 预期 / 判定）。


## 套件一览

- **Discontinuity**（case01-25）：开播到 EOF 的 discontinuity 处理，25 例，非倍速。判据脚本 `assert_cases_device.sh`。
- **Seek + Discontinuity**（sk0-sk4 源，25 矩阵例）：跨 DISCONT 边界 seek，含 1×/2× + 起播即 seek/中途 seek。判据脚本 `assert_seek_cases_device.sh`。
- **pts_robustness**（p01-p12）：discontinuity 组内不一致段完整播完 / 不丢段。判据脚本 `assert_pts_robustness_device.sh`。
- **Subtitle + Discontinuity**（4 结构源，32 矩阵例）：tunnel 直通下外挂 WebVTT 字幕 + discontinuity + 2×/seek。判据脚本 `assert_subtitle_cases_device.sh`。
- **修复回归（PDT / codec-change / seek-EPERM）**（case26-28）：针对 `b9872d9043`（跨 DISCONT seek 定位 + playlist duration 用段时长之和）与 `672964c02f`（forward-seek 越界守卫改用 rebase 后 `base`，消除跨 DISCONT 编解码器切换时正向 seek 的 EPERM 冻结）的定向回归，3 例。判据脚本 `assert_pdt_codecchange_device.sh`。


## 1. Discontinuity 用例（case01-25）

| 用例 | 场景 | 解码器重建(视/音) | 时长s | EXPECT.md |
| --- | --- | --- | --- | --- |
| case01-fmt-head | 格式不连续在最前 | 视频['base(720p) 前插一段 000.ts(640x360) 作为头部，形成「头格式断点」', '仅视频流格式变化（音频始终是 44100 stereo，不变）']/音频1 | 0 | [case01-fmt-head/](case01-fmt-head/EXPECT.md) |
| case02-fmt-mid | 格式不连续在中间 | 视频['720p 段中间插入 000.ts(360p) 再回到 720p，断点在中间', '仅视频格式变化，音频不变']/音频2 | 0 | [case02-fmt-mid/](case02-fmt-mid/EXPECT.md) |
| case03-fmt-tail | 格式不连续在最后 | 视频['720p 段末尾接 000.ts(360p)，断点在尾部', '仅视频格式变化，音频不变']/音频1 | 0 | [case03-fmt-tail/](case03-fmt-tail/EXPECT.md) |
| case04-video-only | 只有视频变化(时间戳已对齐) | 视频['同一 720p 内容的视频段被标记为断点，但音频连续、时间戳已对齐', '无分辨率变化（newres 不检测），只有视频重建']/音频1 | 0 | [case04-video-only/](case04-video-only/EXPECT.md) |
| case05-audio-only | 只有音频变化(22050/mono) | 视频['音频切换为 22050Hz mono（派生自 base），视频保持 720p 连续', '只有音频流参数变化']/音频0 | 1 | [case05-audio-only/](case05-audio-only/EXPECT.md) |
| case06-audio-head | 音频变化在最前 | 视频['头部即切换音频为 22050Hz mono，视频 720p 连续', '只有音频参数变化']/音频0 | 1 | [case06-audio-head/](case06-audio-head/EXPECT.md) |
| case07-ts-jump-fwd | 时间戳向前跳 +98s | 视频['在连续 009 段之间插入 +98s 的时间戳偏移段（格式不变）', '纯时间戳跳变，无格式/分辨率变化']/音频0 | 0 | [case07-ts-jump-fwd/](case07-ts-jump-fwd/EXPECT.md) |
| case08-ts-jump-back | 时间戳向后跳 -82s | 视频['在连续 009 段之间插入 -82s 的时间戳偏移段（格式不变）', '纯时间戳回跳，无格式/分辨率变化']/音频0 | 0 | [case08-ts-jump-back/](case08-ts-jump-back/EXPECT.md) |
| case09-ts-restart | 第二组时间戳归零 | 视频['第二组段时间戳重新从 0 开始（真实拼接流常见）', '无格式/分辨率变化']/音频0 | 0 | [case09-ts-restart/](case09-ts-restart/EXPECT.md) |
| case10-ts-only | 打 DISCONT 但时间戳本就连续 | 视频['相邻段时间戳本来就连续，仅插入 DISCONT 标记', '格式/时间戳均无变化']/音频0 | 0 | [case10-ts-only/](case10-ts-only/EXPECT.md) |
| case11-multi-disc | 4 片每片之间都 DISCONT | 视频['009 / 010 / 011 / 012 四段，每段之间都插 DISCONT（3 个断点）', '时间戳连续递增，无格式变化']/音频0 | 0 | [case11-multi-disc/](case11-multi-disc/EXPECT.md) |
| case12-fmt-and-ts | 格式变 + 时间戳跳同时 | 视频['头部插 000.ts(360p) 同时其时间戳相对前段有跳变', '视频格式 + 时间戳同时变化']/音频1 | 0 | [case12-fmt-and-ts/](case12-fmt-and-ts/EXPECT.md) |
| case13-disc-at-start | m3u8 开头就 DISCONT | 视频['#EXT-X-DISCONTINUITY 出现在第一个段之前', '开头即断点，时间戳/格式无额外变化']/音频0 | 0 | [case13-disc-at-start/](case13-disc-at-start/EXPECT.md) |
| case14-disc-every-ts-fwd | 每片都 DISCONT, 时间戳逐次前跳 | 视频['多段每段都 DISCONT，时间戳逐段前跳', '纯时间戳跳变，无格式变化']/音频0 | 0 | [case14-disc-every-ts-fwd/](case14-disc-every-ts-fwd/EXPECT.md) |
| case15-disc-every-ts-alt | 每片都 DISCONT, 时间戳前后交替跳 | 视频['多段每段都 DISCONT，时间戳前跳/后跳交替', '纯时间戳跳变，无格式变化']/音频0 | 0 | [case15-disc-every-ts-alt/](case15-disc-every-ts-alt/EXPECT.md) |
| case16-disc-every-fmt-alt | 每片都 DISCONT, 格式交替 720/360/720/360 | 视频['多段每段都 DISCONT，分辨率 720p→360p→720p→360p 交替', '格式变化驱动解码器重建']/音频3 | 0 | [case16-disc-every-fmt-alt/](case16-disc-every-fmt-alt/EXPECT.md) |
| case17-disc-every-audio-alt | 每片都 DISCONT, 音频参数交替 | 视频['多段每段都 DISCONT，音频 44100↔22050Hz mono 交替', '音频参数变化驱动解码器重建']/音频0 | 3 | [case17-disc-every-audio-alt/](case17-disc-every-audio-alt/EXPECT.md) |
| case18-cross-all | 交叉：视频变+前跳→音频变+前跳→都变回+后跳 | 视频['三段依次：视频 720p→360p+时间戳前跳；音频 44100→22050+前跳；两者变回 720p/44100+后跳', '视频与音频断点交错']/音频2 | 2 | [case18-cross-all/](case18-cross-all/EXPECT.md) |
| case19-disc-every-plain | 6 片每片都 DISCONT, 什么都不变(压力) | 视频['6 段每段都 DISCONT，内容均为 720p 连续，无额外变量', '纯多断点压力']/音频0 | 0 | [case19-disc-every-plain/](case19-disc-every-plain/EXPECT.md) |
| case20-dup-repeat-disc | 同一分片重复 3 次, 每次带 DISCONT | 视频['同一分片(009, 91.5→101.6s) 重复 3 次，每次都带 DISCONT', '内容完全相同、时间戳相同，靠标记开新组']/音频0 | 0 | [case20-dup-repeat-disc/](case20-dup-repeat-disc/EXPECT.md) |
| case21-dup-repeat-nodisc | 同一分片重复 3 次, 不带 DISCONT(对照) | 视频['同一分片重复 3 次，但【不】打 DISCONT 标记', '内容完全相同、时间戳相同，未标记则不切组']/音频0 | 0 | [case21-dup-repeat-nodisc/](case21-dup-repeat-nodisc/EXPECT.md) |
| case22-dup-repeat-offset | 同一分片重复 3 次, 带 DISCONT 且时间戳递增 | 视频['同一分片重复 3 次，每次带 DISCONT，时间戳逐次递增偏移', '内容相同、时间戳递增加偏移']/音频0 | 0 | [case22-dup-repeat-offset/](case22-dup-repeat-offset/EXPECT.md) |
| case23-dup-interleave-disc | 间隔重复 A B A B, 每次带 DISCONT | 视频['A、B 两段间隔重复（A B A B），每段都带 DISCONT', '跨组交替重复']/音频0 | 0 | [case23-dup-interleave-disc/](case23-dup-interleave-disc/EXPECT.md) |
| case24-dup-then-fmt | 先重复同格式段(000×2), 再切到 720p | 视频['000.ts(360p)×2 重复，再接 009.ts(720p)，断点在 fmt 变化处', '同格式重复段不触发重建，最后 fmt 变化触发一次']/音频1 | 0 | [case24-dup-then-fmt/](case24-dup-then-fmt/EXPECT.md) |
| case25-dup-mixed-ts | 同一分片重复 + 时间戳先后跳、再前跳 | 视频['同一分片重复，时间戳先回跳、再前跳', '重复 + 时间戳混跳']/音频0 | 0 | [case25-dup-mixed-ts/](case25-dup-mixed-ts/EXPECT.md) |

## 2. Seek + Discontinuity（源 + 矩阵例）

### 2.1 源目录（8 个，复用）

| 源目录 | 说明 | 覆盖场景 | EXPECT.md |
| --- | --- | --- | --- |
| sk0-base | SK0-base（无 DISCONT 的 seek 基线） | sk-pos-00a/b/c（起播即 seek 到 3.0/15.0/28.5） | [sk0-base/](sk0-base/EXPECT.md) |
| sk1-disc | SK1-disc（DISCONT + 时间戳连续衔接） | sk-pos-01a~01f（seek 到 3.0/10.7/14.0/19.6/24.0/28.5，覆盖边界前/后/段中/近 EOF） | [sk1-disc/](sk1-disc/EXPECT.md) |
| sk2-disc-jump | SK2-disc-jump（DISCONT + 时间戳大跳） | sk-pos-02a/b/c（seek 到 10.7/19.6/24.0） | [sk2-disc-jump/](sk2-disc-jump/EXPECT.md) |
| sk3-mixres | SK3-mixres（DISCONT + 分辨率切换） | sk-pos-03a/b/c（seek 到 3.0/14.0/24.0；14.0 落 720p 段内，期望识别 1280x720） | [sk3-mixres/](sk3-mixres/EXPECT.md) |
| sk4-2x-base | SK4-2x-base（rmdmy 结构源, 无 DISCONT, 字幕套件 base） | seek 套件 sk-sp-00a（2× + 起播即 seek 15.0）；字幕套件 sub-{W,E}-base-*（4 动作） | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sk4-2x-disc | SK4-2x-disc（DISCONT + 时间戳连续, 字幕套件 disc） | seek 套件 sk-sp-01a（2× + pos 14.0）；字幕套件 sub-{W,E}-disc-* | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sk4-2x-jump | SK4-2x-jump（DISCONT + 时间戳大跳, 字幕套件 jump） | seek 套件 sk-sp-02a（2× + pos 19.6）；字幕套件 sub-{W,E}-jump-* | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sk4-2x-mixres | SK4-2x-mixres（DISCONT + 分辨率切换, 字幕套件 mixres） | seek 套件 sk-sp-03a（2× + pos 14.0）；字幕套件 sub-{W,E}-mixres-* | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |

### 2.2 矩阵例（25 个，来自 assert_seek_cases_device.sh）

| 用例ID | 源 | 模式 | seek(s) | 倍速 | 总时长s | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| sk-pos-00a | sk0-base | pos | 3.0 | 1x | 29.41 | 0 |
| sk-pos-00b | sk0-base | pos | 15.0 | 1x | 29.41 | 0 |
| sk-pos-00c | sk0-base | pos | 28.5 | 1x | 29.41 | 0 |
| sk-pos-01a | sk1-disc | pos | 3.0 | 1x | 29.41 | 0 |
| sk-pos-01b | sk1-disc | pos | 10.7 | 1x | 29.41 | 0 |
| sk-pos-01c | sk1-disc | pos | 14.0 | 1x | 29.41 | 0 |
| sk-pos-01d | sk1-disc | pos | 19.6 | 1x | 29.41 | 0 |
| sk-pos-01e | sk1-disc | pos | 24.0 | 1x | 29.41 | 0 |
| sk-pos-01f | sk1-disc | pos | 28.5 | 1x | 29.41 | 0 |
| sk-pos-02a | sk2-disc-jump | pos | 10.7 | 1x | 29.41 | 0 |
| sk-pos-02b | sk2-disc-jump | pos | 19.6 | 1x | 29.41 | 0 |
| sk-pos-02c | sk2-disc-jump | pos | 24.0 | 1x | 29.41 | 0 |
| sk-pos-03a | sk3-mixres | pos | 3.0 | 1x | 30.67 | 1 |
| sk-pos-03b | sk3-mixres | pos | 14.0 | 1x | 30.67 | 1 |
| sk-pos-03c | sk3-mixres | pos | 24.0 | 1x | 30.67 | 0 |
| sk-mid-01a | sk1-disc | mid | 3 20 10 8 | 1x | 29.41 | 0 |
| sk-mid-01b | sk1-disc | mid | 26 3 | 1x | 29.41 | 0 |
| sk-mid-02a | sk2-disc-jump | mid | 5 15 | 1x | 29.41 | 0 |
| sk-mid-03a | sk3-mixres | mid | 3 14 24 | 1x | 30.67 | 1 |
| sk-sp-00a | sk4-2x-base | pos | 15.0 | 2x | 27.63 | 0 |
| sk-sp-01a | sk4-2x-disc | pos | 14.0 | 2x | 27.63 | 0 |
| sk-sp-01b | sk4-2x-disc | mid | 3 20 10 8 | 2x | 27.63 | 0 |
| sk-sp-02a | sk4-2x-jump | pos | 19.6 | 2x | 27.63 | 0 |
| sk-sp-03a | sk4-2x-mixres | pos | 14.0 | 2x | 28.49 | 1 |

## 3. pts_robustness 用例（p01-p12）

| 用例 | 场景 | EXPECT.md |
| --- | --- | --- |
| p01_baseline_no_disc | baseline 无 DISCONT | [pts_robustness/p01_baseline_no_disc/](pts_robustness/p01_baseline_no_disc/EXPECT.md) |
| p02_same_url_no_disc | 相同 URL 重复, 无 DISCONT | [pts_robustness/p02_same_url_no_disc/](pts_robustness/p02_same_url_no_disc/EXPECT.md) |
| p03_two_groups_consistent | 两组, 内容一致 | [pts_robustness/p03_two_groups_consistent/](pts_robustness/p03_two_groups_consistent/EXPECT.md) |
| p04_in_group_smaller | 组内某段更短 | [pts_robustness/p04_in_group_smaller/](pts_robustness/p04_in_group_smaller/EXPECT.md) |
| p05_in_group_larger | 组内某段更长 | [pts_robustness/p05_in_group_larger/](pts_robustness/p05_in_group_larger/EXPECT.md) |
| p06_in_group_back_and_forth | 组内时间戳前后往复 | [pts_robustness/p06_in_group_back_and_forth/](pts_robustness/p06_in_group_back_and_forth/EXPECT.md) |
| p07_multi_group_mixed | 多组混合 URL | [pts_robustness/p07_multi_group_mixed/](pts_robustness/p07_multi_group_mixed/EXPECT.md) |
| p08_last_odd_drain | 末尾为奇数长度段 | [pts_robustness/p08_last_odd_drain/](pts_robustness/p08_last_odd_drain/EXPECT.md) |
| p09_same_url_across_groups | 相同 URL 跨组重复 | [pts_robustness/p09_same_url_across_groups/](pts_robustness/p09_same_url_across_groups/EXPECT.md) |
| p10_single_segment | 单段 playlist | [pts_robustness/p10_single_segment/](pts_robustness/p10_single_segment/EXPECT.md) |
| p11_boundary_then_odd | 边界后接奇数段 | [pts_robustness/p11_boundary_then_odd/](pts_robustness/p11_boundary_then_odd/EXPECT.md) |
| p12_odd_first_in_group | 组内首段为奇数长度 | [pts_robustness/p12_odd_first_in_group/](pts_robustness/p12_odd_first_in_group/EXPECT.md) |

## 4. Subtitle + Discontinuity（32 矩阵例）

| 用例ID | 结构源 | 封装 | 动作 | 倍速 | 结构源EXPECT |
| --- | --- | --- | --- | --- | --- |
| sub-W-base-pos | sk4-2x-base | TS 封装 | pos | 1x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-W-base-mid | sk4-2x-base | TS 封装 | mid | 1x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-W-base-sp | sk4-2x-base | TS 封装 | sp | 2x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-W-base-mdsp | sk4-2x-base | TS 封装 | mdsp | 2x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-E-base-pos | sk4-2x-base | HLS over fMP4 | pos | 1x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-E-base-mid | sk4-2x-base | HLS over fMP4 | mid | 1x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-E-base-sp | sk4-2x-base | HLS over fMP4 | sp | 2x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-E-base-mdsp | sk4-2x-base | HLS over fMP4 | mdsp | 2x | [sk4-2x-base/](sk4-2x-base/EXPECT.md) |
| sub-W-disc-pos | sk4-2x-disc | TS 封装 | pos | 1x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-W-disc-mid | sk4-2x-disc | TS 封装 | mid | 1x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-W-disc-sp | sk4-2x-disc | TS 封装 | sp | 2x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-W-disc-mdsp | sk4-2x-disc | TS 封装 | mdsp | 2x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-E-disc-pos | sk4-2x-disc | HLS over fMP4 | pos | 1x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-E-disc-mid | sk4-2x-disc | HLS over fMP4 | mid | 1x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-E-disc-sp | sk4-2x-disc | HLS over fMP4 | sp | 2x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-E-disc-mdsp | sk4-2x-disc | HLS over fMP4 | mdsp | 2x | [sk4-2x-disc/](sk4-2x-disc/EXPECT.md) |
| sub-W-jump-pos | sk4-2x-jump | TS 封装 | pos | 1x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-W-jump-mid | sk4-2x-jump | TS 封装 | mid | 1x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-W-jump-sp | sk4-2x-jump | TS 封装 | sp | 2x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-W-jump-mdsp | sk4-2x-jump | TS 封装 | mdsp | 2x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-E-jump-pos | sk4-2x-jump | HLS over fMP4 | pos | 1x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-E-jump-mid | sk4-2x-jump | HLS over fMP4 | mid | 1x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-E-jump-sp | sk4-2x-jump | HLS over fMP4 | sp | 2x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-E-jump-mdsp | sk4-2x-jump | HLS over fMP4 | mdsp | 2x | [sk4-2x-jump/](sk4-2x-jump/EXPECT.md) |
| sub-W-mixres-pos | sk4-2x-mixres | TS 封装 | pos | 1x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-W-mixres-mid | sk4-2x-mixres | TS 封装 | mid | 1x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-W-mixres-sp | sk4-2x-mixres | TS 封装 | sp | 2x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-W-mixres-mdsp | sk4-2x-mixres | TS 封装 | mdsp | 2x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-E-mixres-pos | sk4-2x-mixres | HLS over fMP4 | pos | 1x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-E-mixres-mid | sk4-2x-mixres | HLS over fMP4 | mid | 1x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-E-mixres-sp | sk4-2x-mixres | HLS over fMP4 | sp | 2x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |
| sub-E-mixres-mdsp | sk4-2x-mixres | HLS over fMP4 | mdsp | 2x | [sk4-2x-mixres/](sk4-2x-mixres/EXPECT.md) |

> **前置**：ffmpeg HLS 默认把字幕 playlist 置 `needed=0`/`discard=AVDISCARD_ALL`，必须经 `mpv.conf` 启用 `sid=1`+`sub-visibility=yes`（脚本已内置 `ensure_subtitle_conf()` 自动推送）。

> **已修复（2026-09-25）**：开播即 seek 时字幕不会被拉取（根因 `hls_read_seek` 对字幕 playlist 映射 `cur_seq_no` 越界）。修复后 `hls_read_seek` 对 `is_subtitle` playlist 从首段重新读取，32 例字幕断言已全部通过。


## 5. 修复回归用例（PDT / codec-change / seek-EPERM）

针对两个 ffmpeg HLS 修复提交的定向回归：`b9872d9043`（跨 discontinuity seek 定位 + playlist
duration 用段时长之和）与 `672964c02f`（forward-seek 越界守卫改用 rebase 后的 `base`，消除
跨 discontinuity 编解码器切换时正向 seek 的 EPERM 冻结）。判据脚本 `assert_pdt_codecchange_device.sh`。

| 用例 | 场景 | 解码器重建(视/音) | 时长s | 头条修复断言 | EXPECT.md |
| --- | --- | --- | --- | --- | --- |
| case26-pdt-offset | PDT 30s 偏移 + 第一片 8.33s（seg2=h264 720x480） | 视频1 / 音频0（PDT 30s 缺口固有） | 13.46 | duration=段之和（非 35.125 PDT 跨度） | [case26-pdt-offset/](case26-pdt-offset/EXPECT.md) |
| case27-pdt-offset-start0 | PDT 30s 偏移 + 第一片更短 4.55s（覆盖首段时长边界） | 视频1 / 音频0（PDT 30s 缺口固有） | 9.68 | duration=段之和（非 30.675 PDT 跨度） | [case27-pdt-offset-start0/](case27-pdt-offset-start0/EXPECT.md) |
| case28-codec-change | 跨 DISCONT 编解码器切换 h264→mpeg2（seg2=mpeg2 640x360） | 视频0 / 音频0 | 10.33 | 正向 seek 3s→9s **不再 EPERM 冻结**（672964c02f）；开播即定位 9s 播放 seg2 1.37s | [case28-codec-change/](case28-codec-change/EXPECT.md) |

> **已验证（2026-09-27，真机 AWSSUT4104001920，含修复的 debug APK）**：
> - **PDT duration 修复**：case26/27 播放时长 = 段时长之和（13.5 / 9.7），而非 PDT 跨度（35 / 30.7）→ 修复生效。
> - **codec-change EPERM 冻结修复**：case28 中途 3s→9s 正向 seek，`EPERM/seek 失败 == 0`、`handled cmd=seek value=9` 出现、seg2(MPEG2) 被正确打开、全局 `event: end-file` 到达（修复前 EPERM → 冻结 → 永不到达）。
> - **已知残留（独立 follow-up，不在 672964c02f 守卫范围）**：case28 中途广播 seek 打开 seg2 后落在其末尾（0 帧）；开播即定位（`--ei position 9000`）则正确播放 seg2 1.37s（该设备无 mpeg2 硬解，回退软解 yuv420p）。PDT 用例因 30s 缺口在边界 reset 一次音频时钟 + 视频 `cut into a new one` 重建 1 次，A/V 不同步=0、播放完整，属 PDT 缺口固有行为，非回归。

## 判定标准速查

- **Discontinuity**：播放时长≈期望(±3s)；硬解报错=0；软解回退=0；持续硬解；音频PTS真回退=0；Reset playback=0；end-file(播放完整结束)=1；视频/音频重建==期望；分辨率/音频识别==期望；A/V不同步=0（音频参数切换类为已知抖动观察项）。
- **Seek**：A/V不同步=0（头条）；Reset playback=0；音频PTS真回退=0；seek后播放时长 near (total-lastseek)/speed(±6s)；硬解健康；mixres 识别 1280x720。
- **pts_robustness**：段完整(请求段数==m3u8段数)；duration↔EOF 对应；无网络失败；desync=0；音频PTS真回退=0；硬解报错=0。
- **Subtitle**：字幕被拉取(sub_en)≥1（须 mpv.conf 启用 sid=1/sub-visibility=yes）；字幕轨识别≥1；A/V不同步=0；Reset playback=0；音频PTS真回退=0；播放完整；硬解健康；mixres 用 `VO: [mediacodec_embed]` 行识别 1280x720 与 1920x1080（seek 拉字幕问题已修复）。


## 如何运行全套回归

```bash
cd hls_discontinuity_tests
bash assert_cases_device.sh            # 1) discontinuity 25 例（非倍速）
bash assert_seek_cases_device.sh         # 2) seek 交叉（Tier1 1× 无需 DEBUG；mid/2× 需 DEBUG apk）
bash assert_pts_robustness_device.sh     # 3) pts_robustness 12 例
bash assert_subtitle_cases_device.sh     # 4) subtitle 32 例（需 DEBUG apk）
bash assert_pdt_codecchange_device.sh      # 5) 修复回归 3 例（PDT/codec-change/seek-EPERM，需 DEBUG apk）
# 进度落盘版：run_progress.sh {cases|seek|subtitle} [用例...]
```
