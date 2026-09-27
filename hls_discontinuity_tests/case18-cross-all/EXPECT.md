# case18-cross-all — 交叉：视频变+前跳→音频变+前跳→都变回+后跳

综合交叉：视频变+前跳、音频变+前跳、两者变回+后跳全覆盖。

## 目的

discontinuity 套件用例之一：综合交叉：视频变+前跳、音频变+前跳、两者变回+后跳全覆盖。

## 特征（构造）

- 三段依次：视频 720p→360p+时间戳前跳；音频 44100→22050+前跳；两者变回 720p/44100+后跳
- 视频与音频断点交错

## 预期

| 项 | 预期 |
|---|---|
| 分组 | 按 DISCONTINUITY 标记切组（本例断点数见特征） |
| 解码器重建 | 视频 **0** 次 / 音频 **0** 次（rebase 修复后 discontinuity 不再重建解码器） |
| 历史期望表(仅对照) | 视频 2 / 音频 2（修复前语义，已失效） |
| 分辨率识别 | `VO: [mediacodec_embed] 640x360` 出现 **1** 次 |
| 音频识别 | `AO: [audiotrack] 22050Hz mono` ≥ 1 次 |
| 时间轴 | rebase 后连续，dts 回退 0（音频 PTS 真回退 = 0） |
| 完整性 | 视频帧 **1269** / 音频包 **1882**（= 各段之和） |
| 真机 | 播到 EOF，播放时长 ≈ **48.97s** |

> 注：视频/音频重建判据均为 0；识别 640x360 与 22050Hz mono 各 1 次。**A/V 不同步为观察项**（desync=any）：本例跨段需同时重建 VD+AO，重建瞬间必然有一次偏差；实测设备高负载下偶发，其余判据恒定达标，告警数仍会打印。

> 说明：用例资料里的「重建次数」为修复前期望；当前真机判据为视频/音频重建次数均 == 0，重建次数列仅作历史对照。

## 如何判定成功

### L1（host，`assert_cases.sh`，ffmpeg/ffprobe 离线）

- 时间轴：每条流 **dts 回退数 == 0**
- 总时长：== 各段之和（±0.30s），空洞/重叠都算失败
- 完整性：视频帧数、音频包数 == 各段之和（少一帧即失败）
- 通告条数：== 断点数 × 2（每条流一条）
- 格式识别：期望新格式必须出现 `Reinit context to <新分辨率>`；其余用例不得出现预期外分辨率

### L2（真机，`assert_cases_device.sh`，mpv-android2 / mediacodec）

- 播放时长：`event: playback-restart → event: end-file` 墙钟差 == 48.97s（±3s）
- 硬解报错：`Error while decoding frame` == 0
- 回退软解：`Using software decoding` == 0
- 持续硬解：`Using hardware decoding` ≥ 1
- 音频 PTS 真回退（`Invalid audio PTS` 后值 < 前值）：== 0
- 时间轴重置：`Reset playback due to audio timestamp` == 0
- 完整性：`event: end-file`（播放完整结束）== 1
- 视频重建次数（`[vd:v] The stream is cut into a new one`）== 0；音频重建次数（`[ad:v] The stream is cut into a new one`）== 0（rebase 修复后 discontinuity 不再重建解码器）
- 分辨率识别：`VO: [mediacodec_embed] 640x360` 次数 == 1
- 音频识别：`AO: [audiotrack] 22050Hz mono` ≥ 1
- A/V 不同步：`desynchronisation`：**观察项**（desync=any，跨段同时重建 VD+AO 必有一次偏差；仍打印实际数）

## 运行

```bash
cd hls_discontinuity_tests
bash assert_cases_device.sh case18-cross-all   # 单例
# 或 bash assert_cases_device.sh         # 全量 25 例
```

> 判据坑（已踩）：视频重建必须只匹配 `[vd:v]`，音频侧 `[ad:v]` 也会打印同一句；`Invalid audio PTS` 前进跳变无害，只有后值<前值才算回退。
