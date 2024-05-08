```c
# test-streams
1.DISCONTINUITY test stream
https://rolandjon.github.io/test-streams/sample-discontinuity-stream/sample-discontinuity-stream.m3u8

/////////////////////
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-TARGETDURATION:9
#EXTINF:4.533333,
sample-mediaevents-sd0.ts
#EXTINF:8.333333,
sample-mediaevents-sd1.ts
#EXT-X-DISCONTINUITY
#EXTINF:5.125000,
sintel-trailer0.ts
#EXT-X-DISCONTINUITY
#EXTINF:3.433333,
sample-mediaevents-sd2.ts
#EXT-X-ENDLIST
/////////////////////

2. DASH with subtitles
https://rolandjon.github.io/test-streams/sample-mpd-with-subtitles/sample-mpd-with-subtitles.mpd

3.DASH with 32 period
https://rolandjon.github.io/test-streams/dash-32-period/dash_32period.mpd

4.fmp4 over hls
https://rolandjon.github.io/test-streams/fmp4_over_hls/index.m3u8
