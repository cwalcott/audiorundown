# AudioRundown

A macOS command-line tool that turns long recordings into readable Markdown rundowns and selected MP3 clips for listening or manual upload to Overcast.

Transcription uses Apple's **SpeechAnalyzer / SpeechTranscriber**. Rundowns can use **OpenAI Sol via API**, **local Ollama**, or the **Foundation Models framework's on-device Apple Intelligence model**. Clip selection and FFmpeg audio export stay local. OpenAI is an explicit option requiring an API key and separate billing; local backends need no key. There is no automatic cloud fallback or third-party Swift package dependency.

## One-time setup

- Apple silicon Mac, macOS 26 or later, with a supported speech language.
- Xcode 27 or later to build this version (it uses the current Foundation Models SDK).
- For `--model apple`: Apple Intelligence enabled and its on-device model ready. `doctor` reports Apple model availability.
- For `--model qwen3.6:27b` (or another Ollama model): Ollama running locally with that model already installed. Apple Intelligence is not required for Ollama summarization or selection.
- FFmpeg for audio decoding and MP3 export: `brew install ffmpeg` if needed.

Clone or download the repository, then build and install from its directory:

```sh
cd /path/to/audiorundown
swift build -c release
mkdir -p ~/.bin
cp .build/release/audiorundown ~/.bin/audiorundown
export PATH="$HOME/.bin:$PATH"
audiorundown doctor

# Optional: save Sol as your default (requires an API key and billing):
audiorundown configure --model openai:gpt-6.1-sol \
  --reasoning medium --max-cost 1.00 --editor "Visual Studio Code"
```

For local summarization, use `--model apple` or choose an installed Ollama model. To save a local default, run `audiorundown configure --model apple` or `audiorundown configure --model MODEL_NAME`. For Ollama, install a model once if needed with `ollama pull qwen3.6:27b`, then start the Ollama app or `ollama serve`. AudioRundown connects only to `127.0.0.1:11434`; it does not download models, use Ollama cloud models, or fall back to another provider. The Ollama backend currently requests a 32K context window with thinking disabled. Long recordings are processed in pieces, so the full transcript does not need to fit in that window. Transcription still uses Apple’s Speech framework regardless of the summary model.

Add `export PATH="$HOME/.bin:$PATH"` to your shell configuration if `~/.bin` is not already on your `PATH`. Rebuild and copy the executable again after source updates.

`configure` saves preferences in `~/.config/audiorundown/config.json`. Run it without options to inspect them. It never saves the API key. Command flags override preferences; `--model apple` or an installed Ollama model uses local summarization even when Sol is saved. A fresh installation without preferences defaults to Apple. The saved summary model does not change the local selection model. `--editor` takes a macOS application name; without it, `--open` uses the system's default Markdown app. `AUDIORUNDOWN_CONFIG` can override the config path for isolated environments.

## Everyday workflow

After the [one-time setup](#one-time-setup), the usual process is two commands:

```sh
audiorundown rundown "$HOME/Downloads/recording.mp3" --open
# Read the summary, then choose what to listen to:
audiorundown select "$HOME/Downloads/recording.mp3"
```

`rundown` transcribes if needed, then summarizes with your saved model preference. It prints the exact Markdown path and a copyable command for choosing clips. `--open` opens the Markdown in your configured app; omit it to open the printed path yourself. Add `--interactive` to start choosing clips immediately after generation.

Defaults are `en-US` and folders beside the source audio. With Sol selected, the files are:

```text
Downloads/
  recording.mp3
  recording.transcript/
    transcript.json, transcript.txt, transcript.srt, listening-guide-prompt.md
    active-rundown.json
    .openai-rundown-cache/
    rundown-openai/
      rundown.md, rundown.json, model-draft.json, api-usage.json
  recording.clips/
    selection-001/
      Episode title - 03c - Clip title.mp3
      export.json, sections.json
    selection-002/
      ...
```

The Markdown has numbered main segments, each with a short **Summary** and a **Detailed rundown** of lettered clips. The generator aims for about five main segments, usually within ten, while following the recording's topics.

At the selection prompt, enter IDs or describe what you want:

```text
1, 3b
2a-2j
Export the equipment discussion and the travel tips
Export the whole interview segment with 10 seconds before it
```

IDs export immediately without a model. Descriptions use a local model and may ask for clarification. `list` shows the available IDs, `show 3b` reads an item's summary, and `quit` exits. Selecting a parent and its child exports the parent once. Start with `select ... --preview` to inspect choices without exporting. Selection chooses existing catalog entries; use `clip` below for arbitrary time ranges.

A range such as `2a-2j` creates **one continuous MP3**, from the start of `2a` through the end of `2j`, including any gaps between the clips. Its name uses the saved parent segment title, for example `Studio Notes 2026-06-15 - 02a-02j - Recording techniques.mp3`. No model call is needed to select or name it. Clip ranges can cross segment boundaries (`2h-3b`); ranges of whole segments (`2-4`) also work, with their segment titles combined. Both endpoints must be saved IDs of the same kind, in chronological order.

Use commas for separate files: `2a, 2b` exports two clips; `2a-2j, 4b` exports one combined range plus one separate clip. Contained selections are exported once; partially overlapping ranges are rejected so you can choose a single combined range explicitly. You can also run `audiorundown select recording.mp3 --request "2a-2j" --preview` before exporting.

Selected filenames put the episode first: `Studio Notes 2026-06-15 - 03c - Choosing a microphone.mp3`. The MP3 title is **“Studio Notes 2026-06-15 · 3c · Choosing a microphone”**. The episode comes from the source's title tag, falling back to its filename. Filenames use the rundown ID, with at least two digits, instead of a counter that restarts with each batch. This groups clips by episode and catalog order when they share a folder.

Only the descriptive clip title is shortened, at word boundaries up to 60 characters; filenames shorten it further if needed for filesystem limits and replace unsafe path characters. The episode name and ID remain visible. Padded selections add their source time range to the filename to distinguish versions. Repeating an identical selection gives the same filename in a new selection folder. The album tag keeps the full episode title, the artist comes from the source when present, and track numbers preserve export order. Export records retain the full clip title, summary, and original time range. Explicit titles in manual `clip` and ordinary `export` plans are preserved.

Upload the desired MP3s to Overcast manually. Each exported MP3 is self-contained, so you can delete the source and generated folders once you no longer need them. Keeping the transcript folder lets you reuse the transcript and cached summaries; further clip exports still need the original audio.

`select recording.mp3` finds the latest successfully generated or imported rundown remembered in the adjacent transcript folder. You can also pass a transcript folder, `transcript.json`, or a specific rundown folder/file. With an older folder containing multiple rundowns and no saved preference, pass the desired rundown folder explicitly. If you put the transcript elsewhere, use that folder or the printed selection command.

### Generate a full-episode rundown with Sol

Set `OPENAI_API_KEY` in the shell that runs the command. If you already exported it in `~/.zshrc`, run `source ~/.zshrc`. Keep the key out of the repository, command-line arguments, logs, and chat. The API project needs Responses access and API billing/model access.

```sh
audiorundown rundown "/path/to/recording.mp3" \
  --model openai:gpt-6.1-sol --interactive
```

You can pass an existing transcript folder or `transcript.json` to reuse transcription. This sends the **entire timestamped transcript text** to OpenAI in one generation request, using medium reasoning and structured output. The model chooses original transcript entry boundaries; the utility validates complete entry coverage, derives times and IDs, and saves a selectable rundown. Audio is not uploaded. Brief gaps between speech entries are preserved.

Default output is `recording.transcript/rundown-openai/`, containing `rundown.md`, `rundown.json`, `model-draft.json`, and `api-usage.json`. Open the selector later with:

```sh
audiorundown select "/path/to/recording.transcript/rundown-openai"
```

Selection defaults to Apple's local model; exact IDs require neither a model nor the API key. Use `select --model gemma4:31b` to select by description with local Ollama instead. API generation is currently supported only for `openai:gpt-6.1-sol`.

Optional API settings:

- `--reasoning low|medium|high|xhigh|max` (default `medium`).
- `--max-cost 1.00` (default): before generation, the API counts input tokens and the utility compares a conservative estimated maximum with this USD amount. Counting sends the transcript even if generation is blocked. The estimate assumes standard Sol prices checked October 4, 2026, up to 25,000 output tokens including reasoning, and cache-write pricing for all input. It is not a billing guarantee and excludes taxes or account-specific charges. The API path currently accepts at most 250,000 input tokens to stay within short-context pricing.
- `--out-dir DIR` for a different destination. Finished outputs are reused only when transcript, model, prompt, and reasoning settings match.

Actual token usage and an estimated cost are printed and saved in `api-usage.json`. Output-token usage includes reasoning, and cache-read/write counts are used when reported. Check the OpenAI billing dashboard for the final charge. Responses use `store: false`; this does not promise zero server-side retention under every account policy.

API responses are cached locally in `.openai-rundown-cache` inside the transcript folder before validation. Repeating the same request reuses its response even with a new output destination, preventing duplicate charges. Incomplete or invalid answers are retained but never published as finished rundowns. There are no automatic paid retries. An interrupted connection may still have incurred usage; check the dashboard before retrying. A leftover `.lock` directory blocks concurrent generation: remove only that indicated lock after confirming no process is still using it. Do not clear the response cache merely to rerun an unchanged request.

### Use a rundown from Codex or ChatGPT

Import a Markdown listening guide once, using the original transcript to identify the source audio and recording duration:

```sh
audiorundown import-rundown "/path/to/episode-rundown.md" \
  --transcript "/path/to/recording.transcript" \
  --out-dir "work/imported-rundown" \
  --engine "Sol via Codex"
audiorundown select "work/imported-rundown"
```

The import does not call a model. It preserves titles, summaries, IDs, and timestamps, and saves the supplied Markdown as `original.md` alongside `rundown.json` and a normalized `rundown.md`. Without `--out-dir`, the destination is `episode-rundown.rundown` beside the input Markdown. Existing output folders are never replaced. `--engine` is an optional provenance label, not a model to call.

In the selector, enter `list`, `show 3d`, or IDs such as `3d, 6i`. Entering IDs or a descriptive selection exports MP3s immediately; add `--preview` when starting the selector to inspect selections without exporting. Imported rundowns use Apple's on-device model for descriptive requests by default. To use Ollama instead, start the selector with `--model gemma4:31b`. Exact IDs need no model, and Sol/API access is not needed to select clips from its saved rundown. Requests select existing catalog entries; they do not create new, finer subdivisions.

The importer accepts this specific format (including the heading levels and inline times), rather than arbitrary Markdown. Ask the summarizing assistant to follow it:

```markdown
# Episode title

## 1. Main topic — 00:00:01–00:05:00
### Summary
One paragraph summarizing the main topic.
### Detailed rundown
**1a. First story — 00:00:01–00:02:30**
A more detailed description.
**1b. Second story — 00:02:33–00:05:00**
A more detailed description.
```

Segment IDs must be consecutive (`1`, `2`, …), with consecutive clip letters under each (`1a`, `1b`, …). Use original `HH:MM:SS` timestamps (optional fractional seconds), ordered nonoverlapping segments, and clips contained within their segment. Gaps for silence or transitions are allowed and never filled automatically. Malformed headings, missing summaries, and invalid ranges are rejected before writing output. The selected transcript must belong to the recording summarized in the Markdown; timing validation cannot detect a guide for a different episode of similar length.

### Generate now, choose clips later

Omit `--interactive` to generate only the rundown. You can also start from an existing transcript folder or `transcript.json`:

```sh
audiorundown rundown "/path/to/recording.transcript" --model qwen3.6:27b
audiorundown select "/path/to/recording.transcript/rundown"
```

For a single request, or to check the selection before exporting:

```sh
audiorundown select "/path/to/recording.transcript/rundown" \
  --request "3b, 5" --preview
audiorundown select "/path/to/recording.transcript/rundown" \
  --request "Export the guitar discussion with 10 seconds before it"
```

`--preview` creates no files. `--out-dir DIR` chooses a new export folder; `--source AUDIO` locates the original if you moved it. Exact IDs require no language model. Explicit numeric padding such as `10 seconds before` or `10 seconds after` is applied by code to preserve the requested direction. For descriptions, `select` uses the saved local model, or Apple for imported/API rundowns; `--model NAME` overrides it. Natural-language selection uses only the saved catalog, so use the existing `clip` command below for custom time ranges or finer cuts.

`rundown --out-dir DIR` changes the rundown destination; its transcript still uses the normal adjacent folder. To choose a different transcript location, run `transcribe --out-dir DIR` first and pass that folder to `rundown`. Intermediate model results are cached in the transcript's `.rundown-cache` folder, so rerunning after an interruption reuses completed analysis. Caches are separate for each backend and Ollama model digest. A finished rundown is reused without changing its IDs; choose a new rundown destination to regenerate it or compare models:

```sh
audiorundown rundown "/path/to/recording.transcript" \
  --model qwen3.6:27b --out-dir "work/qwen-rundown"
audiorundown select "work/qwen-rundown"
```

Local rundowns are experimental. The model summarizes short transcript pieces before grouping them, so clip boundaries are approximate. If structured grouping fails, the tool can use vocabulary changes to place boundaries while the selected model writes the summaries. All backends can omit topics or misattribute speakers. See [validation and limitations](VALIDATION.md) for the checks performed and what they do not establish.

## Transcription options and output files

Use optional overrides only when you want a different language or destination:

```sh
audiorundown transcribe "/path/to/recording.mp3" \
  --language en-GB --out-dir "work/another-recording.transcript"
```

The first run may download Apple's language assets into system-managed storage. The audio is not uploaded. Use `--no-download` to fail instead if assets are missing. `audiorundown languages` lists supported locales and marks installed ones.

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
audiorundown context "/path/to/recording.transcript/transcript.json" \
  --detail overview --output work/overview-context.md
```

Give that file to Codex or another assistant to summarize. Then prepare a more detailed view of just a section:

```sh
audiorundown context "/path/to/recording.transcript/transcript.json" \
  --detail detailed --start 42:15 --end 49:30 --output work/section-context.md
```

Choose `overview`, `standard`, or `detailed`. This changes the summary instructions; it never discards the underlying transcript or requires retranscription. Selected ranges include overlapping segments in full to retain context. Timestamps always refer to the original recording.

**`context` writes a prompt plus transcript; it does not generate a summary or call a model.** Providing the context file to a hosted assistant shares its transcript text with that service. Use `rundown --model apple` or an installed Ollama model for on-device summarization instead. No speaker names are inferred by the transcription utility. Review important names, quotations, and clip boundaries against the audio.

## Optional: export clips from the terminal

Use these commands for exact time ranges or a hand-written export plan.

### Export one section

```sh
audiorundown clip "/path/to/recording.mp3" \
  --start 42:15 --end 49:30 \
  --title "The discussion I want to hear" \
  --album "My listening list" \
  --artist "Studio Notes" \
  --output "work/episodes/selected-discussion.mp3"
```

Times accept seconds (`2535.5`), minutes/seconds (`42:15.5`), or hours/minutes/seconds (`00:42:15.5`). They must be within the source duration and end after they start. Add a few seconds around a topic if you want more context; the utility does not guess sentence boundaries.

MP3s are encoded at 128 kbps / 44.1 kHz with accurate seeking. The tool decodes the source to check its real duration, then seeks by decoding from the beginning for each clip. This takes more time than index-based seeking but keeps cuts aligned with the transcript even when MP3 headers are inaccurate. Re-encoding avoids approximate MP3 frame-copy boundaries. Files contain title, album, artist, track number, and a comment recording the source time range. The utility verifies the exported duration before publishing each result. Encoding incurs one additional lossy generation; the original stays intact.

### Export several mini episodes

Create `selected.json`, using `examples/sections.json` as a template:

```json
{
  "album": "Studio Notes — Episode 12 — selections",
  "artist": "Studio Notes",
  "clips": [
    { "title": "First topic", "start": "00:42:15", "end": "00:49:30" },
    { "title": "Second topic", "start": "01:12:00", "end": "01:19:45" }
  ]
}
```

These are illustrative times, not recommendations for a particular recording.

```sh
audiorundown export "/path/to/recording.mp3" \
  --plan selected.json
```

By default, batch export creates a `.clips` folder beside the source audio, such as `/path/to/recording.clips/`. Add `--out-dir work/episodes` to choose another destination.

The tool validates all ranges before exporting. It writes numbered MP3s, a copy of the selection plan, and `export.json` with the original source ranges. Titles are sanitized for filenames; duplicate titles stay distinct via their sequence numbers. Batch results appear only when the whole batch succeeds. Output folders must be new.

You can then upload the MP3s through your Overcast upload workflow. This utility does not log in to Overcast, upload files, or create an RSS feed. Playback and display behavior depend on the player.

## Development and verification

```sh
swift test
swift build -c release
python3 scripts/test_exports.py .build/release/audiorundown
```

The integration check creates temporary three-tone audio, verifies the selected time range by its actual audio content, checks codec/duration/ID3 tags, and exercises safe filenames, batch export, invalid ranges, and overwrite rejection. It does not require personal recordings or download speech assets.

Keep recordings, transcripts, and model outputs in ignored `work/`, `*.transcript/`, or `*.clips/` directories. Do not commit them. Swift unit tests do not exercise Apple's speech service; test that separately with a recording you can use on a supported Mac. See [VALIDATION.md](VALIDATION.md) for findings and limitations, and [AGENTS.md](AGENTS.md) for contributor guidance.

## References

- [Apple: SpeechAnalyzer and on-device long-form transcription](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Apple: Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Apple: SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Ollama: local chat API and structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- [FFmpeg: seeking, duration, and metadata](https://ffmpeg.org/ffmpeg.html)
