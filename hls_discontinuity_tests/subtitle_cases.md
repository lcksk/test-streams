# HLS 字幕 + discontinuity 测试套件（基于 rmdmy）

> 本套件验证 mpv-android 在 **tunnel（HW_AV_SYNC）直通**下，对带 discontinuity 的 HLS
> （TS 封装与 HLS-over-fMP4 两种媒体封装）能否正确拉取并渲染**外挂 WebVTT 字幕**，
> 并在 **2× 变速 + 起播即 seek + 多次中途 seek** 后保持 A/V 同步、不回退软解、不丢帧。

---

## 0. 变更摘要（相对旧版 emb 方案）

- **base 片源**：改用 `rmdmy`（720p HLS，009–029.ts）。实测干净：concat 后坏包=0、视频跳变=0、音频跳变=0。
- **Form B 改为 `HLS over fMP4`**（EXT-X-MAP + .m4s），**取代旧的内嵌 MP4（mov_text）**。
  HLS 规范不允许内嵌字幕轨，故两种封装形式**统一走外挂 WebVTT rendition**；
  二者的差异只在**媒体封装**（TS vs fMP4），字幕路径完全一致。
- 已删除所有 `*_emb.mp4` / `*-emb/` 目录。
- **jump 形式补齐 fmp4**：旧方案因 emb 把 jump 的时间戳间隙拍平成单文件时间轴、破坏 seek 语义才排除 jump；
  fMP4 HLS 保留 discontinuity，故纳入，反而提升覆盖。
- **用例矩阵**：4 结构 × 2 封装 × 4 动作 = **32 例**，数据驱动（`subtitle_case_matrix.tsv` + `assert_subtitle_cases_device.sh`）。

---

## 1. 测试目标与片源矩阵

| 结构变体 | DISCONT 数 | 说明 | 封装形式 |
|----------|-----------|------|----------|
| `base`   | 0 | 无 discontinuity（对照组） | `wvtt`(TS) / `fmp4` |
| `disc`   | 2 | DISCONT + 时间戳连续衔接 | `wvtt` / `fmp4` |
| `jump`   | 2 | DISCONT + 时间戳大跳（0 / 60 / 120） | `wvtt` / `fmp4` |
| `mixres` | 2 | DISCONT + 1280x720 → 1920x1080 → 1280x720 分辨率切换 | `wvtt` / `fmp4` |

封装形式含义：
- **Form A — `wvtt`（TS 封装）**：`sk4-2x-<x>-wvtt/master.m3u8`，TS 分段（`s_*.ts`）+ 外挂 WebVTT rendition。
- **Form B — `fmp4`（HLS over fMP4）**：`sk4-2x-<x>-fmp4/master.m3u8`，`EXT-X-MAP`（`init_*.mp4`）+ `.m4s` 分段；字幕同样走外挂 WebVTT rendition。

---

## 2. 片源结构与生成

两个构建脚本，后者依赖前者产出的结构源事实：

1. **`build_2x_sources.sh`** —— 生成 4 个**结构源**（`sk4-2x-{base,disc,jump,mixres}/`，仅 `index.m3u8` + `s_*.ts`）
   - 以 rmdmy 的 `009/010/011.ts` 为 A/B/C 内容块；
   - `place()` 重编码（`-c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 96k`）并摆放到非负时间轴；
   - `transcale()` 把 `mixres` 中段转 1080p 以制造分辨率切换；
   - 自检 S1–S6 并写 `sources_facts.tsv` / `sources_struct.tsv`，最后 `exec verify_sources.sh source`。

2. **`build_subtitle_sources.sh`** —— 在结构源之上叠加字幕，生成 8 个**字幕片源**目录 `sk4-2x-<x>-{wvtt,fmp4}/`
   - `wvtt`：复用结构源的 TS 分段，加 `master.m3u8` + `index.m3u8` + `sub_en.m3u8` + `sub_en.vtt`；
   - `fmp4`：每个 discontinuity 组**独立 pass** 生成 `init_a/b/c.mp4` + `a/b/c_000.m4s`，组间插 `#EXT-X-DISCONTINUITY`；字幕同样走 WebVTT rendition；
   - 字幕 cue 时间点：`CUES="2 5 12 15 22 25"`；
   - 末尾 `exec ./verify_sources.sh all` 串起三级验收。

> ffmpeg 坑（已踩平）：hls muxer 把 `-hls_fmp4_init_filename` 解析到 **playlist 目录**、
> 把 `-hls_segment_filename` 解析到 **CWD**，相对名与绝对名行为不一致，易把分段写错目录或二次嵌套。
> 现统一用 `cd $d` 子 shell + 相对 basename 写法，init 与分段都落在目标目录。

---

## 3. 逐例清单（32 例，矩阵驱动）

矩阵由 `gen_matrix()` 生成，等价于 `bash assert_subtitle_cases_device.sh --emit-matrix`，
落盘为 **`subtitle_case_matrix.tsv`**（TAB 分隔，8 列：
`id | srcbase | form | mode | seeks | speed | total | r720`）。

每结构 × 2 封装（wvtt / fmp4）× 4 动作：

| 动作 | mode | seeks | speed | 说明 |
|------|------|-------|-------|------|
| `*-pos`   | `pos` | `pseek`（base15.0 / disc15.0 / jump19.6 / mixres14.0） | 1× | 起播即 seek 到 pseek |
| `*-mid`   | `mid` | `3 20 10 8` | 1× | 依次中途 seek 4 次 |
| `*-sp`    | `pos` | `pseek` | 2× | 起播即 seek + 2× 变速 |
| `*-mdsp`  | `mid` | `3 20 10 8` | 2× | 多次中途 seek + 2× 变速 |

> 2× 变速在开播后**立即**下发（先于任何 seek），用于复现并验证「倍速 + seek 后 A/V 不同步」修复。

---

## 4. 每个 case 怎么算成功（验收标准）

真机日志断言位于 `assert_subtitle_cases_device.sh` 的 `run_one()`，逐条 `eq` / `near` / 计数：

| 编号 | 验收点 | 判据 |
|------|--------|------|
| S1 | 字幕列表被拉取 | `grep -c sub_en == 1`（两种封装都走外挂 WebVTT） |
| S2 | 字幕轨识别 | `grep -ciE 'subtitle\|mov_text\|wvtt\|Added subtitle\|sub.*track' >= 1` |
| S3 | 播放完整性 | 从 lastseek 到 `video EOF` 的实测时长 near `(total-lastseek)/speed`（容差 6s） |
| S4 | 硬解健康 | 无 `Error while decoding frame`、无 `Using software decoding`、有 `Using hardware decoding` |
| S5 | 音频时间轴 | 无 `Invalid audio PTS: x -> y (y<x)` 真回退、无 `Reset playback due to audio timestamp` |
| S6 | 播放结束 | `audio EOF reached` 与 `video EOF reached` 各 1 次 |
| S7 | **头条 A/V 同步** | `desynchronisation` 告警数 == 0（最关键） |
| S8 | 分辨率（仅 mixres, r720=1） | `Decoder format: 1280x720` 出现 1 次（切换后回到 720p） |

- **2× 有效性**：由 S3 播放时长近端断言**间接覆盖**——若倍速未真正生效，实测时长 ≈ 2× 预期而 FAIL。
- discontinuity 次数本身不在真机日志直接断言（mpv 对不同版本的 discontinuity 处理日志措辞不一），
  但 S5/S6/S7 已覆盖其回归；源侧 DISCONT 计数由 `verify_sources.sh` 在 playlist 层校验（见 §6）。

---

## 5. 源侧 gate（verify_sources.sh 三级验收）

三级验收，任一 FAIL 即说明片源不满足测试前提：

1. **素材层**：rmdmy `009/010/011.ts` —— 无坏包 / 无视频跳变 / 无音频跳变。
2. **片源层**（来自 `sources_struct.tsv`）：4 个结构源 S1–S6
   （坏包 / 视频跳变 / 音频伪跳变 / 摆放 / 分辨率 / 时长 / DISCONT）。
3. **字幕形式层**：8 个字幕片源
   （SUBTITLES rendition 存在、EXT-X-MAP 在 `index.m3u8`、init 可解析、WebVTT 头、整 playlist 可被 ffprobe 解析）。

**当前结果：`PASS=56 FAIL=0`**（素材 3 + 结构源 25 + 字幕形式 28）。

---

## 6. 真机复测计划

- **必跑（本次收尾）**：`sk4-2x-base-fmp4` / `sk4-2x-disc-fmp4`
  —— 验证 fMP4 封装在 tunnel 直通下 + 2× + seek 后 desync=0、硬解不回退。
- **全量**：`bash assert_subtitle_cases_device.sh`（需真机 + `debug-tools` 分支 app + `DebugCmdReceiver` 注入 seek/speed）。
- **环境**：
  - mpv 切 `wip_hls_discontinuity`（含倍速+seek 修复），ffmpeg 同分支；
  - app 切 `debug-tools` 重编安装（提供 `am broadcast -a is.xyz.mpv.DEBUG_CMD` 注入）。
