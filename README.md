# AudioChapters

Turn a long recording into a timestamped transcript, explore it at different levels of detail, and export selected sections as individual MP3 episodes.

Transcription runs locally through Apple's **SpeechAnalyzer / SpeechTranscriber**. There are no cloud API keys or Swift package dependencies. Audio decoding and MP3 export use FFmpeg.

## Everyday workflow

After the [one-time setup](#one-time-setup), start each new episode from the project directory:

```sh
cd ~/Development/cwalcott/audiochapters
.build/release/audiochapters transcribe "/path/to/recording.mp3"
```

**That is the only command you need to prepare an episode for discussion in Codex.**

The defaults are:

- **Language:** `en-US`.
- **Output folder:** beside the original audio, with `.transcript` replacing the file extension. For example, `/Users/cwalcott/Downloads/recording.mp3` produces `/Users/cwalcott/Downloads/recording.transcript/`.

When transcription finishes, the tool prints the output folder's path. Then continue in your Codex chat:

1. **Get an overview:** “Give me a high-level summary of the full episode in `/Users/cwalcott/Downloads/recording.transcript`, with timestamps.”
2. **Explore a section:** “Break down the Letterman section,” or “Give me more detail about 01:12–01:47.” You can change the level of detail without retranscribing.
3. **Choose clips:** “Export the Sharon Stone story and the Ralph billing story as separate MP3s with descriptive titles.” Codex can use the transcript and original audio path to prepare the selections and run the export commands.
4. **Listen:** Upload the resulting MP3s through your Overcast upload workflow.

Codex can read the local transcript directly; the `context` command is optional. If you use another assistant without access to these files, attach the transcript or use the [optional context workflow](#optional-prepare-context-for-an-assistant) below.

Transcription stays on your Mac. Summarizing in Codex shares the transcript text with the assistant; the utility itself does not generate summaries. MP3 uploads to Overcast are a separate step.

## One-time setup

- Apple silicon Mac, macOS 26 or later, with a supported speech language.
- Xcode 26 or later (including the macOS SDK and Swift toolchain).
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

**`context` writes a prompt plus transcript; it does not generate a summary or call a model.** Summarization in this chat shares that text with the assistant. There is no on-device summarization engine in this version. No speaker names are inferred by the transcription utility. Review important names, quotations, and clip boundaries against the audio.

## Optional: export clips from the terminal

You can ask Codex to export your selections, as above, or use these commands yourself.

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
- [Apple: SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [FFmpeg: seeking, duration, and metadata](https://ffmpeg.org/ffmpeg.html)
