# case26-pdt-offset — PDT 偏移下的跨 discontinuity rebase

验证 `EXT-X-PROGRAM-DATE-TIME` 在 discontinuity 处存在 30s 偏移时，时间轴按段时长 rebase、
而非按 PDT 跨度展开；并验证 playlist 总时长 = 各段时长之和（修复 b9872d9043 前会按 PDT 跨度
把时长算成 35.125s）。这是 PDT 回归套件第 1 例（第 2 例见 case27，换首段以改变 first_timestamp）。

## 目的

PDT 回归用例之一：seg1 带 `PDT=00:00:00`、seg2 带 `PDT=00:00:30`，但 seg1 实际只有 8.333s，
制造约 21.667s 的 PDT gap。验证 rebase 后时间轴连续、`timeline_offset != 0`、跨 discontinuity
seek 定位正确、且 playlist duration 取段时长之和。

## 特征（构造）

- 两片，断点在中间（`#EXT-X-DISCONTINUITY`），每片各带 `EXT-X-PROGRAM-DATE-TIME`
- seg1：`sample-mediaevents-sd1.ts`（h264 720x480 / aac 48000，8.333s）
- seg2：`sintel-trailer0.ts`（h264 720x480 / aac 48000，5.125s）
- 两段编码格式一致（仅时间戳/PDT 变化，无分辨率变化）
- PDT gap：seg2 PDT − seg1 PDT = 30s；seg1 时长 8.333s ⇒ rebase 后 `timeline_offset ≈ 21.667s`

## 预期

| 项 | 预期 |
|---|---|
| 分组 | 按 DISCONTINUITY 切 1 个断点（2 组） |
| 解码器重建 | 视频 **0** / 音频 **0**（rebase 修复后 discontinuity 不再重建解码器；30s PDT 缺口仅令音频时钟 reset 一次，视频不再 `cut into a new one`；A/V 不同步=0、播放完整，非回归） |
| 时间轴 | rebase 后连续，dts 回退 0 |
| 总时长 | **13.458s**（= 8.333 + 5.125，段时长之和；**不是** PDT 跨度 35.125s） |
| 完整性 | 视频帧 **373** / 音频包 **627**（= 各段之和：250+123 / 390+237） |
| 真机播放时长 | `playback-restart → end-file` 墙钟 ≈ **13.46s**（±3s） |
| 跨 discontinuity 正向 seek | 跳到 ~10s 仍定位到 seg2 正确位置，不 EPERM、不回退非可定位 HTTP |

> 注：总时长判据直接验证了 b9872d9043——若 duration 仍按 PDT 跨度计，真机将等待 ~35s 而非 13.5s。

## 如何判定成功

### L1（host，ffmpeg/ffprobe 离线）

- 时间轴：每条流 **dts 回退数 == 0**
- 总时长：== 各段之和 13.458s（±0.30s）；若 == 35.125s 即为回归未修复
- 完整性：视频帧数 373 / 音频包数 627 == 各段之和
- 格式识别：无预期外分辨率（始终 720x480）

### L2（真机，mpv-android2 / mediacodec）

- 播放时长：`event: playback-restart → event: end-file` 墙钟差 ≈ 13.46s（±3s）
- 硬解报错：`Error while decoding frame` == 0
- 回退软解：`Using software decoding` == 0
- 持续硬解：`Using hardware decoding` ≥ 1
- 音频 PTS 真回退（`Invalid audio PTS` 后值 < 前值）：== 0
- 时间轴重置：`Reset playback due to audio timestamp` == 1（PDT 30s 缺口固有：边界处音频时钟 reset 一次）
- 完整性：`event: end-file`（播放完整结束）== 1
- 视频重建 == 0 / 音频重建 == 0（rebase 修复后 discontinuity 不再重建解码器；PDT 缺口仅音频时钟 reset 一次）
- A/V 不同步：`desynchronisation` == 0

## 运行

```bash
cd hls_discontinuity_tests
bash assert_pdt_codecchange_device.sh case26-pdt-offset   # 单例
# 或 bash assert_pdt_codecchange_device.sh                # 3 例全跑
```
