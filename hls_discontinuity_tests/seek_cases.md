# seek + discontinuity 测试套件（8K 长片 + 跨边界 seek）

在原有 25 个 discontinuity 用例基础上补充 **seek** 维度：原 25 例只验证"开播到 EOF 的 discontinuity 处理"，
完全没覆盖"播放中 / 开播即跳到某个位置（尤其跨 DISCONTINUITY 边界）"的健壮性。

## 素材

三个同源 8K 片（均 7680×4320 / 30fps / HE-AAC 48000 stereo）：

| 文件 | 时长 | 原始 start |
|---|---|---|
| hls_dump_file_6.ts | 10.562s | 57.671 |
| hls_dump_file_7.ts | 8.809s  | 68.124 |
| hls_dump_file_8.ts | 10.038s | 76.828 |

另用 `rmdmy/009.ts`（1280×720 h264 / aac 44100 stereo）作为 720p 段。

## 构造的源（`./build_seek_sources.sh` 一键生成，全部 `-c copy` 不重编码）

| 源 | 组成 | DISCONT | 时长 | 边界 |
|---|---|---|---|---|
| **sk0-base** | 6+7+8 连续拼成单文件，无 DISCONT | 0 | 29.41s | 无 |
| **sk1-disc** | 6 `#D` 7 `#D` 8，时间戳连续**递增**（段间衔接） | 2 | 29.41s | 10.562 / 19.371 |
| **sk2-disc-jump** | 6 `#D` 7(+60s) `#D` 8(+120s)，DISCONT + 时间戳大跳 | 2 | 29.41s | 10.562 / 19.371（时间戳跳到 60/120） |
| **sk3-mixres** | 8K(6) `#D` 720p(009) `#D` 8K(8)，分辨率交替 + DISCONT | 2 | 30.67s | 10.562 / 20.635 |

> **构造坑（已踩，已修）**：mpegts 段若用负 `-output_ts_offset` rebase 到 0，会造成 DISCONT 之后时间戳从段末**回落到 0（递减）**——
> 这种"每段归零 + DISCONT"的流会让 mpv 的 seek 失效。正确做法是让各段时间戳**单调递增衔接**（段间连续）。
> 另外：seek 目标**精确等于** discontinuity 边界会退化成立即 EOF，故边界用例取"边界 +0.1s"段内位置。

## 测试矩阵（device，共 25 例）

- **Tier1 起播即 seek**（`--ei position`，现有 app 已支持，无需重编）：sk0/sk1/sk2/sk3 各取段内多个位置（边界前 / 边界后 / 段中 / 近 EOF）。
- **Tier2 真·中途 seek**（需 DEBUG 构建 + `DebugCmdReceiver`）：播放中发 `seek` 广播，含多段双向拖动（3→20→10→8）、向后拖动（26→3）。
- **2× 变速 + seek**（Tier1/Tier2 各若干）：贴合 tunnel 分支主题，2× 下 seek 最易爆 A/V 不同步。

完整用例表见 `assert_seek_cases_device.sh` 顶部 `CASES`。

## 断言

- **L1（host）**：`./assert_seek_cases.sh` — dts 不回退、总时长==各段和、帧/包数==各段和、DISCONT 通告数==边界×2、SK3 识别到 1280x720 reinit。
  > 注：跨分辨率 playlist（SK3）下 ffprobe 的 `nb_read_frames` 会漏掉中间段（HLS reinit 测量假象），视频帧比对改为 INFO，完整性由 device L2 的 video EOF 真实验证。
- **L2（真机）**：`./assert_seek_cases_device.sh` — 头条 **A/V 不同步告警 == 0**、**Reset playback == 0**、**音频 PTS 真回退 == 0**；
  另含硬解持续、无软解回退、无解码报错、audio/video EOF 各==1、seek 后播放时长≈剩余、SK3 识别 1280x720。

## 运行

```bash
cd /home/lck/work/webroot/hls_discontinuity_tests
./build_seek_sources.sh            # 生成 SK0..SK3
./assert_seek_cases.sh            # L1（host）
./assert_seek_cases_device.sh     # L2（真机，需 DEBUG 构建已装 + HTTP 服务可达）
./assert_seek_cases_device.sh sk-pos-01b   # 只跑单个用例
```

L2 前置：安装含 `DebugCmdReceiver` 的 **DEBUG** apk（仅 DEBUG 注册，生产构建不暴露）；HTTP 服务在
`http://192.168.3.24/hls_discontinuity_tests` 可访问 `sk*/index.m3u8`。

## 当前状态 / 已知发现（2026-09-19）

- **L1：4/4 源全绿。**
- **源构造根因（已修）**：`-output_ts_offset` **传负值**会被 mpegts 夹紧成 ~0，导致每段都从 0 开始（DISCONT 后时间戳递减）。
  这种"每段归零 + DISCONT"的流会让 mpv 的 seek 落入**初期退化**（解码器停在默认 `960x540` surface、立即 `video EOF`、时间轴 NOPTS）。
  **正解**：用正值 `-output_ts_offset` 显式设置每段起点（`-muxdelay 0 -muxpreload 0` 才精确生效），使各段**单调递增衔接**：
  sk1→0/10.562/19.371，sk2→0/60/120，sk3→0/10.562/20.635，sk0 单文件连续。
- **对照验证**：真实 discontinuity 源 `case11-multi-disc`（rmdmy 段，天然递增时间戳）seek 15s 完全正常
  （硬解、`reconfig 1280x720`、`playback restart complete @ 15.026`、跨第二个 DISCONT 正常、播到 EOF）——证明**不是** mpv 的 DISCONT-seek 通用缺陷。
- **L2 Tier1（起播即 seek，无需重编）结果**：
  - sk0-base（无 DISCONT）：各位置 seek 全绿。
  - sk1-disc：seek 到 seg6(3.0) / seg8(19.6) **全绿**（硬解 8K、时长正确、播到 EOF、无重置、无回退）。
  - sk3-mixres：seek 到 720p 段内（14.0s）全绿，识别到 `1280x720`。
  - 🎯 **RED：`Audio/Video desynchronisation detected`（非 tunnel，真机可稳定复现）**
    - 判定逻辑：`player/video.c:656` → `last_av_difference = playing_audio_pts − video_pts`，**音频播放位置超前视频 >0.5s** 即告警。
    - 现象：8K seek 后跨下一个 discontinuity 边界时，音频播放位置**向前跳**（seg7 音频在 `18.199656` 处被截、直接落到 seg8 的 `19.371322`，丢约 1.02s），而视频仍在 18.x → 音频超前 1.17s → 告警。

  **对照矩阵（diag_discont_seek.sh，同一批真机）**：

  | 控制组 | 源 | DISCONT | seek | 边界音频跳变 | desync |
  |---|---|---|---|---|---|
  | C1 | sk1-disc(8K) | 有 | 无 | `19.266→19.371`(0.1s) | 0 |
  | C3 | sk0-base(8K 单文件) | **无** | 有 | `19.266→19.371`(0.1s) | 0 |
  | C5/C6/C7 | sk1-disc(8K) | 有 | 10.7/12/15 | **`18.200→19.371`(1.17s)** | **1** |
  | C9 | sk1-720p(同结构) | 有 | 无 | 无 | 0 |
  | C10/C11 | sk1-720p(同结构) | 有 | 15/12 | `20.034→28.338`(丢 8.3s) | **0** |
  | C8 | case11(真实 rmdmy 720p) | 有 | 边界后 0.13s | `20.150→28.338` | 0 |

  **结论**：
  - desync 需要 **DISCONTINUITY + seek 同时满足**（C1/C3/C9 分别缺一个条件即不复现）。
  - **非 tunnel**（用 `mediacodec` 解码器 + `mediacodec_embed` VO，无 HwAvSync）。
  - **源本身无问题**（包级音/视频 PTS 仅差 ~0.08s）。
  - 排除了解码器重建：两源在边界处均**无** `The stream is cut into a new one`/reinit（时间轴移动且无参数变化 → 不重建）。
  - **desync 不是"音频丢多少"决定的**：同结构 720p 源丢 8.3s 音频却**不** desync，8K 只丢 1.02s 却 desync → **8K 特有**，指向"8K 视频在断点处解码时序/滞后"导致 `playing_audio_pts` 相对 `video_pts` 超前。
  - ⚠️ **待定**：需在 mpv 的 `update_av_diff()`（`player/video.c:660`）加临时日志（打印 `playing_audio_pts`、`video_pts`、`last_av_difference`）并重编，判定是"音频侧超前"还是"8K 视频侧滞后"，再定位修复点。
- **Tier2 真中途 seek + 2× 变速**：需重新编译安装含 `DebugCmdReceiver` 的 DEBUG apk 后才能跑（app 代码已加，待构建）。

## DebugCmdReceiver

`app/src/main/java/is/xyz/mpv/DebugCmdReceiver.kt`：监听 `is.xyz.mpv.DEBUG_CMD` 广播，支持注入
`seek <绝对秒>` / `set speed <倍率>`。仅在 `BuildConfig.DEBUG` 下于 `MPVActivity.onCreate` 注册、`onDestroy` 注销。
测试用：`am broadcast -a is.xyz.mpv.DEBUG_CMD --es cmd seek --ef value 15.0`。
