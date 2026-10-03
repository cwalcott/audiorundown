import Foundation
import Speech

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: [String], values: Set<String>, switches: Set<String> = []) throws {
        var index = 0
        while index < args.count {
            let token = args[index]
            if token == "--" { positional += args.dropFirst(index + 1); break }
            if token.hasPrefix("--") {
                guard options[token] == nil, !flags.contains(token) else { throw UserError("Duplicate option: \(token)") }
                if switches.contains(token) { flags.insert(token) }
                else if values.contains(token) {
                    index += 1
                    guard index < args.count, !args[index].hasPrefix("--") else { throw UserError("Missing value for \(token)") }
                    options[token] = args[index]
                } else { throw UserError("Unknown option: \(token)") }
            } else { positional.append(token) }
            index += 1
        }
    }

    func required(_ option: String) throws -> String {
        guard let value = options[option], !value.isEmpty else { throw UserError("Missing required option \(option)") }
        return value
    }
    func source() throws -> URL {
        guard positional.count == 1 else { throw UserError("Expected exactly one input audio file. Run audiochapters --help for examples.") }
        return fileURL(positional[0])
    }
}

@main
struct AudioChapters {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            log("Error: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func run(_ args: [String]) async throws {
        guard let command = args.first else { print(help); return }
        if ["help", "--help", "-h"].contains(command) || args.dropFirst().contains("--help") {
            print(help); return
        }
        let rest = Array(args.dropFirst())
        switch command {
        case "transcribe":
            let a = try Arguments(rest, values: ["--language", "--out-dir"], switches: ["--no-download"])
            let source = try a.source()
            let destination = a.options["--out-dir"].map(fileURL) ?? source.deletingPathExtension().appendingPathExtension("transcript")
            try await Transcription.run(source: source, language: a.options["--language"] ?? "en-US", destination: destination, downloadAssets: !a.flags.contains("--no-download"))
        case "rundown":
            let a = try Arguments(rest, values: ["--language", "--out-dir"], switches: ["--no-download", "--interactive"])
            let output = try await RundownGenerator.run(input: a.source(), destination: a.options["--out-dir"].map(fileURL), language: a.options["--language"] ?? "en-US", downloadAssets: !a.flags.contains("--no-download"))
            if a.flags.contains("--interactive") {
                try await Selection.run(input: output, request: nil, destination: nil, sourceOverride: nil, preview: false)
            }
        case "select":
            let a = try Arguments(rest, values: ["--request", "--out-dir", "--source"], switches: ["--preview"])
            try await Selection.run(input: a.source(), request: a.options["--request"], destination: a.options["--out-dir"].map(fileURL), sourceOverride: a.options["--source"].map(fileURL), preview: a.flags.contains("--preview"))
        case "clip":
            let a = try Arguments(rest, values: ["--start", "--end", "--output", "--title", "--album", "--artist"])
            try Clips.single(source: a.source(), output: fileURL(a.required("--output")), start: a.required("--start"), end: a.required("--end"), title: a.options["--title"], album: a.options["--album"], artist: a.options["--artist"])
        case "export":
            let a = try Arguments(rest, values: ["--plan", "--out-dir"])
            let source = try a.source()
            let destination = a.options["--out-dir"].map(fileURL) ?? source.deletingPathExtension().appendingPathExtension("clips")
            try await Clips.export(source: source, planURL: fileURL(a.required("--plan")), destination: destination)
        case "context":
            let a = try Arguments(rest, values: ["--detail", "--start", "--end", "--output"])
            try SummaryContext.run(input: a.source(), output: fileURL(a.required("--output")), detail: a.options["--detail"] ?? "overview", start: a.options["--start"], end: a.options["--end"])
        case "languages":
            guard rest.isEmpty else { throw UserError("languages takes no arguments.") }
            let installed = Set(await SpeechTranscriber.installedLocales.map(\.identifier))
            for locale in await SpeechTranscriber.supportedLocales.sorted(by: { $0.identifier < $1.identifier }) {
                print("\(locale.identifier)\(installed.contains(locale.identifier) ? " (installed)" : "")")
            }
        case "doctor":
            guard rest.isEmpty else { throw UserError("doctor takes no arguments.") }
            print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            print("Apple SpeechTranscriber: \(SpeechTranscriber.isAvailable ? "available" : "unavailable")")
            print("Apple Intelligence language model: \(LocalIntelligence.status)")
            for name in ["ffmpeg", "ffprobe"] {
                print("\(name): \((try? Subprocess.executable(name).path) ?? "not found (install FFmpeg)")")
            }
            let locales = await SpeechTranscriber.installedLocales.map(\.identifier).sorted()
            print("Installed speech languages: \(locales.isEmpty ? "none; downloaded on first transcription" : locales.joined(separator: ", "))")
        default: throw UserError("Unknown command '\(command)'. Run audiochapters --help.")
        }
    }

    static let help = """
    AudioChapters — local Apple speech transcription and MP3 episode export

    USAGE
      audiochapters rundown INPUT [--out-dir DIR] [--language en-US] [--no-download] [--interactive]
      audiochapters select RUNDOWN [--request "1, 3b"] [--preview] [--out-dir DIR] [--source AUDIO]
      audiochapters transcribe INPUT [--language en-US] [--out-dir DIR] [--no-download]
      audiochapters clip INPUT --start TIME --end TIME --output FILE.mp3
                         [--title TITLE] [--album ALBUM] [--artist ARTIST]
      audiochapters export INPUT --plan sections.json [--out-dir DIR]
      audiochapters context transcript.json --output summary-context.md
                            [--detail overview|standard|detailed] [--start TIME --end TIME]
      audiochapters languages
      audiochapters doctor

    TIME accepts seconds, MM:SS, or HH:MM:SS, with optional fractional seconds.
    All times refer to the original recording. Existing outputs are never replaced.

    EXAMPLES
      audiochapters transcribe interview.mp3
      audiochapters clip interview.mp3 --start 42:15 --end 49:30 \\
        --title "Why the first approach failed" --output first-approach.mp3
      audiochapters export interview.mp3 --plan selected.json --out-dir episodes
      audiochapters context interview.transcript/transcript.json --detail detailed \\
        --start 42:15 --end 49:30 --output deep-dive.md

    TRANSCRIPT OUTPUTS
      transcript.txt, transcript.json (segment/word timings), transcript.srt,
      and listening-guide-prompt.md. Default directory: INPUT.transcript.

    CLIP PLAN
      {"album":"My listening list","clips":[
        {"title":"A useful section","start":"00:42:15","end":"00:49:30"}
      ]}

    Transcription uses Apple's on-device model; first use may download language assets.
    context prepares a prompt plus timed transcript for an assistant; it does not call a model.
    rundown accepts audio, a transcript folder, or transcript.json; it reuses existing transcripts.
    Rundowns and natural-language selection use Apple Intelligence locally. IDs work without it.
    Default rundown: INPUT.transcript/rundown/{rundown.md,rundown.json}.
    Default selections: INPUT.clips/selection-001/ (then 002, 003…).
    Audio decoding and MP3 export require FFmpeg. Upload exported MP3s to Overcast manually.
    """
}
