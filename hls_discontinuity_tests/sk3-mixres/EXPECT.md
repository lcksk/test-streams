# sk3-mixres — SK3-mixres（DISCONT + 分辨率切换）

8K(6) #D 720p(009) #D 8K(8)，分辨率交替 + DISCONTINUITY。测跨分辨率断点 seek。

## 目的

seek + discontinuity 套件（见 `seek_cases.md`）的源。本目录是被多个 seek 用例复用的「源」，本身不直接判定；判定由其上叠加的 seek 场景（Tier1 起播即 seek / Tier2 真中途 seek / 2× 变速 + seek）完成。

## 源构造（特征）

- seg6(8K) rebase 0；720p(009) rebase 10.562；seg8(8K) rebase 20.635
- 段间插 DISCONT，共 2 个断点，分辨率 8K→720p→8K
- 总时长 30.67s，边界 10.562 / 20.635

## 覆盖的 seek 场景（见 `assert_seek_cases_device.sh`）

- sk-pos-03a/b/c（seek 到 3.0/14.0/24.0；14.0 落 720p 段内，期望识别 1280x720）

## 如何判定成功（L2 真机，头条断言）

- **A/V 不同步 `desynchronisation` == 0**（最关键：DISCONT + seek 同时满足才复现 desync）
- `Reset playback due to audio timestamp` == 0
- 音频 PTS 真回退（`Invalid audio PTS` 后值<前值）== 0
- 播放完整性：从 lastseek 到 `event: end-file` 实测时长 near `(total-lastseek)/speed`（容差 6s）
- 硬解健康：无 `Error while decoding frame`、无 `Using software decoding`、有 `Using hardware decoding`
- `event: end-file`（播放完整结束）== 1
- 识别到 1280x720（仅 mixres 结构，r720=1）

## 运行

```bash
cd hls_discontinuity_tests
# 先 ./build_seek_sources.sh 生成源
bash assert_seek_cases_device.sh sk-pos-01a   # 单例（起播即 seek 跨 DISCONT）
# 或 bash assert_seek_cases_device.sh          # 全量（需 DEBUG apk 支持 mid/2x 的 DebugCmdReceiver）
```
