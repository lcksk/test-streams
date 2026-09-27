# p08_last_odd_drain — 末尾为奇数长度段

最后一个段时长为奇数/非整数，测试末尾 drain；验证到 EOF 不丢尾段。

## 目的

pts_robustness 套件（见 `assert_pts_robustness_device.sh`）用例之一：验证 discontinuity **组内不一致段**是否完整播完，重点检测「丢分段 / 没播完」（段完整性 + duration↔EOF 对应）。

## 特征（构造）

- 最后一段为特殊（奇数）长度
- EOF 完整

## 预期 / 如何判定成功（L2 真机）

- **段完整**：日志请求 `.ts` 段数（按 URL 去重）== m3u8 的 #EXTINF 段数（丢几段=没播完，FAIL）
- **无网络失败**：无 `Failed to open` / `Timeout was reached`
- **播放到 EOF**：`event: end-file`（或 `Exiting.`）到达
- **duration↔EOF 对应**：实测播放时长(end-file - start-file) ≈ m3u8 #EXTINF 加总（容差约 10%~15%+2s），偏离=可能丢分段
- **A/V 不同步** `desynchronisation` == 0
- **音频 PTS 真回退** == 0（后值 < 前值才算）
- **硬解报错** `Error while decoding frame` == 0

## 运行

```bash
cd hls_discontinuity_tests
bash assert_pts_robustness_device.sh p08_last_odd_drain   # 单例
# 或 bash assert_pts_robustness_device.sh     # 全量 12 例
```
