# AudioChapters

Turn a long recording into a timestamped transcript, explore it at different levels of detail, and export selected sections as individual MP3 episodes.

Transcription runs locally through Apple's **SpeechAnalyzer / SpeechTranscriber**. There are no cloud API keys or Swift package dependencies. Audio decoding and MP3 export use FFmpeg, which is already installed on this Mac.

## Requirements and build

- Apple silicon Mac, macOS 26 or later, with a supported speech language.
- Xcode 26 or later (including the macOS SDK and Swift toolchain).
- FFmpeg for audio decoding and MP3 export: `brew install ffmpeg` if needed.

```sh
cd ~/Development/cwalcott/audiochapters
swift build -c release
.build/release/audiochapters doctor
```

Use `.build/release/audiochapters` below, or add that directory to your PATH to use `audiochapters` directly. `swift run -c release audiochapters …` also works.

## 1. Transcribe locally

```sh
.build/release/audiochapters transcribe "/path/to/recording.mp3" \
  --language en-US --out-dir "work/recording.transcript"
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

Source files are never edited. Existing outputs are never overwritten. Results are published only after transcription completes. Progress is printed to stderr as each minute of audio is processed. This first version does not checkpoint or resume an interrupted transcription.

## 2. Start broad, then ask for detail

Create context for a short overview of the entire show:

```sh
.build/release/audiochapters context work/recording.transcript/transcript.json \
  --detail overview --output work/overview-context.md
```

Give that file to Codex or another assistant to summarize. Then prepare a more detailed view of just a section:

```sh
.build/release/audiochapters context work/recording.transcript/transcript.json \
  --detail detailed --start 42:15 --end 49:30 --output work/section-context.md
```

Choose `overview`, `standard`, or `detailed`. This changes the summary instructions; it never discards the underlying transcript or requires retranscription. Selected ranges include overlapping segments in full to retain context. Timestamps always refer to the original recording.

**`context` writes a prompt plus transcript; it does not generate a summary or call a model.** Summarization in this chat shares that text with the assistant. There is no on-device summarization engine in this version. No speaker names are inferred by the transcription utility. Review important names, quotations, and clip boundaries against the audio.

## 3. Export one section

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

## 4. Export several mini episodes

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
  --plan selected.json --out-dir work/episodes
```

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
- [Apple: SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [FFmpeg: seeking, duration, and metadata](https://ffmpeg.org/ffmpeg.html)
