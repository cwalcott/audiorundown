import Foundation

struct ClipPlan: Codable {
    var album: String?
    var artist: String?
    var clips: [Clip]

    struct Clip: Codable {
        let title: String
        let start: String
        let end: String
    }
}

struct ExportReceipt: Codable {
    let source: String
    let createdAt: Date
    let album: String
    let artist: String
    let clips: [Entry]
    struct Entry: Codable {
        let file: String
        let title: String
        let start: Double
        let end: Double
    }
}

enum Clips {
    /// MP3 container duration may be an estimate. Decode once for an exact timeline.
    static func sourceDuration(of source: URL) throws -> Double {
        try requireFile(source)
        let output = try Subprocess.run(Subprocess.executable("ffmpeg"), [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-nostats", "-i", source.path,
            "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000",
            "-progress", "pipe:1", "-f", "null", "-"
        ])
        let times = String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line -> Double? in
            guard line.hasPrefix("out_time_us="), let micros = Double(line.dropFirst("out_time_us=".count)) else { return nil }
            return micros / 1_000_000
        }
        guard let seconds = times.last, seconds.isFinite, seconds > 0, seconds < 1_000_000_000 else {
            throw UserError("Could not decode the source audio duration.")
        }
        return seconds
    }

    static func duration(of source: URL) throws -> Double {
        try requireFile(source)
        let probe = try Subprocess.executable("ffprobe")
        let output = try Subprocess.run(probe, ["-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_type:format=duration", "-of", "json", source.path])
        struct Probe: Decodable {
            struct Stream: Decodable { let codec_type: String }
            struct Format: Decodable { let duration: String? }
            let streams: [Stream]
            let format: Format
        }
        let value = try JSONDecoder().decode(Probe.self, from: output)
        guard value.streams.contains(where: { $0.codec_type == "audio" }),
              let raw = value.format.duration, let seconds = Double(raw),
              seconds.isFinite, seconds > 0, seconds < 1_000_000_000 else {
            throw UserError("Could not determine an audio duration for \(source.path).")
        }
        return seconds
    }

    static func encode(source: URL, output: URL, range: AudioRange, title: String, album: String, artist: String, track: String) throws {
        let ffmpeg = try Subprocess.executable("ffmpeg")
        // Seek AFTER opening input: decode from the start so missing/unreliable MP3
        // seek headers cannot shift cuts away from the transcript's sample timeline.
        _ = try Subprocess.run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-i", source.path, "-ss", String(range.start), "-t", String(range.duration),
            "-map", "0:a:0", "-vn", "-map_metadata", "-1", "-map_chapters", "-1",
            "-c:a", "libmp3lame", "-b:a", "128k", "-ar", "44100", "-id3v2_version", "3",
            "-metadata", "title=\(title)", "-metadata", "album=\(album)",
            "-metadata", "artist=\(artist)", "-metadata", "track=\(track)",
            "-metadata", "genre=Podcast",
            "-metadata", "comment=Excerpt from \(source.lastPathComponent), \(Timecode.format(range.start)) to \(Timecode.format(range.end))",
            output.path
        ])
        let actual = try duration(of: output)
        guard abs(actual - range.duration) < 0.5 else {
            throw UserError("Exported clip has an unexpected duration (wanted \(range.duration)s, got \(actual)s).")
        }
    }

    static func single(source: URL, output: URL, start: String, end: String, title: String?, album: String?, artist: String?) throws {
        guard output.pathExtension.lowercased() == "mp3" else { throw UserError("The output must end in .mp3.") }
        try requireNew(output)
        let startSeconds = try Timecode.parse(start)
        let endSeconds = try Timecode.parse(end)
        log("Checking decoded source duration…")
        let range = try AudioRange(start: startSeconds, end: endSeconds, sourceDuration: sourceDuration(of: source))
        let fm = FileManager.default
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = output.deletingLastPathComponent().appendingPathComponent(".audiochapters-\(UUID().uuidString).mp3")
        defer { try? fm.removeItem(at: staging) }
        try encode(source: source, output: staging, range: range,
                   title: title ?? output.deletingPathExtension().lastPathComponent,
                   album: album ?? source.deletingPathExtension().lastPathComponent,
                   artist: artist ?? "AudioChapters", track: "1/1")
        try requireNew(output)
        try fm.moveItem(at: staging, to: output)
        log("Saved \(output.path) (\(Timecode.format(range.duration)))")
    }

    static func export(source: URL, planURL: URL, destination: URL) async throws {
        try requireNew(destination)
        try requireFile(planURL)
        let plan: ClipPlan
        do { plan = try JSONDecoder().decode(ClipPlan.self, from: Data(contentsOf: planURL)) }
        catch { throw UserError("Invalid clip plan: \(error.localizedDescription). See examples/sections.json for the format.") }
        guard !plan.clips.isEmpty else { throw UserError("The clip plan is empty.") }
        log("Checking decoded source duration…")
        let sourceDuration = try sourceDuration(of: source)
        // Validate the entire selection before creating any output.
        let ranges = try plan.clips.map { clip in
            guard !clip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UserError("Every clip needs a nonempty title.")
            }
            return try AudioRange(start: Timecode.parse(clip.start), end: Timecode.parse(clip.end), sourceDuration: sourceDuration)
        }
        let album = plan.album ?? source.deletingPathExtension().lastPathComponent
        let artist = plan.artist ?? "AudioChapters"
        try await withNewDirectory(at: destination) { staging in
            var entries: [ExportReceipt.Entry] = []
            for (index, clip) in plan.clips.enumerated() {
                let filename = String(format: "%03d", index + 1) + "-" + safeFilename(clip.title) + ".mp3"
                log("Exporting \(index + 1)/\(plan.clips.count): \(clip.title)")
                try encode(source: source, output: staging.appendingPathComponent(filename), range: ranges[index],
                           title: clip.title, album: album, artist: artist, track: "\(index + 1)/\(plan.clips.count)")
                entries.append(.init(file: filename, title: clip.title, start: ranges[index].start, end: ranges[index].end))
            }
            let receipt = ExportReceipt(source: source.path, createdAt: Date(), album: album, artist: artist, clips: entries)
            try jsonData(receipt).write(to: staging.appendingPathComponent("export.json"))
            try jsonData(plan).write(to: staging.appendingPathComponent("sections.json"))
        }
        log("Saved \(plan.clips.count) MP3 episodes to \(destination.path)")
    }
}
