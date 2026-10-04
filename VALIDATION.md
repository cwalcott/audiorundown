# Verification on October 3, 2026

Tested on Apple silicon, macOS 27.0.1, Swift 6.4 / Xcode's macOS 27 SDK.

- `swift test`: 17 tests passed, including full rundown coverage, model boundary validation, exact-ID selection, parent/child deduplication, padding, fractional end-time safety, and fallback grouping, in addition to the original transcription/export helper tests.
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


## Local Ollama / Qwen comparison

- Added explicit `--model qwen3.6:27b` selection for rundown generation. Natural-language selection defaults to the backend saved in the rundown, with an optional override. Apple remains the default when generating a rundown without `--model`.
- The installed model was Qwen 3.6 27B, Q4_K_M, digest `bcbdbd4bcf86f2c4a56cd1698fb31f9434f7dd99752f71b636c750aaa67a49a5`. The local `/api/chat` request uses a 32,768-token context, temperature zero, and thinking disabled. There is no model download or cross-provider fallback. Transport is fixed to loopback, disables proxies, and rejects redirects and cloud-model metadata.
- The existing Stern transcript was reused without retranscribing. The complete rundown took 1,259.38 seconds (about 21 minutes) on the user's M3 Max MacBook Pro with 48 GB RAM. It has five main segments and 43 clips with validated complete, ordered timeline coverage. All structured grouping succeeded without the vocabulary fallback. Outputs are in ignored `work/stern-qwen-rundown`.
- New unit checks cover incomplete/empty Ollama responses, cloud-model rejection, and selection of the backend stored in a rundown. All 17 unit tests and the release build passed.
- Live checks confirmed valid structured selection with requested padding, missing-model errors without downloads, rejection of an existing rundown generated with another model, and exact-ID preview working even when the named model is not installed.
- A natural request using the saved Qwen backend selected `3d` with ten seconds of leading padding and exported 01:13:57.080–01:18:40.260. FFprobe confirmed 283.18 seconds and the expected title/album/artist tags. Reusing the finished rundown preserved both Markdown and JSON hashes.
- Qwen's writing is more concise than the Apple baseline, but it still misattributes Wolfie's concert experience to Howard and Mike Trainor's lunch to Gary. It describes the baby's arrival ambiguously as the daughter's birth, splits the Letterman conversation across two main segments, and summarizes performance lyrics as narrative content. Its valid JSON and complete timeline do not establish factual or editorial quality.

The user also supplied a ChatGPT rundown generated at a reported medium reasoning setting. The precise model was not supplied. That document has five main segments and 27 clips. It keeps the Letterman material together and gives the full Sting/Shaggy interview its own segment. Transcript spot-checks supported its baby story, Wolfie concert attribution, Sharon Stone anecdote, and performance boundaries. This is not an exhaustive accuracy audit. ChatGPT received the full timestamped transcript, whereas the current Qwen pipeline summarizes isolated excerpts and then works from those summaries; the comparison therefore measures both model and workflow differences. No OpenAI API request was made by this utility.


## Imported Sol rundown (2026-10-04)

- Added `import-rundown` for the documented numbered Markdown format. Imports use schema 2 with ordered, nonoverlapping ranges that may contain gaps; generated schema-1 rundowns still require full coverage. Imported provenance is displayed without claiming local generation, and local generation cannot mistake an imported catalog for cached model output.
- Imported the existing full-episode Sol medium result into `work/stern-sol-rundown`: six segments and 41 clips. Independently compared all 47 titles, IDs, and ranges with the original Markdown; all match exactly. The original Markdown is retained beside the JSON and normalized Markdown.
- Release CLI preview for `3d, 6i` reproduced 01:15:08–01:17:58 and 02:37:30–02:42:01, matching the two clips the user already listened to.
- Live Apple-model preview for “Export the Sharon Stone story with 10 seconds before it” selected 3d at 01:14:58–01:17:58. No API request or summary regeneration was needed. Imported catalogs default to Apple for descriptions, independently of the provenance label; `--model` overrides the selector as before.
- Tests cover JSON round-trip and selection boundary preservation, missing IDs/text, malformed headings, overlapping/empty/out-of-bounds ranges, clip containment, and continued strict schema-1 validation. Twenty tests passed; release build passed.
