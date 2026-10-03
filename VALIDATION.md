# Verification on October 3, 2026

Tested on Apple silicon, macOS 27.0.1, Swift 6.4 / Xcode's macOS 27 SDK.

- `swift test`: six tests passed (time parsing and rounding, range validation, CLI errors, filename safety, summary selection preserving original times, and failed-batch cleanup).
- `swift build -c release`: passed.
- `python3 scripts/test_exports.py .build/release/audiochapters`: passed. The source is a variable-bitrate MP3 without a Xing seek header. Checks include actual selected audio content, codec, duration, metadata, overwrite rejection, invalid ranges, and batch naming/track numbering.
- Apple's installed English speech assets were used with `--no-download` on the user-provided `THSS.2026-06-02.CF128K-HTB.mp3`.
- Full transcription succeeded: decoded duration 10,486.047375 seconds (2:54:46), 3,519 segments, 30,868 word timing runs. All segment ranges were finite, ordered within each segment, and within the source duration.
- An overview context for the full recording and a detailed context for 02:00–08:00 were generated successfully.
- Real-audio clip 03:19.680–04:53.040 exported successfully; FFprobe reported 93.36 seconds and the requested ID3 tags.
- Real-audio clip 02:54:25–02:54:40 exported successfully, covering a range beyond the source container's underestimated duration.

The test file exposed two important cases: Apple's direct compressed-file reading failed near EOF, and the MP3 container's estimated duration was about 24 seconds shorter than decoded audio. The utility now normalizes audio to temporary PCM before speech analysis, validates selections using decoded duration, and decodes from the beginning when seeking for clip export.

This is a functional test, not a transcription-accuracy benchmark. The transcript has not been manually corrected throughout. Summaries remain a separate assistant step; no Overcast upload or playback in Overcast was tested. User recordings, transcript outputs, and experiment clips are kept outside version control in `work/`.
