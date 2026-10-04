# Validation and limitations

## Automated checks

Run from the repository root:

```sh
swift test
swift build -c release
python3 scripts/test_exports.py .build/release/audiorundown
```

The latest verification on October 4, 2026 passed all 32 Swift tests, the release build, and the FFmpeg integration checks on Apple silicon with macOS 27.0.1 and Swift 6.4 / Xcode 27.

The Swift tests cover time parsing, validated model boundaries, stable IDs, parent/child selection, padding, imported Markdown, source-time preservation, saved preferences, rundown discovery, and safe output handling. Synthetic API responses exercise refusal and incomplete-output handling, cost accounting, and local cache reuse without credentials or paid requests.

The integration script creates temporary audio with three distinct tones. It checks the actual audio content of a cut, MP3 codec and duration, metadata, shortened titles, source-tag fallbacks, successive export folders, overwrite rejection, and invalid ranges. It also exercises importing a rundown and selecting clips using the original MP3 path. Filename checks cover episode-first ordering, stable catalog IDs across batches, different episodes in a shared folder, and time-range suffixes for padded versions. Temporary fixtures are removed after the run.

These checks do not download speech assets, run live summary models, or make paid API requests. They verify software behavior, not transcription or summary accuracy.

## Audio timing

Manual testing with a long recording exposed two issues: Apple's direct compressed-file reader could fail near the end, and an MP3 container could report a duration shorter than the decoded audio.

Transcription therefore uses a temporary mono PCM file decoded by FFmpeg. Export checks the decoded source duration and seeks by decoding from the beginning. Both operations use the same timeline. This is slower than seeking through an MP3 index, but avoids shifting clips when seek headers are missing or inaccurate.

Exports are re-encoded at 128 kbps / 44.1 kHz and checked for the expected duration. Re-encoding adds a lossy generation. It does not establish that a selected boundary is a good place to start or stop listening.

## Summary and selection quality

Model experiments are informal development checks, not a benchmark or a general ranking:

- The Apple backend produced missed topics, incorrect speaker attribution, and jokes presented as facts. Structured generation sometimes failed validation or encountered content restrictions.
- Local Ollama models can produce more consistent structured output, but valid structure does not prevent attribution errors, omissions, or poor topic grouping. Results depend on the installed model and the recording.
- Full-transcript summaries showed promising topic coverage in spot checks. This comparison also changes the workflow: local backends summarize short excerpts before grouping them, while the API backend receives the full transcript. It does not isolate model quality.

All summaries should be treated as listening guides. Transcripts have no reliable speaker labels, and names may be misrecognized. Review quotations, factual claims, and important listening boundaries against the audio.

Exact-ID selection needs no model. Descriptive selection uses a local model to choose existing IDs and can choose the wrong topic. Use `--preview` to inspect a selection; explicit numeric before/after padding is applied by code. Use `clip` for custom boundaries.

Local rundown boundaries follow transcript pieces and may include neighboring material. API boundaries follow transcript entries and can omit silence, applause, or music beyond the final recognized words. Imported rundowns preserve supplied timestamps; timing validation cannot determine whether they describe the correct recording.

## Operational limits

- Transcription requires supported Apple speech hardware, software, and language assets. It does not checkpoint or resume an interrupted transcription.
- Rundown caches reuse completed work; they do not guarantee the accuracy of a saved answer. A finished rundown keeps its IDs stable.
- The API cost cap uses estimated prices and output limits, not a billing guarantee. Token counting sends transcript text even if the cap prevents generation. Interrupted requests can incur usage; no automatic paid retry is performed.
- Exported MP3 tags are verified with FFprobe. Display and playback behavior in Overcast or other players are not covered by automated tests. Uploading is manual.

Keep recordings, transcripts, model responses, and generated clips outside version control. Future validation notes should record reproducible behavior and limitations using synthetic or shareable examples.
