# AudioChapters

Turn a long recording into a readable rundown, then export selected sections as individual MP3 episodes for Overcast.

Transcription uses Apple's **SpeechAnalyzer / SpeechTranscriber**. Summaries and natural-language clip selection use the **Foundation Models framework's on-device Apple Intelligence model**. Audio decoding and MP3 export use FFmpeg. No cloud fallback, API keys, or Swift package dependencies.

## Everyday workflow

After the [one-time setup](#one-time-setup), run:

```sh
cd ~/Development/cwalcott/audiochapters
.build/release/audiochapters rundown "/path/to/recording.mp3" --interactive
```

This transcribes the audio if needed, generates a complete Markdown rundown, and opens a terminal prompt for choosing clips. Defaults are `en-US` and a `recording.transcript` folder beside the audio. Existing transcripts and finished rundowns are reused.

Read `recording.transcript/rundown/rundown.md` in your preferred Markdown viewer. Each numbered main segment has a short **Summary** followed by a **Detailed rundown** of lettered clips. The generator aims for about five main segments, usually within ten, with flexibility for recordings with many topics. The saved `rundown.json` keeps the IDs and original timestamps stable.

At the terminal prompt, enter a selection:

```text
1, 3b
Export the Sharon Stone story and the Ralph billing story
Export the whole Letterman segment with 10 seconds before it
```

These descriptions are examples; available topics depend on the recording. The tool prints the selected titles and times, then exports each selection as an MP3. If a request is ambiguous, it asks a follow-up question. Use `list` to see the IDs, `show 3b` to read an item's summary, or `quit` to exit. Selecting a parent segment and one of its children exports the parent once.

Exports go beside the audio in `recording.clips/selection-001/`, then `selection-002/`, and so on. Upload the MP3s through your Overcast upload workflow. Uploading is still manual.

### Generate now, choose clips later

Omit `--interactive` to generate only the rundown. You can also start from an existing transcript folder or `transcript.json`:

```sh
.build/release/audiochapters rundown "/path/to/recording.transcript"
.build/release/audiochapters select "/path/to/recording.transcript/rundown"
```

For a single request, or to check the selection before exporting:

```sh
.build/release/audiochapters select "/path/to/recording.transcript/rundown" \
  --request "3b, 5" --preview
.build/release/audiochapters select "/path/to/recording.transcript/rundown" \
  --request "Export the guitar discussion with 10 seconds before it"
```

`--preview` creates no files. `--out-dir DIR` chooses a new export folder; `--source AUDIO` locates the original if you moved it. Exact IDs require no language model. Natural-language selection uses only the saved catalog, so use the existing `clip` command below for custom time ranges or finer cuts.

`rundown --out-dir DIR` changes the rundown destination; its transcript still uses the normal adjacent folder. To choose a different transcript location, run `transcribe --out-dir DIR` first and pass that folder to `rundown`. Intermediate model results are cached in the transcript's `.rundown-cache` folder, so rerunning after an interruption reuses completed analysis. A finished rundown is reused without changing its IDs; choose a new rundown destination to regenerate it.

The local rundown is experimental. If Apple returns an invalid topic plan or declines structured generation, the tool reports that and uses vocabulary changes between notes to place approximate boundaries; Apple still writes the summaries and fallback titles. The model summarizes roughly two- to three-minute transcript pieces, groups them, then writes the finished summaries. Clip boundaries currently fall on those piece boundaries, so they can include neighboring material or miss the beginning of a story. Use `clip` for precise cuts. Our Stern tests also found missed topics, incorrect attribution, and jokes described as facts; this is a draft listening guide, not a verified account. Check selections with `--preview`, and use padding when a story needs more context. A long recording can take several minutes to summarize. All audio and transcript processing by these commands stays on your Mac.

## One-time setup

- Apple silicon Mac, macOS 26 or later, with a supported speech language.
- Xcode 27 or later to build this version (it uses the current Foundation Models SDK).
- Apple Intelligence enabled and its on-device model ready for rundown generation and natural-language selection. `doctor` reports availability.
- FFmpeg for audio decoding and MP3 export: `brew install ffmpeg` if needed.

```sh
cd ~/Development/cwalcott/audiochapters
swift build -c release
.build/release/audiochapters doctor
```

Rebuild after updating the source. You can also add `.build/release` to your PATH to use `audiochapters` directly, or use `swift run -c release audiochapters …`.

## Transcription options and output files

Use optional overrides only when you want a different language or destination:

```sh
.build/release/audiochapters transcribe "/path/to/recording.mp3" \
  --language en-GB --out-dir "work/another-recording.transcript"
```

The first run may download Apple's language assets into system-managed storage. The audio is not uploaded. Use `--no-download` to fail instead if assets are missing. `audiochapters languages` lists supported locales and marks installed ones.

Before transcription, FFmpeg decodes the source to a temporary mono 16 kHz PCM file (about 115 MB per hour). This avoids Apple's compressed-file reader failing near the end of some long MP3s, and uses the same decoding timeline as clip export. The temporary file is deleted when the command finishes or reports an error. A force-killed process may leave a temporary file in the system temporary directory.

The new output directory contains:

| File | Purpose |
| --- | --- |
| `transcript.txt` | Readable transcript with original start/end timestamps |
| `transcript.json` | Source path, language, duration, segments, and word/run timings |
| `transcript.srt` | Timestamped subtitles, one cue per finalized speech segment |
| `listening-guide-prompt.md` | Instructions for a summary and clip-selection workflow |

Source files are never edited. Existing outputs are never overwritten. If the transcript folder already exists, use it for your next summary, or choose a new `--out-dir` to transcribe again. Results are published only after transcription completes. Progress is printed to stderr as each minute of audio is processed. This first version does not checkpoint or resume an interrupted transcription.

## Optional: prepare context for an assistant

This is useful when you want a portable file containing both summary instructions and transcript text. It is optional when Codex can read the transcript directly.

Create context for a short overview of the entire show:

```sh
.build/release/audiochapters context "/path/to/recording.transcript/transcript.json" \
  --detail overview --output work/overview-context.md
```

Give that file to Codex or another assistant to summarize. Then prepare a more detailed view of just a section:

```sh
.build/release/audiochapters context "/path/to/recording.transcript/transcript.json" \
  --detail detailed --start 42:15 --end 49:30 --output work/section-context.md
```

Choose `overview`, `standard`, or `detailed`. This changes the summary instructions; it never discards the underlying transcript or requires retranscription. Selected ranges include overlapping segments in full to retain context. Timestamps always refer to the original recording.

**`context` writes a prompt plus transcript; it does not generate a summary or call a model.** Summarization in this chat shares that text with the assistant. Use `rundown` for on-device summarization instead. No speaker names are inferred by the transcription utility. Review important names, quotations, and clip boundaries against the audio.

## Optional: export clips from the terminal

Use these commands for exact time ranges or a hand-written export plan.

### Export one section

```sh
.build/release/audiochapters clip "/path/to/recording.mp3" \
  --start 42:15 --end 49:30 \
  --title "The discussion I want to hear" \
  --album "My listening list" \
  --artist "Howard Stern" \
  --output "work/episodes/selected-discussion.mp3"
```

Times accept seconds (`2535.5`), minutes/seconds (`42:15.5`), or hours/minutes/seconds (`00:42:15.5`). They must be within the source duration and end after they start. Add a few seconds around a topic if you want more context; the utility does not guess sentence boundaries.

MP3s are encoded at 128 kbps / 44.1 kHz with accurate seeking. The tool decodes the source to check its real duration, then seeks by decoding from the beginning for each clip. This takes more time than index-based seeking but keeps cuts aligned with the transcript even when MP3 headers are inaccurate. Re-encoding avoids approximate MP3 frame-copy boundaries. Files contain title, album, artist, track number, and a comment recording the source time range. The utility verifies the exported duration before publishing each result. Encoding incurs one additional lossy generation; the original stays intact.

### Export several mini episodes

Create `selected.json`, using `examples/sections.json` as a template:

```json
{
  "album": "Howard Stern — June 2, 2026 — selections",
  "artist": "Howard Stern",
  "clips": [
    { "title": "First topic", "start": "00:42:15", "end": "00:49:30" },
    { "title": "Second topic", "start": "01:12:00", "end": "01:19:45" }
  ]
}
```

These are illustrative times, not recommendations for a particular recording.

```sh
.build/release/audiochapters export "/path/to/recording.mp3" \
  --plan selected.json
```

By default, batch export creates a `.clips` folder beside the source audio, such as `/path/to/recording.clips/`. Add `--out-dir work/episodes` to choose another destination.

The tool validates all ranges before exporting. It writes numbered MP3s, a copy of the selection plan, and `export.json` with the original source ranges. Titles are sanitized for filenames; duplicate titles stay distinct via their sequence numbers. Batch results appear only when the whole batch succeeds. Output folders must be new.

You can then upload the MP3s through your Overcast upload workflow. This utility does not log in to Overcast, upload files, or create an RSS feed. Playback and display behavior depend on the player.

## Development and verification

```sh
swift test
swift build -c release
python3 scripts/test_exports.py .build/release/audiochapters
```

The integration check creates temporary three-tone audio, verifies the selected time range by its actual audio content, checks codec/duration/ID3 tags, and exercises safe filenames, batch export, invalid ranges, and overwrite rejection. It does not require the user's recordings or download speech assets.

User audio, transcripts, and local experiments belong in ignored `work/`. Do not commit them. Swift unit tests do not exercise Apple's speech service; test that separately with an actual recording on a supported Mac.

## References

- [Apple: SpeechAnalyzer and on-device long-form transcription](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple: Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Apple: SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [FFmpeg: seeking, duration, and metadata](https://ffmpeg.org/ffmpeg.html)
