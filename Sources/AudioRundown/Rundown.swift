import Foundation

struct Rundown: Codable {
    var schemaVersion = 1
    let source: String
    let transcriptFingerprint: String
    let title: String
    let duration: Double
    let createdAt: Date
    var engine = "Apple SystemLanguageModel (on device)"
    var origin: String? = nil
    let segments: [Segment]

    struct Segment: Codable {
        let id: String
        let title: String
        let start: Double
        let end: Double
        let summary: String
        let clips: [Clip]
    }
    struct Clip: Codable {
        let id: String
        let title: String
        let start: Double
        let end: Double
        let summary: String
    }

    var items: [Clip] {
        segments.flatMap { segment in
            [Clip(id: segment.id, title: segment.title, start: segment.start, end: segment.end, summary: segment.summary)] + segment.clips
        }
    }

    var markdown: String {
        let provenance = origin == "openai" ? "Generated with \(Self.prose(engine)) via API" : schemaVersion == 2 ? "Imported from \(Self.prose(engine))" : "Generated locally with \(Self.prose(engine))"
        let note = origin == "openai" ? "Draft listening guide; boundaries use original transcript entries. Check claims and listening boundaries against the audio." : schemaVersion == 2 ? "Imported timestamps are preserved; gaps between selections are allowed." : "Experimental draft: check names, claims, and clip boundaries against the audio. Topic grouping can fall back to approximate vocabulary-based boundaries."
        var lines = ["# \(Self.prose(title))", "", "\(Self.durationLabel(duration)) · \(provenance)", "", note, "",
                     "Times refer to the original recording. Select a whole segment (1) or an individual clip (1a).", ""]
        for segment in segments {
            lines += ["## \(segment.id). \(Self.prose(segment.title))",
                      "\(Self.displayTime(segment.start))–\(Self.displayTime(segment.end)) · \(Self.durationLabel(segment.end - segment.start))", "",
                      "### Summary", "", Self.prose(segment.summary), "", "### Detailed rundown", ""]
            for clip in segment.clips {
                lines += ["#### \(clip.id). \(Self.prose(clip.title))",
                          "\(Self.displayTime(clip.start))–\(Self.displayTime(clip.end))", "", Self.prose(clip.summary), ""]
            }
        }
        return lines.joined(separator: "\n")
    }

    static func prose(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func displayTime(_ seconds: Double) -> String {
        String(Timecode.format(seconds).split(separator: ".")[0])
    }
    static func durationLabel(_ seconds: Double) -> String {
        let value = Int(seconds.rounded())
        return value >= 3600 ? "\(value / 3600)h \(value / 60 % 60)m" : "\(value / 60)m \(value % 60)s"
    }
    static func letters(_ index: Int) -> String {
        var n = index + 1
        var result = ""
        while n > 0 {
            n -= 1
            result = String(UnicodeScalar(97 + n % 26)!) + result
            n /= 26
        }
        return result
    }

    func validate() throws {
        guard [1, 2].contains(schemaVersion), duration.isFinite, duration > 0, duration < 1_000_000_000,
              !segments.isEmpty, !source.isEmpty else { throw UserError("Invalid or unsupported rundown.") }
        var expectedStart = 0.0
        for (index, segment) in segments.enumerated() {
            guard segment.id == String(index + 1), segment.start >= expectedStart,
                  (schemaVersion == 2 || abs(segment.start - expectedStart) < 0.002),
                  !segment.title.isEmpty, !segment.summary.isEmpty, !segment.clips.isEmpty else {
                throw UserError("Invalid segment IDs, text, or coverage in rundown.")
            }
            _ = try AudioRange(start: segment.start, end: segment.end, sourceDuration: duration)
            var clipStart = segment.start
            for (clipIndex, clip) in segment.clips.enumerated() {
                guard clip.id == segment.id + Self.letters(clipIndex), clip.start >= clipStart,
                      (schemaVersion == 2 || abs(clip.start - clipStart) < 0.002),
                      !clip.title.isEmpty, !clip.summary.isEmpty else {
                    throw UserError("Invalid clip IDs, text, or coverage in rundown.")
                }
                _ = try AudioRange(start: clip.start, end: clip.end, sourceDuration: segment.end)
                clipStart = clip.end
            }
            guard schemaVersion == 2 || abs(clipStart - segment.end) < 0.002 else { throw UserError("Clips do not cover their segment.") }
            expectedStart = segment.end
        }
        guard schemaVersion == 2 || abs(expectedStart - duration) < 0.002 else { throw UserError("Rundown does not cover the whole recording.") }
    }

    static func load(_ input: URL) throws -> Rundown {
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: input.path, isDirectory: &directory)
        let file = exists && directory.boolValue ? input.appendingPathComponent("rundown.json") : input
        try requireFile(file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rundown = try decoder.decode(Self.self, from: Data(contentsOf: file))
        try rundown.validate()
        return rundown
    }
}

extension Transcript {
    static func load(_ file: URL) throws -> Transcript {
        try requireFile(file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(Self.self, from: Data(contentsOf: file))
        guard transcript.schemaVersion == 1, transcript.duration.isFinite, transcript.duration > 0,
              transcript.duration < 1_000_000_000, !transcript.segments.isEmpty else {
            throw UserError("Invalid or unsupported transcript.")
        }
        var previous = -1.0
        for segment in transcript.segments {
            guard segment.start.isFinite, segment.end.isFinite, segment.start >= 0,
                  segment.start >= previous, segment.end > segment.start,
                  segment.end <= transcript.duration + 0.1 else { throw UserError("Invalid transcript timing.") }
            previous = segment.start
        }
        return transcript
    }
}
