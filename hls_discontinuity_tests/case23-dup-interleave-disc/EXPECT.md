# case23-dup-interleave-disc — 间隔重复 A B A B, 每次带 DISCONT

间隔重复（A B A B）且每次带 DISCONT 的完整性压力。

## 目的

discontinuity 套件用例之一：间隔重复（A B A B）且每次带 DISCONT 的完整性压力。

## 特征（构造）

- A、B 两段间隔重复（A B A B），每段都带 DISCONT
- 跨组交替重复

## 预期

| 项 | 预期 |
|---|---|
| 分组 | 按 DISCONTINUITY 标记切组（本例断点数见特征） |
| 解码器重建 | 视频 **0** 次 / 音频 **0** 次（rebase 修复后 discontinuity 不再重建解码器） |
| 历史期望表(仅对照) | 视频 0 / 音频 0（修复前语义，已失效） |
| 时间轴 | rebase 后连续，dts 回退 0（音频 PTS 真回退 = 0） |
| 完整性 | 视频帧 **1410** / 音频包 **2430**（= 各段之和） |
| 真机 | 播到 EOF，播放时长 ≈ **56.68s** |

> 注：视频/音频重建均 0；4 段全部完整播完、dts 不回退。

> 说明：用例资料里的「重建次数」为修复前期望；当前真机判据为视频/音频重建次数均 == 0，重建次数列仅作历史对照。

## 如何判定成功

### L1（host，`assert_cases.sh`，ffmpeg/ffprobe 离线）

- 时间轴：每条流 **dts 回退数 == 0**
- 总时长：== 各段之和（±0.30s），空洞/重叠都算失败
- 完整性：视频帧数、音频包数 == 各段之和（少一帧即失败）
- 通告条数：== 断点数 × 2（每条流一条）
- 格式识别：期望新格式必须出现 `Reinit context to <新分辨率>`；其余用例不得出现预期外分辨率

### L2（真机，`assert_cases_device.sh`，mpv-android2 / mediacodec）

- 播放时长：`event: playback-restart → event: end-file` 墙钟差 == 56.68s（±3s）
- 硬解报错：`Error while decoding frame` == 0
- 回退软解：`Using software decoding` == 0
- 持续硬解：`Using hardware decoding` ≥ 1
- 音频 PTS 真回退（`Invalid audio PTS` 后值 < 前值）：== 0
- 时间轴重置：`Reset playback due to audio timestamp` == 0
- 完整性：`event: end-file`（播放完整结束）== 1
- 视频重建次数（`[vd:v] The stream is cut into a new one`）== 0；音频重建次数（`[ad:v] The stream is cut into a new one`）== 0（rebase 修复后 discontinuity 不再重建解码器）
- A/V 不同步：`desynchronisation` == 0（**其余用例均严格 0，无放宽**）

## 运行

```bash
cd hls_discontinuity_tests
bash assert_cases_device.sh case23-dup-interleave-disc   # 单例
# 或 bash assert_cases_device.sh         # 全量 25 例
```

> 判据坑（已踩）：视频重建必须只匹配 `[vd:v]`，音频侧 `[ad:v]` 也会打印同一句；`Invalid audio PTS` 前进跳变无害，只有后值<前值才算回退。
