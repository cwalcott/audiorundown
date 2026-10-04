# AudioRundown

## Purpose and workflow

AudioRundown is a Swift command-line utility for transcribing long recordings, creating readable episode rundowns, and exporting selected sections as MP3s for listening or manual upload to Overcast. Read `README.md` for commands and `VALIDATION.md` for measured results and known limitations.

Prefer simple defaults and an interactive selection workflow. Rundowns should have roughly five main segments, usually no more than ten, but follow the recording's topics rather than enforcing a fixed count. Each numbered segment has a short Summary followed by a Detailed rundown of lettered clips. Keep Markdown easy to skim.

## Build and verify

- Swift 6 package targeting macOS 26 or later on Apple silicon. The current implementation is built with Xcode 27 or later; it uses Apple Speech and Foundation Models frameworks. There are no third-party Swift package dependencies.
- FFmpeg and FFprobe are required for decoding and export. Apple Intelligence is needed only for the Apple summarization/selection backend; Ollama is optional and uses an already installed local model.
- After Swift changes, run `swift test` and `swift build -c release` from the repository root. The executable is `.build/release/audiorundown`.
- When changing audio decoding, seeking, export, or export metadata, also run `python3 scripts/test_exports.py .build/release/audiorundown`. It uses synthetic audio and temporary files.
- For selection changes, exercise `select ... --preview` against an available saved rundown. Exact IDs need no model; test natural-language selection separately when its backend is available.
- Reuse saved transcripts for experiments. Full transcription and model runs are expensive and are not routine regression checks. Documentation-only edits do not require rebuilding.

## Code map

- `Sources/AudioRundown/CLI.swift`: argument parsing, command dispatch, and help.
- `Settings.swift`, `Workflow.swift`: saved preferences, rundown discovery, and next-step commands.
- `Transcription.swift`: Apple Speech transcription and transcript outputs.
- `RundownGenerator.swift`, `TopicGrouping.swift`: local summary generation and topic grouping.
- `Rundown.swift`, `RundownImport.swift`: saved catalog, validation, Markdown rendering and import.
- `LocalIntelligence.swift`, `OllamaClient.swift`: local model backends and structured generation.
- `OpenAIClient.swift`, `OpenAIRundown.swift`: explicit API transport, full-transcript generation, usage/cost estimates, and response caching.
- `Selection.swift`: interactive requests, catalog IDs, and export plans.
- `Clips.swift`, `Support.swift`: audio export, timecodes, subprocesses, and atomic outputs.
- `Tests/AudioRundownTests/`: Swift Testing tests; `scripts/test_exports.py`: FFmpeg integration checks.

Paths in this code map after the first entry are relative to `Sources/AudioRundown/`.

## Preserve these behaviors

- All times refer to the original decoded recording. MP3 container duration can be wrong; preserve PCM normalization for transcription and decoded-duration/accurate-seeking behavior for export.
- Model responses are untrusted data. Validate IDs, finite time ranges, ordering, containment, and padding before export. Exact-ID selection must remain independent of model availability.
- Generated schema-1 rundowns require complete coverage. Imported and API schema-2 rundowns allow gaps but require ordered, nonoverlapping segments and clips within their parent. API drafts must cover all transcript entries; timestamps are derived from validated entry indices. Preserve imported timestamps rather than filling gaps or shifting boundaries.
- Preserve stable saved IDs and truthful model provenance. Importing a rundown does not call its authoring model. Imported and API catalogs default to Apple for descriptive selection; `--model` can override the selector.
- Keep existing outputs intact and publish new output directories atomically. Pass subprocess arguments directly, without shell evaluation.
- Preserve explicit backend selection, loopback-only Ollama transport, and the absence of silent cloud fallback or automatic model downloads. Only an explicit `--model openai:gpt-6.1-sol` or that explicitly saved rundown preference sends transcript text to OpenAI; audio and selection stay local. Keep API keys out of source, arguments, logs, and saved responses. Preserve no-redirect transport, preflight cost checks, and local response reuse without automatic paid retries. Tests use synthetic responses; live API calls are not routine regression checks.
- Structural validation does not establish summary accuracy. Evaluate speaker attribution, jokes versus factual claims, music versus conversation, topic coverage, and useful listening boundaries separately. Record experimental findings without turning a single episode into a general model ranking.

## Repository hygiene

Keep recordings, transcripts, model caches, generated rundowns, and exported clips out of commits. Use ignored `work/`, `*.transcript/`, or `*.clips/` directories for local artifacts; use synthetic fixtures in tests. Do not depend on a particular user's Downloads paths in production code or tests.

Update CLI help and `README.md` when commands or defaults change. Add material experiment results to `VALIDATION.md`, distinguishing software checks from content-quality judgments. Keep this file focused on durable project guidance rather than session history.
