# case28-codec-change — 跨 discontinuity 编解码器切换的正向 seek（EPERM 回归）

原始 fail case：seg1 为 h264、seg2 切换为 **MPEG2**（分辨率/编码均变），discontinuity 处
rebase 后 `timeline_offset ≈ 5.95s`。修复前 `hls_read_seek` 的越界守卫用 `first_timestamp`
（raw 域）而非 rebase 后的 `base` 比较，对本例错误地返回 EIO → mpv 回退到非可定位 HTTP 的
通用 seek → **EPERM**，于是正向 seek（3s→9s）后 POS 卡在 ~3.12s 不动。修复（672964c02f）后
守卫改用 `base`，正向 seek 正常。

## 目的

codec-change 回归用例（头条）：验证跨 discontinuity、且 seg2 编解码器不同（h264→mpeg2）时，
正向 seek 能正确定位并继续播放到 EOF，不再 EPERM 冻结。

## 特征（构造）

- 两片，断点在中间（`#EXT-X-DISCONTINUITY`）
- seg1：`sample-mediaevents-sd1.ts`（h264 720x480 / aac 48000，8.333s）
- seg2：`case-codec-chg.ts`（**mpeg2video** 640x360 / aac 44100 mono，2.0s）
- 编码格式在断点处变化（视频 codec + 分辨率 + 音频采样率/声道均变）

## 预期

| 项 | 预期 |
|---|---|
| 分组 | 1 个断点（2 组） |
| 解码器重建 | 视频 **0** / 音频 **0**（rebase 路径，不重建） |
| 时间轴 | rebase 后连续，dts 回退 0 |
| 总时长 | **10.333s**（= 8.333 + 2.0） |
| 完整性 | 视频帧 **300** / 音频包 **478**（= 250+50 / 390+88） |
| 真机·正向 seek 头条（已验证修复） | 中途 3s→9s 正向 seek：**不再 EPERM 冻结**（修复 672964c02f）；`handled cmd=seek value=9` 出现、seg2(MPEG2) 被正确打开、全局 `event: end-file` 到达（修复前 EPERM → 冻结 → 永不到达） |
| 真机·mid-seek 残留（follow-up） | 中途广播 seek 打开 seg2 后落在其末尾（0 帧），未真正渲染 seg2；**开播即定位**（`--ei position 9000`）则正确播放 seg2 1.37s（该设备无 mpeg2 硬解，回退软解 yuv420p）。该 mid-seek 定位残留属独立的 seek 定位问题，不在 672964c02f 的 EPERM 守卫范围内 |
| 真机播放总时长 | 开播即定位 9s：`playback-restart → end-file` ≈ 1.37s（=10.33−9）；mid-seek 在残留下 ≈ 0.1s（落 seg2 EOF，观察项） |

## 如何判定成功

### L1（host）

- dts 回退数 == 0；总时长 == 10.333s（±0.30s）
- 完整性：视频 300 / 音频 478 == 各段之和
- 格式识别：出现 `mpeg2video` 且 seg2 为 640x360（编解码器切换被正确识别，但走 rebase 不重建）

### L2（真机，头条：正向 seek 不 EPERM）

- 正向 seek（broadcast `cmd=seek value=9`）后日志出现 `handled cmd=seek value=9`
- **无 EPERM / 无 freeze（头条修复）**：`EPERM|Operation not permitted|Could not seek` == 0；`event: end-file` 在 seek 后到达（修复前 EPERM 冻结 → 永不到达）；POS 不卡在 ~3.12s
- `Reset playback due to audio timestamp` == 0；视频/音频重建 == 0；A/V 不同步 == 0
- 硬解报错 == 0；回退软解 == 0；持续硬解 ≥ 1
- 音频 PTS 真回退 == 0；`event: end-file` == 1
- mid-seek 播放时长（观察项）：落 seg2 EOF ≈ 0.1s；对照开播即定位 9s 为 1.37s（软解 mpeg2）

> 判据坑（已踩）：修复前此例正向 seek 后 POS 停在 3.12s 不动（EPERM 回退到非可定位 HTTP），
> `end-file` 永不到达、墙钟超时；修复后必须看到 end-file 且时长合理。

## 运行

```bash
cd hls_discontinuity_tests
bash assert_pdt_codecchange_device.sh case28-codec-change   # 含正向 seek 9s
```
