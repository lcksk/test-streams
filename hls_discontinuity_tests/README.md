# HLS discontinuity 测试集（以 rmdmy 为 base）

## 素材

| 角色 | 文件 | 规格 |
|---|---|---|
| base | `rmdmy/009.ts … 029.ts`（21 片，时间戳本来连续：91.5s 起） | h264 **1280x720** High@31 + aac **44100/2ch** |
| 格式不连续段 | `000.ts`（10.513s） | h264 **640x360** High@30 + aac 44100/2ch（**视频变、音频不变**） |
| 派生素材 | `_derived/`（18 个） | 音频转 22050Hz/mono 的段、各类 `-output_ts_offset` 时间戳偏移段 |

派生靠 `ffmpeg -c copy -output_ts_offset <t> -f mpegts -muxdelay 0 -muxpreload 0` 生成：
不重编码，只改时间戳，用来把"格式变化"和"时间戳跳变"两个变量**隔离**开。

## 目录

```
README.md                本文件
assert_cases.sh          L1 断言（host ffmpeg/ffprobe，自动跑，约 3 分钟）
assert_cases_device.sh   L2 断言（手机真机 mpv-android2，自动跑，约 25 分钟）
case01 … case25/         25 个用例，每个含 index.m3u8 + EXPECT.md（含实测）
_derived/                派生素材（由 base 与 000.ts 生成，勿手工改）
rmdmy/ 000.ts            原始素材
```

## 用例总表

| # | 用例 | 场景 | 视频重建 | 音频重建 | 时长s | 视频帧/音频包 |
|---|---|---|---|---|---|---|
| 01 | fmt-head | 格式不连续在**最前** | 1 | 0 | 38.85 | 1019/1665 |
| 02 | fmt-mid | 格式不连续在**中间**（含变回来） | 2 | 0 | 38.85 | 1019/1665 |
| 03 | fmt-tail | 格式不连续在**最后** | 1 | 0 | 38.85 | 1019/1665 |
| 04 | video-only | **只有视频变**（时间戳已对齐） | 1 | 0 | 20.59 | 564/881 |
| 05 | audio-only | **只有音频变**（22050/mono，已对齐） | 0 | 1 | 20.19 | 500/648 |
| 06 | audio-head | 音频变在**最前** | 0 | 1 | 38.46 | 955/1432 |
| 07 | ts-jump-fwd | 时间戳**向前跳** +98s（格式不变） | 0 | 0 | 28.34 | 705/1215 |
| 08 | ts-jump-back | 时间戳**向后跳** -82s | 0 | 0 | 28.34 | 705/1215 |
| 09 | ts-restart | 第二组时间戳**归零**（最常见） | 0 | 0 | 28.34 | 705/1215 |
| 10 | ts-only | 打 DISCONT 但时间戳**本就连续** | 0 | 0 | 35.80 | 890/1533 |
| 11 | multi-disc | 4 片，每片之间都 DISCONT | 0 | 0 | 40.32 | 1003/1728 |
| 12 | fmt-and-ts | 格式变 + 时间戳跳**同时** | 1 | 0 | 20.59 | 564/881 |
| 13 | disc-at-start | m3u8 开头就 DISCONT | 0 | 0 | 28.34 | 705/1215 |
| 14 | disc-every-ts-fwd | **每片都 DISCONT**，时间戳**逐次前跳** | 0 | 0 | 40.32 | 1003/1728 |
| 15 | disc-every-ts-alt | **每片都 DISCONT**，时间戳**前后交替跳** | 0 | 0 | 40.32 | 1003/1728 |
| 16 | disc-every-fmt-alt | **每片都 DISCONT**，**格式交替** 720/360/720/360 | 3 | 0 | 49.36 | 1333/2115 |
| 17 | disc-every-audio-alt | **每片都 DISCONT**，**音频参数交替** | 0 | 3 | 48.58 | 1205/1649 |
| 18 | cross-all | **交叉**：视频变+前跳 → 音频变+前跳 → 都变回+后跳 | 2 | 2 | 48.97 | 1269/1882 |
| 19 | disc-every-plain | **6 片每片都 DISCONT**，什么都不变（压力） | 0 | 0 | 66.14 | 1645/2834 |
| 20 | dup-repeat-disc | **同一分片重复 3 次**，每次带 DISCONT | 0 | 0 | 30.22 | 750/1293 |
| 21 | dup-repeat-nodisc | 同一分片重复 3 次，**【不带】DISCONT**（对照） | 0 | 0 | 30.22 | 750/1293 |
| 22 | dup-repeat-offset | 同一分片重复 3 次，带 DISCONT 且时间戳递增 | 0 | 0 | 30.22 | 750/1293 |
| 23 | dup-interleave-disc | **间隔重复 A B A B**，每次带 DISCONT | 0 | 0 | 56.68 | 1410/2430 |
| 24 | dup-then-fmt | 先重复同格式段（000×2），再切到 720p | **1** | 0 | 31.10 | 878/1331 |
| 25 | dup-mixed-ts | 同一分片重复 + 时间戳先后跳、再前跳 | 0 | 0 | 30.22 | 750/1293 |

## 成功 / 失败判定条件

### L1（host，`./assert_cases.sh`）——每条不通过即 FAIL

| 判据 | 通过条件 |
|---|---|
| 时间轴 | 每条流 **dts 回退数 == 0** |
| 总时长 | == 各段之和（±0.30s）——空洞/重叠都算失败 |
| 完整性 | 视频帧数、音频包数 == 各段之和（**少一帧即失败**） |
| 通告条数 | == 断点数 × 2（每条流一条） |
| 格式识别 | 期望新格式的用例必须出现 `Reinit context to <新分辨率>`；其余用例不得出现 1280x720 以外的分辨率 |

### L2（手机真机，`./assert_cases_device.sh`）

| 判据 | 通过条件 | 失败含义 |
|---|---|---|
| 播放时长 | `playback restart complete → video EOF` 的墙钟差 == 期望（±3s） | 提前结束 = 丢包/卡住；超时 = 卡死 |
| 硬解报错 | `Error while decoding frame` **== 0** | 硬解路径坏了（第三轮修的就是这个） |
| 回退软解 | `Using software decoding` **== 0** | 重建后没能继续硬解 |
| 持续硬解 | `Using hardware decoding` **≥ 1** | 根本没走硬解 |
| 音频 PTS | **真回退**（`Invalid audio PTS` 中后值 < 前值）== 0 | 时间轴倒退 |
| 时间轴重置 | `Reset playback due to audio timestamp` == 0 | 播放被整体重置（"回到 0"症状） |
| 完整性 | `audio EOF` 与 `video EOF` 各 == 1 | 没播完 |
| 视频重建次数 | == 期望（格式变才重建） | 该重建没重建 / 不该重建却重建 |
| 音频重建次数 | == 期望（音频参数变才重建） | 同上 |
| 分辨率识别 | `Decoder format: 640x360` 出现次数 == 段数 | 格式变化没被识别 |
| 音频识别 | `AO: [audiotrack] 22050Hz mono` ≥ 1 | 音频参数变化没被识别 |
| A/V 不同步告警 | `Audio/Video desynchronisation detected` == 0（音频参数切换类设为观察项） | 一次 >0.5s 的 A/V 偏差（见下"第四批发现"） |

## 重复分片组（case20–25）的核心结论

**case20 vs case21 是一对照**，同样的"同一分片重复 3 次"：

| | case20（**带** DISCONT） | case21（**不带** DISCONT） |
|---|---|---|
| 分组 | 3 组 | 1 组（没标记就不切组） |
| 通告 | 4 条 | **0 条** |
| dts 回退 | **0** | **4**（host 实测） |
| 真机音频回退 | 0 | **2** |
| 真机 `Reset playback` | 0 | **2 次** ← 就是"播放回到 0"的症状 |

即：**没打 DISCONTINUITY 的重复分片会让播放器把时间轴打回起点**（真实世界里"回看拼接/生成脚本 bug"就是这么产生的）。打了标记后完全连续。case21 在断言里设为**观察项**（`any`），它的"回退/重置"是预期现象而非失败。

### 三个判据坑（已踩过，勿重踩）

1. **`The stream is cut into a new one` 音频侧也打印**（`[ad:v]`）。统计视频重建必须只匹配
   `[vd:v]`，否则 case05/06/17/18 会全部误报（实测 case18 正好是 2×`[vd]` + 2×`[ad]`）。
2. **mpv 的 `Invalid audio PTS` 不是"回退"告警**，而是 |跳变| > 0.1s 的告警，**前进也打印**
   （case03 实测 `28.212 → 28.338` 是 +0.126s 前进，无害）。只有"后值 < 前值"才算失败。
3. **HTTP 服务 / app 启动偶发抖动**：曾让一轮里 13/14 用例一开播就 `EOF reached`（假失败，单跑全过）；
   以及 `am start` 的 intent 偶发未被 app 接收（mpv 停在 `event: idle`，日志里没有 `Opening http`）。
   脚本已加双重健壮性：① `am start` 后**轮询日志直到出现 `Opening http`**，否则 force-stop 重启（最多 3 次）；
   ② 用例判定失败**自动重试一次**。若仍失败，先 `curl` 验服务再判定。
4. 真机上 `Decoder format: <新分辨率>` 只在新格式**首次出现**时打印——同格式重复段
   （case24 的 000×2）不会重复打印，期望次数按"格式变化次数"而非"段数"填。
5. **A/V 不同步告警**（`Audio/Video desynchronisation detected`）：触发条件是 `|A-V| > 0.5s`
   （`player/video.c:660`），且只打印一次。仅"音频参数切换"类用例（case06/17）会出现一次
   —— 因为 Android AudioTrack 重配瞬间会偏差。其余 23 个用例全为 0，说明 discontinuity
   修复**未引入** A/V 偏差。这类用例标为观察项打印实测，其余严格为 0。

## 怎么跑

```bash
cd /home/lck/work/webroot/hls_discontinuity_tests
./assert_cases.sh              # L1：host 自动，约 3 分钟
./assert_cases_device.sh       # L2：手机真机自动，约 16 分钟（adb 已连上即可）
./assert_cases_device.sh case18   # 只跑单个用例
```

真机脚本会为每个用例：`am force-stop` → `am start <url> --ei position 0` → 流式抓
`adb logcat -s mpv` → 等 `时长+15s` → 按上表逐条判定。日志落在 `/tmp/dev_cases/<用例>.log`。

> 注意：脚本用 `while read` 读用例表，循环里的 `adb shell` / `adb logcat` 必须加
> `</dev/null`，否则它们会把用例表当输入吃掉，只跑第一个用例就结束。

## 当前状态（2026-09-19）

- L1（host）：**25/25 全部通过**
- L2（真机 ALP-AN00 + mpv-android2 + mediacodec）：**25/25 全部通过，全量 287 项断言全绿、0 失败**
  （最终结果见 `/tmp/dev_final.log`；A/V 不同步告警仅 case17 出现 1 次，属预期内的 AudioTrack 重配抖动）
- 每个用例的 `EXPECT.md` 里都附了真机实测数据
- 失败 case 的完整 RED→GREEN 复盘见 `FAILURE-ANALYSIS.md`（结论：无一项是产品缺陷，全是判据/环境/对照现象）

## seek + discontinuity 扩展（8K 长片，覆盖跨边界 seek）

原 25 例只测"开播到 EOF"的 discontinuity 处理，没覆盖"seek（尤其跨 DISCONTINUITY 边界）"。
扩展套件见 **`seek_cases.md`**：用 `hls_dump_file_6/7/8.ts` 构造 sk0-base / sk1-disc / sk2-disc-jump / sk3-mixres 四个 8K 长源，
含 Tier1 起播即 seek、Tier2 真中途 seek（app 加 `DebugCmdReceiver`）、2× 变速 + seek，头条断言 A/V 不同步 == 0。
构造 `./build_seek_sources.sh`、L1 `./assert_seek_cases.sh`、L2 `./assert_seek_cases_device.sh`。
