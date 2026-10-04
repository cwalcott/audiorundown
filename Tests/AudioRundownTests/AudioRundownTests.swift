import Foundation
import Testing
@testable import AudioRundown

@Test func timeParsingAndRounding() throws {
    #expect(try Timecode.parse("90.25") == 90.25)
    #expect(try Timecode.parse("42:15.5") == 2535.5)
    #expect(try Timecode.parse("01:02:03") == 3723)
    #expect(try Timecode.parse("120:00") == 7200)
    for invalid in ["", "-1", "nan", "inf", "1:60", "1:2:60", "1::2", "1.5:02", "1:02:03:04", "1000000000"] {
        #expect(throws: UserError.self) { try Timecode.parse(invalid) }
    }
    #expect(Timecode.format(3599.9996) == "01:00:00.000")
    #expect(Timecode.format(3.125, srt: true) == "00:00:03,125")
}

@Test func rangeValidation() throws {
    #expect(try AudioRange(start: 2, end: 5, sourceDuration: 5).duration == 3)
    for (start, end) in [(2.0, 2.0), (3, 2), (-1, 2), (0, 6), (Double.nan, 3), (0, Double.infinity)] {
        #expect(throws: UserError.self) { try AudioRange(start: start, end: end, sourceDuration: 5) }
    }
}

@Test func argumentErrors() throws {
    #expect(throws: UserError.self) { try Arguments(["--start"], values: ["--start"]) }
    #expect(throws: UserError.self) { try Arguments(["--wat"], values: []) }
    #expect(throws: UserError.self) { try Arguments(["--start", "1", "--start", "2"], values: ["--start"]) }
    let args = try Arguments(["--", "--recording.mp3"], values: [])
    #expect(args.positional == ["--recording.mp3"])
}

@Test func filenamesCannotEscapeDestination() {
    #expect(safeFilename("../../A / title: test") == "A-title-test")
    #expect(safeFilename("🎧") == "clip")
    #expect(safeFilename(String(repeating: "a", count: 100)).count == 80)
}

@Test func summarySelectionKeepsOriginalTimes() throws {
    let transcript = Transcript(source: "/audio.mp3", language: "en-US", duration: 100, createdAt: Date(), segments: [
        .init(start: 0, end: 10, text: "Beginning", words: []),
        .init(start: 30, end: 50, text: "Selected discussion", words: []),
        .init(start: 60, end: 80, text: "Later", words: [])
    ])
    let range = try AudioRange(start: 35, end: 60, sourceDuration: 100)
    let context = try SummaryContext.render(transcript: transcript, detail: .detailed, range: range)
    #expect(context.contains("Selected discussion"))
    #expect(context.contains("00:00:30.000 – 00:00:50.000"))
    #expect(!context.contains("Beginning"))
    #expect(!context.contains("Later"))
    #expect(context.contains("Detail: detailed"))
    #expect(transcript.subtitles.contains("00:00:30,000 --> 00:00:50,000"))
}

@Test func directoryFailureDoesNotPublishPartialResults() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let output = root.appendingPathComponent("clips")
    do {
        try await withNewDirectory(at: output) { stage in
            try writeText("partial", to: stage.appendingPathComponent("partial.txt"))
            throw UserError("simulated failure")
        }
        Issue.record("Expected failure")
    } catch {}
    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}
