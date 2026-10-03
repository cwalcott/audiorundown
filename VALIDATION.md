# Verification on October 3, 2026

Tested on Apple silicon, macOS 27.0.1, Swift 6.4 / Xcode's macOS 27 SDK.

- `swift test`: 14 tests passed, including full rundown coverage, model boundary validation, exact-ID selection, parent/child deduplication, padding, fractional end-time safety, and fallback grouping, in addition to the original transcription/export helper tests.
- `swift build -c release`: passed.
- `python3 scripts/test_exports.py .build/release/audiochapters`: passed. The source is a variable-bitrate MP3 without a Xing seek header. Checks include actual selected audio content, codec, duration, metadata, overwrite rejection, invalid ranges, and batch naming/track numbering.
- Apple's installed English speech assets were used with `--no-download` on the user-provided `THSS.2026-06-02.CF128K-HTB.mp3`.
- Full transcription succeeded: decoded duration 10,486.047375 seconds (2:54:46), 3,519 segments, 30,868 word timing runs. All segment ranges were finite, ordered within each segment, and within the source duration.
- An overview context for the full recording and a detailed context for 02:00–08:00 were generated successfully.
- Real-audio clip 03:19.680–04:53.040 exported successfully; FFprobe reported 93.36 seconds and the requested ID3 tags.
- Real-audio clip 02:54:25–02:54:40 exported successfully, covering a range beyond the source container's underestimated duration.

The test file exposed two important cases: Apple's direct compressed-file reading failed near EOF, and the MP3 container's estimated duration was about 24 seconds shorter than decoded audio. The utility now normalizes audio to temporary PCM before speech analysis, validates selections using decoded duration, and decodes from the beginning when seeking for clip export.

This is a functional test, not a transcription-accuracy benchmark. The transcript has not been manually corrected throughout. The local rundown is an experimental draft: on this recording, model tests showed missed topics, incorrect attribution, and jokes described as facts. Structured generation also rejected some content and produced invalid indices. These tests distinguish software validation from summary accuracy; no Overcast upload or playback in Overcast was tested. User recordings, transcript outputs, and experiment clips are kept outside version control in `work/`.


## Apple-only rundown experiment

- The existing full Stern transcript was summarized on-device, using 69 bounded pieces and the installed model's 8,192-token context. No remote model was called.
- The completed result contains five main segments and 31 numbered clips, with full, ordered coverage of the original 10,486.047375-second timeline. Generated Markdown and JSON are in ignored `work/stern-local-rundown`.
- Apple's structured chapter plans failed validation or encountered content restrictions. The documented vocabulary-based fallback was used for all main/detail grouping in this run; Apple generated the actual text summaries and fallback titles.
- Exact-ID selection exported clip `4e`, 02:20:43.200–02:23:10.620. FFprobe confirmed 147.42 seconds and title/album/artist tags.
- A natural request for the dinner at Sting's place with ten seconds before it selected `4e`, 02:20:33.200–02:23:10.620, and exported successfully. The saved receipt records those original source times.
- Readability and accuracy remain weak: summaries can be verbose or cut off, speaker identities and anecdotes are sometimes confused, and topic grouping can combine unrelated discussions or divide a continuing interview. Natural-language interpretation is also experimental; exact IDs and preview mode are the dependable way to control selections.

The generated result is preserved without manual corrections as a baseline for later model comparisons. Functional checks do not establish factual summary accuracy.
