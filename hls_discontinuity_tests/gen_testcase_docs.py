#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 HLS discontinuity 测试集的全部 EXPECT.md + 总纲 MD + Excel 索引。

产出：
  - case01..case25/EXPECT.md            （discontinuity 套件，25 例）
  - sk0-base..sk4-2x-*/EXPECT.md        （seek 源 8 例）
  - pts_robustness/p01..p12/EXPECT.md   （pts_robustness 12 例）
  - sk4-2x-{base,disc,jump,mixres}/EXPECT.md  （subtitle 4 结构源）
  - TESTCASES-INDEX.md                  （共纲领，按套件分区，便于检索）
  - TESTCASES-INDEX.xlsx                （同数据，可筛选）
"""
import os, datetime

ROOT = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# 1) discontinuity 套件（case01-25）
#    数据来自 README.md 用例总表 + FAILURE-ANALYSIS.md + 实际 m3u8。
#    字段：id, zh, purpose, feat(特征 bullets), nvd, nad, dur, fr, pk,
#          newres, newaudio, note(特殊判据/坑)
# ---------------------------------------------------------------------------
DISC = [
 ("case01-fmt-head", "格式不连续在最前", "验证 DISCONTINUITY 出现在播放头部、且只有视频分辨率变化时的处理。",
  ["base(720p) 前插一段 000.ts(640x360) 作为头部，形成「头格式断点」",
   "仅视频流格式变化（音频始终是 44100 stereo，不变）"], 1,0,38.85,1019,1665,"640x360:1","-",
  "视频重建 1 次（头断点触发）；音频重建 0。"),
 ("case02-fmt-mid", "格式不连续在中间", "验证格式断点在播放中段、且后半段又变回原格式时的处理。",
  ["720p 段中间插入 000.ts(360p) 再回到 720p，断点在中间",
   "仅视频格式变化，音频不变"], 2,0,38.85,1019,1665,"640x360:1","-",
  "视频重建 2 次（进/出 360p 各一次）。"),
 ("case03-fmt-tail", "格式不连续在最后", "验证格式断点出现在播放尾部时的处理。",
  ["720p 段末尾接 000.ts(360p)，断点在尾部",
   "仅视频格式变化，音频不变"], 1,0,38.85,1019,1665,"640x360:1","-",
  "视频重建 1 次（尾断点）；注意 000.ts 时间戳略前跳属正常前进，非回退。"),
 ("case04-video-only", "只有视频变化(时间戳已对齐)", "验证「仅视频流变化、音频不变且时间戳已对齐」的断点。",
  ["同一 720p 内容的视频段被标记为断点，但音频连续、时间戳已对齐",
   "无分辨率变化（newres 不检测），只有视频重建"], 1,0,20.59,564,881,"-","-",
  "视频重建 1 次；音频重建 0、无分辨率变化。"),
 ("case05-audio-only", "只有音频变化(22050/mono)", "验证「仅音频参数变化(22050Hz mono)」的断点。",
  ["音频切换为 22050Hz mono（派生自 base），视频保持 720p 连续",
   "只有音频流参数变化"], 0,1,20.19,500,648,"-","22050Hz mono",
  "音频重建 1 次、视频重建 0；识别到 22050Hz mono。"),
 ("case06-audio-head", "音频变化在最前", "验证音频参数变化出现在头部的断点。",
  ["头部即切换音频为 22050Hz mono，视频 720p 连续",
   "只有音频参数变化"], 0,1,38.46,955,1432,"-","22050Hz mono",
  "音频重建 1 次；音频 PTS 真回退与 `Reset playback` 为观察项（obs=any）；A/V 不同步仍须严格为 0。"),
 ("case07-ts-jump-fwd", "时间戳向前跳 +98s", "验证 DISCONTINUITY + 时间戳整体前跳（格式不变）的 rebase。",
  ["在连续 009 段之间插入 +98s 的时间戳偏移段（格式不变）",
   "纯时间戳跳变，无格式/分辨率变化"], 0,0,28.34,705,1215,"-","-",
  "视频/音频重建均 0；dts 不回退。"),
 ("case08-ts-jump-back", "时间戳向后跳 -82s", "验证 DISCONTINUITY + 时间戳整体回跳（格式不变）的 rebase。",
  ["在连续 009 段之间插入 -82s 的时间戳偏移段（格式不变）",
   "纯时间戳回跳，无格式/分辨率变化"], 0,0,28.34,705,1215,"-","-",
  "视频/音频重建均 0；rebase 后 dts 不应回退。"),
 ("case09-ts-restart", "第二组时间戳归零", "验证 DISCONTINUITY + 第二组时间戳从 0 重开（最常见场景）的 rebase。",
  ["第二组段时间戳重新从 0 开始（真实拼接流常见）",
   "无格式/分辨率变化"], 0,0,28.34,705,1215,"-","-",
  "视频/音频重建均 0；rebase 成连续时间轴。"),
 ("case10-ts-only", "打 DISCONT 但时间戳本就连续", "验证「打了 DISCONT 标记、但时间戳实际连续」的边界（不应误重建）。",
  ["相邻段时间戳本来就连续，仅插入 DISCONT 标记",
   "格式/时间戳均无变化"], 0,0,35.80,890,1533,"-","-",
  "视频/音频重建均 0；marker 不应造成重置。"),
 ("case11-multi-disc", "4 片每片之间都 DISCONT", "验证多段连续 discontinuity（每段都开新组）的 rebase，原始 fail case。",
  ["009 / 010 / 011 / 012 四段，每段之间都插 DISCONT（3 个断点）",
   "时间戳连续递增，无格式变化"], 0,0,40.32,1003,1728,"-","-",
  "视频/音频重建均 0；rebase 后整条时间轴连续、dts 不回退（修复核心覆盖）。"),
 ("case12-fmt-and-ts", "格式变 + 时间戳跳同时", "验证「格式变化与时间戳跳变同时发生」的断点。",
  ["头部插 000.ts(360p) 同时其时间戳相对前段有跳变",
   "视频格式 + 时间戳同时变化"], 1,0,20.59,564,881,"640x360:1","-",
  "视频重建 1 次；音频重建 0。"),
 ("case13-disc-at-start", "m3u8 开头就 DISCONT", "验证 playlist 第一个 EXTINF 前就有 DISCONT 的异常构造。",
  ["#EXT-X-DISCONTINUITY 出现在第一个段之前",
   "开头即断点，时间戳/格式无额外变化"], 0,0,28.34,705,1215,"-","-",
  "视频/音频重建均 0；开局断点不应导致重置或回退。"),
 ("case14-disc-every-ts-fwd", "每片都 DISCONT, 时间戳逐次前跳", "压力：每段都 DISCONT 且时间戳逐次前跳。",
  ["多段每段都 DISCONT，时间戳逐段前跳",
   "纯时间戳跳变，无格式变化"], 0,0,40.32,1003,1728,"-","-",
  "视频/音频重建均 0；rebase 后连续。"),
 ("case15-disc-every-ts-alt", "每片都 DISCONT, 时间戳前后交替跳", "压力：每段都 DISCONT 且时间戳前后交替跳。",
  ["多段每段都 DISCONT，时间戳前跳/后跳交替",
   "纯时间戳跳变，无格式变化"], 0,0,40.32,1003,1728,"-","-",
  "视频/音频重建均 0；交替跳变下 rebase 不回退。"),
 ("case16-disc-every-fmt-alt", "每片都 DISCONT, 格式交替 720/360/720/360", "压力：每段都 DISCONT 且分辨率在 720p/360p 间交替。",
  ["多段每段都 DISCONT，分辨率 720p→360p→720p→360p 交替",
   "格式变化驱动解码器重建"], 3,0,49.36,1333,2115,"640x360:2","-",
  "视频重建 3 次（含 2 个 360p 段）；识别 640x360 次数=2（段数，非变化次数）。"),
 ("case17-disc-every-audio-alt", "每片都 DISCONT, 音频参数交替", "压力：每段都 DISCONT 且音频参数在 44100/22050 间交替。",
  ["多段每段都 DISCONT，音频 44100↔22050Hz mono 交替",
   "音频参数变化驱动解码器重建"], 0,3,48.58,1205,1649,"-","22050Hz mono",
  "音频重建 3 次；音频 PTS 真回退与 `Reset playback` 为观察项（obs=any）；A/V 不同步仍须严格为 0。"),
 ("case18-cross-all", "交叉：视频变+前跳→音频变+前跳→都变回+后跳", "综合交叉：视频变+前跳、音频变+前跳、两者变回+后跳全覆盖。",
  ["三段依次：视频 720p→360p+时间戳前跳；音频 44100→22050+前跳；两者变回 720p/44100+后跳",
   "视频与音频断点交错"], 2,2,48.97,1269,1882,"640x360:1","22050Hz mono",
  "视频/音频重建判据均为 0；识别 640x360 与 22050Hz mono 各 1 次。**A/V 不同步为观察项**（desync=any）：本例跨段需同时重建 VD+AO，重建瞬间必然有一次偏差；实测设备高负载下偶发，其余判据恒定达标，告警数仍会打印。"),
 ("case19-disc-every-plain", "6 片每片都 DISCONT, 什么都不变(压力)", "压力：6 段每段都 DISCONT 但内容/格式/时间戳都不变。",
  ["6 段每段都 DISCONT，内容均为 720p 连续，无额外变量",
   "纯多断点压力"], 0,0,66.14,1645,2834,"-","-",
  "视频/音频重建均 0；6 段全部完整播完。"),
 ("case20-dup-repeat-disc", "同一分片重复 3 次, 每次带 DISCONT", "重复分片对照组（带标记）：验证「重复段 + DISCONT」能 rebase 成连续时间轴。",
  ["同一分片(009, 91.5→101.6s) 重复 3 次，每次都带 DISCONT",
   "内容完全相同、时间戳相同，靠标记开新组"], 0,0,30.22,750,1293,"-","-",
  "视频/音频重建均 0；重复时间戳被 rebase 成 0→10.07→20.15→30.22，dts 回退 0（vs case21 对照）。"),
 ("case21-dup-repeat-nodisc", "同一分片重复 3 次, 不带 DISCONT(对照)", "重复分片对照组（不带标记）：证明「不打 DISCONT」会让时间轴被打回起点。",
  ["同一分片重复 3 次，但【不】打 DISCONT 标记",
   "内容完全相同、时间戳相同，未标记则不切组"], 0,0,30.22,750,1293,"-","-",
  "本用例为预期现象观察项：音频 PTS 真回退、时间轴重置(Reset playback) 会出现（即『播放回到 0』症状）；其余判据照常严格。"),
 ("case22-dup-repeat-offset", "同一分片重复 3 次, 带 DISCONT 且时间戳递增", "重复分片 + 每次带 DISCONT 且时间戳递增加偏移。",
  ["同一分片重复 3 次，每次带 DISCONT，时间戳逐次递增偏移",
   "内容相同、时间戳递增加偏移"], 0,0,30.22,750,1293,"-","-",
  "视频/音频重建均 0；rebase 成递增连续时间轴，dts 不回退。"),
 ("case23-dup-interleave-disc", "间隔重复 A B A B, 每次带 DISCONT", "间隔重复（A B A B）且每次带 DISCONT 的完整性压力。",
  ["A、B 两段间隔重复（A B A B），每段都带 DISCONT",
   "跨组交替重复"], 0,0,56.68,1410,2430,"-","-",
  "视频/音频重建均 0；4 段全部完整播完、dts 不回退。"),
 ("case24-dup-then-fmt", "先重复同格式段(000×2), 再切到 720p", "重复同格式段后切到不同分辨率的复合场景。",
  ["000.ts(360p)×2 重复，再接 009.ts(720p)，断点在 fmt 变化处",
   "同格式重复段不触发重建，最后 fmt 变化触发一次"], 1,0,31.10,878,1331,"640x360:1","-",
  "视频重建 1 次（仅 360p→720p 处）；注意同格式重复段不重复打印 Decoder format，识别 640x360 次数=1（变化次数）。"),
 ("case25-dup-mixed-ts", "同一分片重复 + 时间戳先后跳、再前跳", "重复分片 + 混合时间戳前后跳的复合场景。",
  ["同一分片重复，时间戳先回跳、再前跳",
   "重复 + 时间戳混跳"], 0,0,30.22,750,1293,"-","-",
  "视频/音频重建均 0；rebase 后连续、dts 不回退。"),
]

# ---------------------------------------------------------------------------
# 2) seek 源（sk0-base..sk4-2x-mixres）构造 + 覆盖的场景
# ---------------------------------------------------------------------------
SEEK_SOURCES = [
 ("sk0-base", "SK0-base（无 DISCONT 的 seek 基线）",
  "8K 长片(7680x4320/30fps/HE-AAC) 三段时间戳连续拼接成单文件，无任何 DISCONTINUITY。作为 seek 基线对照组。",
  ["素材：hls_dump_file_6/7/8.ts（各 ~10s，起点 57.6/68.1/76.8）",
   "各段 rebase 到连续时间轴 0 / 10.562 / 19.371，concat 成单文件",
   "总时长 29.41s，无 DISCONT"],
  "sk-pos-00a/b/c（起播即 seek 到 3.0/15.0/28.5）"),
 ("sk1-disc", "SK1-disc（DISCONT + 时间戳连续衔接）",
  "8K 三段时间戳连续递增、段间插 DISCONTINUITY（DISCONT 后不回落到 0）。测跨 DISCONT 边界 seek。",
  ["素材同上，各段 rebase 到 0 / 10.562 / 19.371（连续衔接）",
   "段间插 #EXT-X-DISCONTINUITY，共 2 个断点",
   "总时长 29.41s，边界 10.562 / 19.371"],
  "sk-pos-01a~01f（seek 到 3.0/10.7/14.0/19.6/24.0/28.5，覆盖边界前/后/段中/近 EOF）"),
 ("sk2-disc-jump", "SK2-disc-jump（DISCONT + 时间戳大跳）",
  "8K 三段时间戳大跳（0 / 60 / 120）+ DISCONTINUITY。测大跳下的跨边界 seek。",
  ["素材同上，各段 rebase 到 0 / 60 / 120（大跳）",
   "段间插 DISCONT，共 2 个断点",
   "总时长 29.41s，边界 10.562 / 19.371（时间戳跳到 60/120）"],
  "sk-pos-02a/b/c（seek 到 10.7/19.6/24.0）"),
 ("sk3-mixres", "SK3-mixres（DISCONT + 分辨率切换）",
  "8K(6) #D 720p(009) #D 8K(8)，分辨率交替 + DISCONTINUITY。测跨分辨率断点 seek。",
  ["seg6(8K) rebase 0；720p(009) rebase 10.562；seg8(8K) rebase 20.635",
   "段间插 DISCONT，共 2 个断点，分辨率 8K→720p→8K",
   "总时长 30.67s，边界 10.562 / 20.635"],
  "sk-pos-03a/b/c（seek 到 3.0/14.0/24.0；14.0 落 720p 段内，期望识别 1280x720）"),
 ("sk4-2x-base", "SK4-2x-base（rmdmy 结构源, 无 DISCONT, 字幕套件 base）",
  "720p HLS（rmdmy 009/010/011.ts）三段时间戳连续、无 DISCONTINUITY。既是 seek 2x 套件的 base 结构源，也是字幕套件 base 结构源。",
  ["素材：rmdmy 009/010/011.ts（720p h264 / aac 44100）",
   "重编码摆放到非负连续时间轴，无 DISCONT",
   "总时长 ~35.9s，结构源只含 index.m3u8 + s_*.ts"],
  "seek 套件 sk-sp-00a（2× + 起播即 seek 15.0）；字幕套件 sub-{W,E}-base-*（4 动作）"),
 ("sk4-2x-disc", "SK4-2x-disc（DISCONT + 时间戳连续, 字幕套件 disc）",
  "rmdmy 结构源上叠加 DISCONTINUITY + 时间戳连续衔接。字幕套件 disc 结构源。",
  ["基于 sk4-2x-base 结构源，段间插 DISCONT，时间戳连续衔接",
   "2 个断点，分辨率不变(720p)",
   "总时长 ~35.9s"],
  "seek 套件 sk-sp-01a（2× + pos 14.0）；字幕套件 sub-{W,E}-disc-*"),
 ("sk4-2x-jump", "SK4-2x-jump（DISCONT + 时间戳大跳, 字幕套件 jump）",
  "rmdmy 结构源上叠加 DISCONTINUITY + 时间戳大跳（0/60/120）。字幕套件 jump 结构源。",
  ["基于 sk4-2x-base 结构源，段间插 DISCONT，时间戳大跳",
   "2 个断点，分辨率不变(720p)",
   "总时长 ~35.9s，seek 点 19.6"],
  "seek 套件 sk-sp-02a（2× + pos 19.6）；字幕套件 sub-{W,E}-jump-*"),
 ("sk4-2x-mixres", "SK4-2x-mixres（DISCONT + 分辨率切换, 字幕套件 mixres）",
  "rmdmy 结构源上叠加 DISCONTINUITY + 720p→1080p→720p 分辨率切换。字幕套件 mixres 结构源。",
  ["基于 sk4-2x-base 结构源，中途段转 1080p，段间插 DISCONT",
   "2 个断点，分辨率 720p→1080p→720p",
   "总时长 ~35.9s，seek 点 14.0"],
  "seek 套件 sk-sp-03a（2× + pos 14.0）；字幕套件 sub-{W,E}-mixres-*"),
]

# seek 套件矩阵（来自 assert_seek_cases_device.sh）
SEEK_MATRIX = [
 # id, src, mode, seeks, speed, total, r720, 说明
 ("sk-pos-00a","sk0-base","pos","3.0","1","29.41","0","起播即 seek 到 3.0（无 DISCONT 基线）"),
 ("sk-pos-00b","sk0-base","pos","15.0","1","29.41","0","起播即 seek 到 15.0（无 DISCONT 基线）"),
 ("sk-pos-00c","sk0-base","pos","28.5","1","29.41","0","起播即 seek 到 28.5（近 EOF）"),
 ("sk-pos-01a","sk1-disc","pos","3.0","1","29.41","0","起播即 seek 到 3.0（跨 DISCONT 前）"),
 ("sk-pos-01b","sk1-disc","pos","10.7","1","29.41","0","起播即 seek 到边界+0.1s（10.562 之后）"),
 ("sk-pos-01c","sk1-disc","pos","14.0","1","29.41","0","起播即 seek 到段中"),
 ("sk-pos-01d","sk1-disc","pos","19.6","1","29.41","0","起播即 seek 到第二边界后"),
 ("sk-pos-01e","sk1-disc","pos","24.0","1","29.41","0","起播即 seek 到段中后段"),
 ("sk-pos-01f","sk1-disc","pos","28.5","1","29.41","0","起播即 seek 到近 EOF"),
 ("sk-pos-02a","sk2-disc-jump","pos","10.7","1","29.41","0","起播即 seek 到 DISCONT 边界后（时间戳大跳）"),
 ("sk-pos-02b","sk2-disc-jump","pos","19.6","1","29.41","0","起播即 seek 到第二边界后"),
 ("sk-pos-02c","sk2-disc-jump","pos","24.0","1","29.41","0","起播即 seek 到段中后段"),
 ("sk-pos-03a","sk3-mixres","pos","3.0","1","30.67","1","起播即 seek 到 8K 段"),
 ("sk-pos-03b","sk3-mixres","pos","14.0","1","30.67","1","起播即 seek 到 720p 段内（期望识别 1280x720）"),
 ("sk-pos-03c","sk3-mixres","pos","24.0","1","30.67","0","起播即 seek 到 8K 段后"),
 ("sk-mid-01a","sk1-disc","mid","3 20 10 8","1","29.41","0","播放中多向 seek（3→20→10→8），1×"),
 ("sk-mid-01b","sk1-disc","mid","26 3","1","29.41","0","播放中向后拖（26→3），1×"),
 ("sk-mid-02a","sk2-disc-jump","mid","5 15","1","29.41","0","播放中 seek（5→15），跨时间戳大跳，1×"),
 ("sk-mid-03a","sk3-mixres","mid","3 14 24","1","30.67","1","播放中 seek 跨分辨率（3→14→24），1×"),
 ("sk-sp-00a","sk4-2x-base","pos","15.0","2","27.63","0","2× 变速 + 起播即 seek（base）"),
 ("sk-sp-01a","sk4-2x-disc","pos","14.0","2","27.63","0","2× 变速 + 起播即 seek（disc）"),
 ("sk-sp-01b","sk4-2x-disc","mid","3 20 10 8","2","27.63","0","2× 变速 + 播放中多向 seek（disc）"),
 ("sk-sp-02a","sk4-2x-jump","pos","19.6","2","27.63","0","2× 变速 + 起播即 seek（jump，时间戳大跳）"),
 ("sk-sp-03a","sk4-2x-mixres","pos","14.0","2","28.49","1","2× 变速 + 起播即 seek（mixres，跨分辨率）"),
]

# ---------------------------------------------------------------------------
# 3) pts_robustness（p01-p12）— 验证 discontinuity 组内不一致段完整播完 / 不丢段
# ---------------------------------------------------------------------------
PTS = [
 ("p01_baseline_no_disc","baseline 无 DISCONT","3 段连续、无 DISCONTINUITY 的基线；验证正常播放无丢段、duration↔EOF 自洽。",
  ["3 段同前缀 .ts，时间戳连续","无 DISCONT，单组"]),
 ("p02_same_url_no_disc","相同 URL 重复, 无 DISCONT","同一 .ts 在 playlist 内重复出现、无 DISCONT；验证重复 URL 不被误去重丢弃。",
  ["同一段 URL 出现多次","无 DISCONT，单组"]),
 ("p03_two_groups_consistent","两组, 内容一致","两个 DISCONTINUITY 组、组内/组间内容一致；验证跨组衔接完整。",
  ["2 个 DISCONT 组","组间内容一致，时间轴连续"]),
 ("p04_in_group_smaller","组内某段更短","组内某段时长明显短于其它段；验证短段不被跳过。",
  ["组内包含一段更短的 .ts","时间轴/段数完整"]),
 ("p05_in_group_larger","组内某段更长","组内某段时长明显长于其它段；验证长段完整播完。",
  ["组内包含一段更长的 .ts","段数/时长完整"]),
 ("p06_in_group_back_and_forth","组内时间戳前后往复","组内时间戳前进/回退交替；验证组内时间轴不回退、不丢段。",
  ["组内包含前进+回退的时间戳跳变","段数完整"]),
 ("p07_multi_group_mixed","多组混合 URL","多个 DISCONTINUITY 组、各组 URL 混合；验证跨组多 URL 都完整拉取。",
  ["3 个 DISCONT 组，各组 URL 混排","跨组完整"]),
 ("p08_last_odd_drain","末尾为奇数长度段","最后一个段时长为奇数/非整数，测试末尾 drain；验证到 EOF 不丢尾段。",
  ["最后一段为特殊（奇数）长度","EOF 完整"]),
 ("p09_same_url_across_groups","相同 URL 跨组重复","同一 .ts 在多个 DISCONTINUITY 组里都出现；验证跨组重复 URL 不被去重丢弃。",
  ["同一段 URL 出现在多个 DISCONT 组","每段都应被请求播完"]),
 ("p10_single_segment","单段 playlist","只有一个 EXTINF 段的极端 playlist；验证单段能正常开播到 EOF。",
  ["单段 .ts","无 DISCONT"]),
 ("p11_boundary_then_odd","边界后接奇数段","DISCONTINUITY 边界后接一段奇数长度段；验证边界切换后尾段完整。",
  ["边界 + 奇数长度尾段","跨边界完整"]),
 ("p12_odd_first_in_group","组内首段为奇数长度","某组首段为奇数长度；验证组内首段完整、不被跳过。",
  ["组内首段奇数长度","组内完整"]),
]

# ---------------------------------------------------------------------------
# 4) subtitle 结构源（4 个）— 32 矩阵例 = 4 结构 × 2 封装(wvtt/fmp4) × 4 动作(pos/mid/sp/mdsp)
# ---------------------------------------------------------------------------
SUB_SOURCES = [
 ("sk4-2x-base","base（无 DISCONT）","rmdmy 009/010/011 连续，无 DISCONTINUITY。字幕基线结构源。",
  "无 DISCONT（对照组）；pseek=15.0；r720=0"),
 ("sk4-2x-disc","disc（DISCONT + 时间戳连续）","段间插 DISCONT、时间戳连续衔接。字幕 disc 结构源。",
  "2 DISCONT；pseek=15.0；r720=0"),
 ("sk4-2x-jump","jump（DISCONT + 时间戳大跳）","段间插 DISCONT、时间戳大跳(0/60/120)。字幕 jump 结构源。",
  "2 DISCONT；pseek=19.6；r720=0"),
 ("sk4-2x-mixres","mixres（DISCONT + 分辨率切换）","段间插 DISCONT、720p→1080p→720p 切换。字幕 mixres 结构源。",
  "2 DISCONT；pseek=14.0；r720=1（期望识别 1280x720 与 1920x1080）"),
]
# 字幕 32 例矩阵（由 subtitle_cases.md 的 gen_matrix 推导）
SUB_FORMS = [("wvtt","TS 封装"),("fmp4","HLS over fMP4")]
SUB_ACTIONS = [("pos","起播即 seek","pseek","1"),("mid","播放中多次 seek","3 20 10 8","1"),
               ("sp","2× + 起播即 seek","pseek","2"),("mdsp","2× + 播放中多次 seek","3 20 10 8","2")]
def sub_matrix_rows():
    rows=[]
    for sb,_,_,_ in SUB_SOURCES:
        b=sb.replace("sk4-2x-","")
        for form,formzh in SUB_FORMS:
            for act,actzh,seeks,sp in SUB_ACTIONS:
                fp = "W" if form=="wvtt" else "E"
                cid=f"sub-{fp}-{b}-{act}"
                rows.append((cid, sb, form, formzh, act, actzh, seeks, sp))
    return rows

# ===========================================================================
# 生成函数
# ===========================================================================
def disc_expect_md(d):
    (cid,zh,purpose,feat,nvd,nad,dur,fr,pk,newres,newaudio,note)=d
    lines=[]
    lines.append(f"# {cid} — {zh}\n")
    lines.append(purpose+"\n")
    lines.append("## 目的\n")
    lines.append(f"discontinuity 套件用例之一：{purpose}\n")
    lines.append("## 特征（构造）\n")
    for f in feat: lines.append(f"- {f}")
    lines.append("")
    lines.append("## 预期\n")
    lines.append("| 项 | 预期 |")
    lines.append("|---|---|")
    lines.append(f"| 分组 | 按 DISCONTINUITY 标记切组（本例断点数见特征） |")
    lines.append("| 解码器重建 | 视频 **0** 次 / 音频 **0** 次（rebase 修复后 discontinuity 不再重建解码器） |")
    lines.append(f"| 历史期望表(仅对照) | 视频 {nvd} / 音频 {nad}（修复前语义，已失效） |")
    if newres!="-":
        cnt=newres.split(":")[1]
        lines.append(f"| 分辨率识别 | `VO: [mediacodec_embed] {newres.split(':')[0]}` 出现 **{cnt}** 次 |")
    if newaudio!="-":
        lines.append(f"| 音频识别 | `AO: [audiotrack] {newaudio}` ≥ 1 次 |")
    lines.append(f"| 时间轴 | rebase 后连续，dts 回退 0（音频 PTS 真回退 = 0） |")
    lines.append(f"| 完整性 | 视频帧 **{fr}** / 音频包 **{pk}**（= 各段之和） |")
    lines.append(f"| 真机 | 播到 EOF，播放时长 ≈ **{dur}s** |")
    lines.append("")
    if note:
        lines.append("> 注："+note+"\n")
    lines.append("> 说明：用例资料里的「重建次数」为修复前期望；当前真机判据为视频/音频重建次数均 == 0，重建次数列仅作历史对照。\n")
    lines.append("## 如何判定成功\n")
    lines.append("### L1（host，`assert_cases.sh`，ffmpeg/ffprobe 离线）\n")
    lines.append("- 时间轴：每条流 **dts 回退数 == 0**")
    lines.append("- 总时长：== 各段之和（±0.30s），空洞/重叠都算失败")
    lines.append("- 完整性：视频帧数、音频包数 == 各段之和（少一帧即失败）")
    lines.append("- 通告条数：== 断点数 × 2（每条流一条）")
    lines.append("- 格式识别：期望新格式必须出现 `Reinit context to <新分辨率>`；其余用例不得出现预期外分辨率")
    lines.append("")
    lines.append("### L2（真机，`assert_cases_device.sh`，mpv-android2 / mediacodec）\n")
    lines.append(f"- 播放时长：`event: playback-restart → event: end-file` 墙钟差 == {dur}s（±3s）")
    lines.append("- 硬解报错：`Error while decoding frame` == 0")
    lines.append("- 回退软解：`Using software decoding` == 0")
    lines.append("- 持续硬解：`Using hardware decoding` ≥ 1")
    lines.append("- 音频 PTS 真回退（`Invalid audio PTS` 后值 < 前值）：== 0")
    lines.append("- 时间轴重置：`Reset playback due to audio timestamp` == 0")
    lines.append("- 完整性：`event: end-file`（播放完整结束）== 1")
    lines.append("- 视频重建次数（`[vd:v] The stream is cut into a new one`）== 0；音频重建次数（`[ad:v] The stream is cut into a new one`）== 0（rebase 修复后 discontinuity 不再重建解码器）")
    if newres!="-":
        cnt=newres.split(":")[1]
        lines.append(f"- 分辨率识别：`VO: [mediacodec_embed] {newres.split(':')[0]}` 次数 == {cnt}")
    if newaudio!="-":
        lines.append(f"- 音频识别：`AO: [audiotrack] {newaudio}` ≥ 1")
    if cid=="case18-cross-all":
        lines.append("- A/V 不同步：`desynchronisation`：**观察项**（desync=any，跨段同时重建 VD+AO 必有一次偏差；仍打印实际数）")
    else:
        lines.append("- A/V 不同步：`desynchronisation` == 0（**其余用例均严格 0，无放宽**）")
    if cid in ("case06-audio-head","case17-disc-every-audio-alt","case21-dup-repeat-nodisc"):
        lines.append("- 音频 PTS 真回退 / `Reset playback`：**观察项**（`obs=any`，本例允许出现，非缺陷；其余用例须为 0）")
    lines.append("")
    lines.append("## 运行\n")
    lines.append(f"```bash\ncd {os.path.basename(ROOT)}\nbash assert_cases_device.sh {cid}   # 单例\n# 或 bash assert_cases_device.sh         # 全量 25 例\n```\n")
    lines.append("> 判据坑（已踩）：视频重建必须只匹配 `[vd:v]`，音频侧 `[ad:v]` 也会打印同一句；`Invalid audio PTS` 前进跳变无害，只有后值<前值才算回退。\n")
    return "\n".join(lines)

def seek_expect_md(s):
    (cid,zh,purpose,feat,scenes)=s
    lines=[]
    lines.append(f"# {cid} — {zh}\n")
    lines.append(purpose+"\n")
    lines.append("## 目的\n")
    lines.append("seek + discontinuity 套件（见 `seek_cases.md`）的源。本目录是被多个 seek 用例复用的「源」，本身不直接判定；"
                 "判定由其上叠加的 seek 场景（Tier1 起播即 seek / Tier2 真中途 seek / 2× 变速 + seek）完成。\n")
    lines.append("## 源构造（特征）\n")
    for f in feat: lines.append(f"- {f}")
    lines.append("")
    lines.append("## 覆盖的 seek 场景（见 `assert_seek_cases_device.sh`）\n")
    lines.append(f"- {scenes}\n")
    lines.append("## 如何判定成功（L2 真机，头条断言）\n")
    lines.append("- **A/V 不同步 `desynchronisation` == 0**（最关键：DISCONT + seek 同时满足才复现 desync）")
    lines.append("- `Reset playback due to audio timestamp` == 0")
    lines.append("- 音频 PTS 真回退（`Invalid audio PTS` 后值<前值）== 0")
    lines.append("- 播放完整性：从 lastseek 到 `event: end-file` 实测时长 near `(total-lastseek)/speed`（容差 6s）")
    lines.append("- 硬解健康：无 `Error while decoding frame`、无 `Using software decoding`、有 `Using hardware decoding`")
    lines.append("- `event: end-file`（播放完整结束）== 1")
    lines.append("- 识别到 1280x720（仅 mixres 结构，r720=1）")
    lines.append("")
    lines.append("## 运行\n")
    lines.append(f"```bash\ncd {os.path.basename(ROOT)}\n# 先 ./build_seek_sources.sh 生成源\nbash assert_seek_cases_device.sh sk-pos-01a   # 单例（起播即 seek 跨 DISCONT）\n# 或 bash assert_seek_cases_device.sh          # 全量（需 DEBUG apk 支持 mid/2x 的 DebugCmdReceiver）\n```\n")
    return "\n".join(lines)

def pts_expect_md(p):
    (cid,zh,purpose,feat)=p
    lines=[]
    lines.append(f"# {cid} — {zh}\n")
    lines.append(purpose+"\n")
    lines.append("## 目的\n")
    lines.append("pts_robustness 套件（见 `assert_pts_robustness_device.sh`）用例之一：验证 discontinuity **组内不一致段**是否完整播完，"
                 "重点检测「丢分段 / 没播完」（段完整性 + duration↔EOF 对应）。\n")
    lines.append("## 特征（构造）\n")
    for f in feat: lines.append(f"- {f}")
    lines.append("")
    lines.append("## 预期 / 如何判定成功（L2 真机）\n")
    lines.append("- **段完整**：日志请求 `.ts` 段数（按 URL 去重）== m3u8 的 #EXTINF 段数（丢几段=没播完，FAIL）")
    lines.append("- **无网络失败**：无 `Failed to open` / `Timeout was reached`")
    lines.append("- **播放到 EOF**：`event: end-file`（或 `Exiting.`）到达")
    lines.append("- **duration↔EOF 对应**：实测播放时长(end-file - start-file) ≈ m3u8 #EXTINF 加总（容差约 10%~15%+2s），偏离=可能丢分段")
    lines.append("- **A/V 不同步** `desynchronisation` == 0")
    lines.append("- **音频 PTS 真回退** == 0（后值 < 前值才算）")
    lines.append("- **硬解报错** `Error while decoding frame` == 0")
    lines.append("")
    lines.append("## 运行\n")
    lines.append(f"```bash\ncd {os.path.basename(ROOT)}\nbash assert_pts_robustness_device.sh {cid}   # 单例\n# 或 bash assert_pts_robustness_device.sh     # 全量 12 例\n```\n")
    return "\n".join(lines)

def sub_expect_md(s):
    (cid,zh,purpose,feat)=s
    lines=[]
    lines.append(f"# {cid} — 字幕结构源 {zh}\n")
    lines.append(purpose+"\n")
    lines.append("## 目的\n")
    lines.append("字幕 + discontinuity 套件（见 `subtitle_cases.md`）的**结构源**。本目录是被 32 个矩阵例（4 结构 × 2 封装 × 4 动作）"
                 "复用的「源」；判定由 `assert_subtitle_cases_device.sh` 在叠加字幕 playlist 后完成。\n")
    lines.append("## 源构造（特征）\n")
    # feat 是整串（用全角；分隔），不能直接 for 迭代（会逐字符输出）
    for f in [x.strip() for x in feat.split("；") if x.strip()]:
        lines.append(f"- {f}")
    lines.append("")
    lines.append("## 封装形式与动作矩阵\n")
    lines.append("- **Form A `wvtt`（TS 封装）**：`"+cid+"-wvtt/master.m3u8`，TS 分段 + 外挂 WebVTT rendition（`sub_en.m3u8` + `sub_en.vtt`）")
    lines.append("- **Form B `fmp4`（HLS over fMP4）**：`"+cid+"-fmp4/master.m3u8`，`EXT-X-MAP` + `.m4s` 分段；字幕同样走外挂 WebVTT rendition")
    lines.append("- **4 动作**：`pos` 起播即 seek / `mid` 播放中多次 seek / `sp` 2×+起播即 seek / `mdsp` 2×+播放中多次 seek")
    lines.append("")
    lines.append("## 前置（必须，否则字幕断言必然全挂）\n")
    lines.append("ffmpeg 的 HLS 在 `read_header` 阶段把字幕 playlist 置 `needed=0`、流 `discard=AVDISCARD_ALL`\n")
    lines.append("（**上游默认关闭字幕**）；读取循环只处理 `pls->needed` 的 playlist，故 `read_subtitle_packet()`\n")
    lines.append("不会被调用、字幕永不去拉。必须显式启用：**`mpv.conf` 写入 `sid=1` + `sub-visibility=yes`**\n")
    lines.append("（mpv 选项只能经 `filesDir/mpv.conf` 注入；`msg-level=ffmpeg=debug` 需保留，靠它打印 HLS request 行）。\n")
    lines.append("`assert_subtitle_cases_device.sh` 已内置 `ensure_subtitle_conf()` 自动推送该配置。\n")
    lines.append("## 如何判定成功（L2 真机，头条断言）\n")
    lines.append("- 字幕被拉取：`sub_en`（`sub_en.m3u8` 或 `sub_en.vtt`）≥ 1 次\n")
    lines.append("  （实测被请求的是 `sub_en.vtt`；`sub_en.m3u8` 不一定单独打印，故按 `sub_en` 匹配）")
    lines.append("- 字幕轨识别：日志出现 `subtitle|mov_text|wvtt|Added subtitle|sub.*track` ≥ 1")
    lines.append("- **A/V 不同步 `desynchronisation` == 0**（最关键，2×+seek 最易爆）")
    lines.append("- `Reset playback due to audio timestamp` == 0；音频 PTS 真回退 == 0")
    lines.append("- 播放完整性：`event: end-file` 实测时长 near `(total-lastseek)/speed`（容差 6s）；`event: end-file`（播放完整结束）== 1")
    lines.append("- 硬解健康：无 `Error while decoding frame`、无 `Using software decoding`、有 `Using hardware decoding`")
    lines.append("- mixres 结构：`VO: [mediacodec_embed] 1280x720` 与 `VO: [mediacodec_embed] 1920x1080` 各 ≥ 1（分辨率切换真发生）")
    lines.append("")
    lines.append("## 已知问题（2026-09-25 实测）\n")
    lines.append("**开播即 seek 时字幕不会被拉取。** 同一 `sk4-2x-base-wvtt` 源：position=0 时 `sub_en` 拉取\n")
    lines.append("成功（请求到 `sub_en.vtt`）；position=15.0 时 `sub_en`=0，且日志出现\n")
    lines.append("`Format webvtt detected only with low score of 1, misdetection possible!`（字幕子 demuxer 探测失败）。\n")
    lines.append("由于 4 种动作（pos/mid/sp/mdsp）全部含 seek，该问题会让 32 例的字幕断言全挂；\n")
    lines.append("属**产品侧**（ffmpeg HLS 字幕 + seek 交互），非片源、非断言问题。\n")
    lines.append("")
    lines.append("## 运行\n")
    lines.append(f"```bash\ncd {os.path.basename(ROOT)}\n# 先 ./build_2x_sources.sh && ./build_subtitle_sources.sh 生成源\nbash assert_subtitle_cases_device.sh sub-W-base-pos   # 单例（wvtt, base, 起播即 seek）\n# 或 bash assert_subtitle_cases_device.sh          # 全量（需 DEBUG apk 支持 seek/speed 注入）\n```\n")
    return "\n".join(lines)

def combined_expect_md(s_seek, s_sub):
    (cid,zh_s,purpose_s,feat_s,scenes)=s_seek
    (_,zh_sub,purpose_sub,feat_sub)=s_sub
    lines=[]
    lines.append(f"# {cid} — {zh_s} ／ 字幕结构源 {zh_sub}\n")
    lines.append("本目录是 **seek + discontinuity 套件** 与 **subtitle + discontinuity 套件** 的共用结构源："
                 "既被 `sk-sp-*` 用例（2× + 跨 DISCONT 边界 seek）复用，也被字幕 32 矩阵例"
                 "（4 结构 × 2 封装 × 4 动作）复用。\n")
    lines.append("## 源构造（特征）\n")
    for f in feat_s: lines.append(f"- {f}")
    lines.append("")
    lines.append("## 一、Seek + Discontinuity 用法（2× 变速 + 跨 DISCONT 边界 seek）\n")
    lines.append(f"覆盖场景：{scenes}\n")
    lines.append("- **A/V 不同步 `desynchronisation` == 0**（头条）")
    lines.append("- `Reset playback due to audio timestamp` == 0；音频 PTS 真回退 == 0")
    lines.append("- seek 后播放时长 near `(total-lastseek)/speed`（±6s）；硬解健康；`event: end-file`（播放完整结束）== 1")
    lines.append("- 运行：`bash assert_seek_cases_device.sh sk-sp-*`\n")
    lines.append("## 二、Subtitle + Discontinuity 用法（tunnel 直通下外挂 WebVTT）\n")
    # feat_sub 是整串（用全角；分隔），不能直接 for 迭代（会逐字符输出）
    for f in [x.strip() for x in feat_sub.split("；") if x.strip()]:
        lines.append(f"- {f}")
    lines.append("")
    lines.append("- **Form A `wvtt`（TS 封装）**：`"+cid+"-wvtt/master.m3u8`")
    lines.append("- **Form B `fmp4`（HLS over fMP4）**：`"+cid+"-fmp4/master.m3u8`")
    lines.append("- **4 动作**：`pos` 起播即 seek / `mid` 播放中多次 seek / `sp` 2×+起播即 seek / `mdsp` 2×+播放中多次 seek\n")
    lines.append("**前置（必须，否则字幕断言必然全挂）**：ffmpeg 的 HLS 在 `read_header` 阶段把字幕 playlist")
    lines.append("置 `needed=0`、流 `discard=AVDISCARD_ALL`（**上游默认关闭字幕**），读取循环只处理")
    lines.append("`pls->needed` 的 playlist，`read_subtitle_packet()` 不会被调用、字幕永不去拉。")
    lines.append("必须经 `mpv.conf` 显式启用：`sid=1` + `sub-visibility=yes`（`msg-level=ffmpeg=debug` 需保留，")
    lines.append("靠它打印 HLS request 行）。`assert_subtitle_cases_device.sh` 已内置 `ensure_subtitle_conf()` 自动推送。\n")
    lines.append("**已修复（2026-09-25）：开播即 seek 时字幕不会被拉取。** 根因：`hls_read_seek` 对字幕 playlist")
    lines.append("用 `find_timestamp_in_playlist` 映射 `cur_seq_no`，但字幕 playlist 的段时序与主媒体不对应，")
    lines.append("使 `current_segment(pls)->url` 越界/为 NULL，`init_subtitle_context` 打开子 demuxer 失败（日志 `Format webvtt")
    lines.append("detected only with low score`）。修复：`hls_read_seek` 对 `is_subtitle` playlist 改为关闭子 demuxer 并从首段")
    lines.append("（`start_seq_no`）重新读取。修复后 position=0 与 position>0 均能拉取 `sub_en.vtt`（已真机验证）。\n")
    lines.append("判定：字幕被拉取(sub_en)≥1（须先启用字幕，见前置）；字幕轨识别≥1；**A/V 不同步==0**；Reset playback==0；音频PTS真回退==0；"
                 "播放完整；硬解健康；mixres 用 `VO: [mediacodec_embed]` 行识别 1280x720 与 1920x1080；**已知问题**：开播即 seek 时字幕不拉取。\n")
    lines.append("运行：`bash assert_subtitle_cases_device.sh sub-W-<b>-<act>` / `sub-E-<b>-<act>`（需 DEBUG apk）\n")
    return "\n".join(lines)

# ---------------- 写文件 ----------------
written=[]
for d in DISC:
    cid=d[0]; p=os.path.join(ROOT,cid,"EXPECT.md")
    os.makedirs(os.path.dirname(p),exist_ok=True)
    with open(p,"w",encoding="utf-8") as f: f.write(disc_expect_md(d))
    written.append(p)

# seek 源：sk0-sk3（4 个）写独立 seek 文档；sk4-2x-*（4 个，与字幕共用）写合并文档
_subd={s[0]:s for s in SUB_SOURCES}
for s in SEEK_SOURCES:
    cid=s[0]; p=os.path.join(ROOT,cid,"EXPECT.md")
    os.makedirs(os.path.dirname(p),exist_ok=True)
    if cid.startswith("sk4-2x-"):
        with open(p,"w",encoding="utf-8") as f: f.write(combined_expect_md(s,_subd[cid]))
    else:
        with open(p,"w",encoding="utf-8") as f: f.write(seek_expect_md(s))
    written.append(p)

for p_ in PTS:
    cid=p_[0]; p=os.path.join(ROOT,"pts_robustness",cid,"EXPECT.md")
    os.makedirs(os.path.dirname(p),exist_ok=True)
    with open(p,"w",encoding="utf-8") as f: f.write(pts_expect_md(p_))
    written.append(p)

print(f"EXPECT.md 已写 {len(written)} 个")

# ===========================================================================
# 总纲 MD
# ===========================================================================
def md_table(header, rows):
    out=["| "+" | ".join(header)+" |","| "+" | ".join(["---"]*len(header))+" |"]
    for r in rows: out.append("| "+" | ".join(str(x) for x in r)+" |")
    return "\n".join(out)

disc_rows=[[d[0],d[1],f"视频{d[3]}/音频{d[4]}",d[5],
            f"[{d[0]}/]({d[0]}/EXPECT.md)"] for d in DISC]
seek_src_rows=[[s[0],s[1],s[4],f"[{s[0]}/]({s[0]}/EXPECT.md)"] for s in SEEK_SOURCES]
seek_matrix_rows=[[m[0],m[1],m[2],m[3],f"{m[4]}x",m[5],m[6]] for m in SEEK_MATRIX]
pts_rows=[[p[0],p[1],f"[pts_robustness/{p[0]}/](pts_robustness/{p[0]}/EXPECT.md)"] for p in PTS]
sub_rows=sub_matrix_rows()
sub_md_rows=[[r[0],r[1],r[3],r[4],f"{r[7]}x",f"[{r[1]}/]({r[1]}/EXPECT.md)"] for r in sub_rows]

md=[]
md.append("# HLS discontinuity 测试集 — 测试用例总纲（共纲领）\n")
md.append(f"> 生成时间：{datetime.date.today().isoformat()}  ｜  根目录：`hls_discontinuity_tests/`\n")
md.append("\n本索引汇总四套真机/HLS 测试的全部用例，便于按场景检索特定 case。每个目录级用例都配有 `EXPECT.md`（目的 / 特征 / 预期 / 判定）。\n")
md.append("\n## 套件一览\n")
md.append("- **Discontinuity**（case01-25）：开播到 EOF 的 discontinuity 处理，25 例，非倍速。判据脚本 `assert_cases_device.sh`。")
md.append("- **Seek + Discontinuity**（sk0-sk4 源，25 矩阵例）：跨 DISCONT 边界 seek，含 1×/2× + 起播即 seek/中途 seek。判据脚本 `assert_seek_cases_device.sh`。")
md.append("- **pts_robustness**（p01-p12）：discontinuity 组内不一致段完整播完 / 不丢段。判据脚本 `assert_pts_robustness_device.sh`。")
md.append("- **Subtitle + Discontinuity**（4 结构源，32 矩阵例）：tunnel 直通下外挂 WebVTT 字幕 + discontinuity + 2×/seek。判据脚本 `assert_subtitle_cases_device.sh`。\n")
md.append("\n## 1. Discontinuity 用例（case01-25）\n")
md.append(md_table(["用例","场景","解码器重建(视/音)","时长s","EXPECT.md"],disc_rows))
md.append("\n## 2. Seek + Discontinuity（源 + 矩阵例）\n")
md.append("### 2.1 源目录（8 个，复用）\n")
md.append(md_table(["源目录","说明","覆盖场景","EXPECT.md"],seek_src_rows))
md.append("\n### 2.2 矩阵例（25 个，来自 assert_seek_cases_device.sh）\n")
md.append(md_table(["用例ID","源","模式","seek(s)","倍速","总时长s","说明"],seek_matrix_rows))
md.append("\n## 3. pts_robustness 用例（p01-p12）\n")
md.append(md_table(["用例","场景","EXPECT.md"],pts_rows))
md.append("\n## 4. Subtitle + Discontinuity（32 矩阵例）\n")
md.append(md_table(["用例ID","结构源","封装","动作","倍速","结构源EXPECT"],sub_md_rows))
md.append("\n> **前置**：ffmpeg HLS 默认把字幕 playlist 置 `needed=0`/`discard=AVDISCARD_ALL`，必须经 `mpv.conf` 启用 `sid=1`+`sub-visibility=yes`（脚本已内置 `ensure_subtitle_conf()` 自动推送）。\n")
md.append("> **已修复（2026-09-25）**：开播即 seek 时字幕不会被拉取（根因 `hls_read_seek` 对字幕 playlist 映射 `cur_seq_no` 越界）。修复后 `hls_read_seek` 对 `is_subtitle` playlist 从首段重新读取，32 例字幕断言已全部通过。\n")
md.append("\n## 判定标准速查\n")
md.append("- **Discontinuity**：播放时长≈期望(±3s)；硬解报错=0；软解回退=0；持续硬解；音频PTS真回退=0；Reset playback=0；end-file(播放完整结束)=1；视频/音频重建==期望；分辨率/音频识别==期望；A/V不同步=0（音频参数切换类为已知抖动观察项）。")
md.append("- **Seek**：A/V不同步=0（头条）；Reset playback=0；音频PTS真回退=0；seek后播放时长 near (total-lastseek)/speed(±6s)；硬解健康；mixres 识别 1280x720。")
md.append("- **pts_robustness**：段完整(请求段数==m3u8段数)；duration↔EOF 对应；无网络失败；desync=0；音频PTS真回退=0；硬解报错=0。")
md.append("- **Subtitle**：字幕被拉取(sub_en)≥1（须 mpv.conf 启用 sid=1/sub-visibility=yes）；字幕轨识别≥1；A/V不同步=0；Reset playback=0；音频PTS真回退=0；播放完整；硬解健康；mixres 用 `VO: [mediacodec_embed]` 行识别 1280x720 与 1920x1080（seek 拉字幕问题已修复）。\n")
md.append("\n## 如何运行全套回归\n")
md.append("```bash\ncd hls_discontinuity_tests\nbash assert_cases_device.sh            # 1) discontinuity 25 例（非倍速）\nbash assert_seek_cases_device.sh         # 2) seek 交叉（Tier1 1× 无需 DEBUG；mid/2× 需 DEBUG apk）\nbash assert_pts_robustness_device.sh     # 3) pts_robustness 12 例\nbash assert_subtitle_cases_device.sh     # 4) subtitle 32 例（需 DEBUG apk）\n# 进度落盘版：run_progress.sh {cases|seek|subtitle} [用例...]\n```\n")
with open(os.path.join(ROOT,"TESTCASES-INDEX.md"),"w",encoding="utf-8") as f:
    f.write("\n".join(md))
print("TESTCASES-INDEX.md 已写")

# ===========================================================================
# Excel
# ===========================================================================
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
from openpyxl.utils import get_column_letter

wb=Workbook()
hdr_fill=PatternFill("solid",fgColor="1F4E78"); hdr_font=Font(color="FFFFFF",bold=True)
wrap=Alignment(vertical="top",wrap_text=True)

def add_sheet(name, header, rows, widths):
    ws=wb.create_sheet(name)
    ws.append(header)
    for c in range(1,len(header)+1):
        cell=ws.cell(1,c); cell.fill=hdr_fill; cell.font=hdr_font; cell.alignment=Alignment(vertical="center")
    for r in rows:
        ws.append(r)
    for c,w in enumerate(widths,1):
        ws.column_dimensions[get_column_letter(c)].width=w
    for row in ws.iter_rows(min_row=2):
        for cell in row: cell.alignment=wrap
    ws.freeze_panes="A2"
    ws.auto_filter.ref=ws.dimensions
    return ws

# Overview
ov=[["Discontinuity",25,"case01-25","assert_cases_device.sh","开播到 EOF 的 discontinuity 处理（非倍速）"],
    ["Seek+Discontinuity",25,"sk0-sk4 源 / 矩阵例","assert_seek_cases_device.sh","跨 DISCONT 边界 seek（1×/2× + 起播即 seek/中途 seek）"],
    ["pts_robustness",12,"p01-p12","assert_pts_robustness_device.sh","discontinuity 组内不一致段完整播完 / 不丢段"],
    ["Subtitle+Discontinuity",32,"4 结构 × 2 封装 × 4 动作","assert_subtitle_cases_device.sh","tunnel 直通下外挂 WebVTT 字幕 + discontinuity + 2×/seek"]]
add_sheet("总览",["套件","用例数","范围","判据脚本","说明"],ov,[20,8,28,30,46])

disc_x=[[d[0],d[1],"Discontinuity",f"视频{d[3]}/音频{d[4]}",d[5],
         (d[8] if d[8]!="-" else ""),(d[9] if d[9]!="-" else ""),f"[{d[0]}/EXPECT.md]({d[0]}/EXPECT.md)"] for d in DISC]
add_sheet("Discontinuity",["用例","场景","套件","解码器重建(视/音)","时长s","分辨率识别","音频识别","EXPECT.md"],
          disc_x,[26,28,14,18,8,14,16,30])

seek_x=[[m[0],m[1],m[2],m[3],f"{m[4]}x",m[5],m[6],f"[{m[1]}/EXPECT.md]({m[1]}/EXPECT.md)"] for m in SEEK_MATRIX]
add_sheet("Seek",["用例ID","源","模式","seek(s)","倍速","总时长s","说明","源EXPECT.md"],
          seek_x,[16,16,8,14,8,10,40,30])

pts_x=[[p[0],p[1],"pts_robustness",f"[pts_robustness/{p[0]}/EXPECT.md](pts_robustness/{p[0]}/EXPECT.md)"] for p in PTS]
add_sheet("PtsRobustness",["用例","场景","套件","EXPECT.md"],pts_x,[22,40,16,40])

sub_x=[[r[0],r[1],r[3],r[4],f"{r[7]}x",f"[{r[1]}/EXPECT.md]({r[1]}/EXPECT.md)"] for r in sub_rows]
add_sheet("Subtitle",["用例ID","结构源","封装","动作","倍速","结构源EXPECT.md"],sub_x,[20,16,18,22,8,30])

wb.remove(wb["Sheet"])
wb.save(os.path.join(ROOT,"TESTCASES-INDEX.xlsx"))
print("TESTCASES-INDEX.xlsx 已写")
print("全部完成")
