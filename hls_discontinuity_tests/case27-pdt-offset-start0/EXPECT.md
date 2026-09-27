# case27-pdt-offset-start0 — PDT 偏移（首段更短）下的跨 discontinuity rebase

case26 的对照例：首段换成 `sample-mediaevents-sd0.ts`（4.55s）而不是 8.333s，使 seg1 的
`first_timestamp` 与 rebase 后的 `timeline_offset` 关系不同（gap ≈ 25.45s），用于覆盖
「首段时长较短」这一边界；验证同样的 PDT rebase 与 duration 修复仍然成立。

## 目的

PDT 回归用例第 2 例：与 case26 唯一差别是首段时长（4.55s vs 8.333s），从而改变 rebase 偏移
基数。验证 PDT 时间轴重建对首段时长不敏感、duration 仍取段时长之和。

## 特征（构造）

- 两片，断点在中间，每片各带 `EXT-X-PROGRAM-DATE-TIME`
- seg1：`sample-mediaevents-sd0.ts`（h264 720x480 / aac 48000，4.55s）
- seg2：`sintel-trailer0.ts`（h264 720x480 / aac 48000，5.125s）
- 两段编码格式一致，仅时间戳/PDT 变化
- PDT gap：30s − 4.55s ⇒ rebase 后 `timeline_offset ≈ 25.45s`

## 预期

| 项 | 预期 |
|---|---|
| 分组 | 1 个断点（2 组） |
| 解码器重建 | 视频 **0** / 音频 **0**（rebase 修复后 discontinuity 不再重建解码器；30s PDT 缺口仅令音频时钟 reset 一次，视频不再 `cut into a new one`；A/V 不同步=0、播放完整，非回归） |
| 时间轴 | rebase 后连续，dts 回退 0 |
| 总时长 | **9.675s**（= 4.55 + 5.125；**不是** PDT 跨度 30.675s） |
| 完整性 | 视频帧 **259** / 音频包 **448**（= 136+123 / 211+237） |
| 真机播放时长 | ≈ **9.68s**（±3s） |
| 跨 discontinuity 正向 seek | 跳到 ~7s 仍定位正确，不 EPERM |

## 如何判定成功

### L1（host）

- dts 回退数 == 0；总时长 == 9.675s（±0.30s）
- 完整性：视频 259 / 音频 448 == 各段之和

### L2（真机）

- 播放时长：`playback-restart → end-file` 墙钟差 ≈ 9.68s（±3s）
- 硬解报错 == 0；回退软解 == 0；持续硬解 ≥ 1
- 音频 PTS 真回退 == 0；时间轴重置 == 1（PDT 30s 缺口固有：边界处音频时钟 reset 一次）
- `event: end-file` == 1；视频重建 == 0 / 音频重建 == 0（rebase 修复后 discontinuity 不再重建解码器；PDT 缺口仅音频时钟 reset 一次）；`desynchronisation` == 0

## 运行

```bash
cd hls_discontinuity_tests
bash assert_pdt_codecchange_device.sh case27-pdt-offset-start0
```
