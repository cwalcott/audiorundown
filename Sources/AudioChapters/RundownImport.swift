import Foundation

/// Imports the documented listening-guide Markdown format without asking a model
/// to reinterpret either the prose or the original recording timestamps.
enum RundownImport {
    private struct Entry {
        let id: String
        let title: String
        let start: Double
        let end: Double
        var summary = ""
        var clips: [Rundown.Clip] = []
    }

    static func parse(_ markdown: String, transcript: Transcript, fingerprint: String,
                      engine: String = "Imported Markdown") throws -> Rundown {
        let heading = try NSRegularExpression(pattern: #"^(?:## |\*\*)([1-9][0-9]*[a-z]*)\. (.+?) [—–-] (\d{2,}:\d{2}:\d{2}(?:\.\d+)?)\s*[–—-]\s*(\d{2,}:\d{2}:\d{2}(?:\.\d+)?)(?:\*\*)?$"#)
        var title = ""
        var segments: [Rundown.Segment] = []
        var segment: Entry?
        var clip: Entry?
        var inSummary = false
        var inDetails = false

        func finishClip() {
            if let value = clip {
                segment?.clips.append(.init(id: value.id, title: value.title, start: value.start,
                                            end: value.end, summary: value.summary.trimmingCharacters(in: .whitespacesAndNewlines)))
                clip = nil
            }
        }
        func finishSegment() {
            finishClip()
            if let value = segment {
                segments.append(.init(id: value.id, title: value.title, start: value.start,
                                      end: value.end, summary: value.summary.trimmingCharacters(in: .whitespacesAndNewlines), clips: value.clips))
                segment = nil
            }
        }
        for (index, raw) in markdown.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            func invalid(_ reason: String) -> UserError {
                UserError("Cannot import Markdown at line \(index + 1): \(reason)")
            }
            if line.hasPrefix("# ") {
                guard title.isEmpty, segment == nil else { throw invalid("unexpected document title.") }
                title = String(line.dropFirst(2))
                continue
            }
            if line.hasPrefix("## ") || line.hasPrefix("**") {
                let ns = line as NSString
                guard let match = heading.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                    throw invalid("expected a numbered heading with an original HH:MM:SS–HH:MM:SS range. See README import format.")
                }
                let value = Entry(id: ns.substring(with: match.range(at: 1)), title: ns.substring(with: match.range(at: 2)),
                                  start: try Timecode.parse(ns.substring(with: match.range(at: 3))),
                                  end: try Timecode.parse(ns.substring(with: match.range(at: 4))))
                if line.hasPrefix("## ") {
                    finishSegment()
                    segment = value
                    inSummary = false
                    inDetails = false
                } else {
                    guard segment != nil, inDetails, line.hasSuffix("**") else { throw invalid("clip must follow its segment's Detailed rundown heading.") }
                    finishClip()
                    clip = value
                }
                continue
            }
            if line == "### Summary" {
                guard segment != nil, !inSummary, !inDetails else { throw invalid("unexpected Summary heading.") }
                inSummary = true
                continue
            }
            if line == "### Detailed rundown" {
                guard segment != nil, inSummary, !inDetails else { throw invalid("Detailed rundown must follow Summary.") }
                inSummary = false
                inDetails = true
                continue
            }
            if line.hasPrefix("#") || line.hasPrefix("```") { throw invalid("unsupported heading or code fence.") }
            if clip != nil { clip?.summary += line + "\n" }
            else if inSummary { segment?.summary += line + "\n" }
            else if segment != nil { throw invalid("unexpected text outside a summary or clip.") }
            // Introductory prose is retained in original.md, not the selection catalog.
        }
        finishSegment()
        guard !title.isEmpty, !engine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UserError("Imported rundown needs a # title and a nonempty engine label.")
        }
        var result = Rundown(source: transcript.source, transcriptFingerprint: fingerprint, title: title,
                             duration: transcript.duration, createdAt: Date(), engine: engine, segments: segments)
        // Imported selections may omit silence and transitions. Never stretch their bounds.
        result.schemaVersion = 2
        try result.validate()
        return result
    }

    static func run(input: URL, transcriptInput: URL, destination: URL?, engine: String) async throws -> URL {
        try requireFile(input)
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: transcriptInput.path, isDirectory: &directory)
        let transcriptFile = exists && directory.boolValue ? transcriptInput.appendingPathComponent("transcript.json") : transcriptInput
        let transcript = try Transcript.load(transcriptFile)
        let markdown = try String(contentsOf: input, encoding: .utf8)
        let fingerprint = LocalIntelligence.fingerprint(String(decoding: try Data(contentsOf: transcriptFile), as: UTF8.self))
        let rundown = try parse(markdown, transcript: transcript, fingerprint: fingerprint, engine: engine)
        let output = destination ?? input.deletingPathExtension().appendingPathExtension("rundown")
        try await withNewDirectory(at: output) { staging in
            try jsonData(rundown).write(to: staging.appendingPathComponent("rundown.json"))
            try writeText(rundown.markdown, to: staging.appendingPathComponent("rundown.md"))
            try writeText(markdown, to: staging.appendingPathComponent("original.md"))
        }
        print("Imported \(rundown.segments.count) segments and \(rundown.segments.reduce(0) { $0 + $1.clips.count }) clips: \(output.path)")
        return output
    }
}
