import Foundation
import Testing
@testable import AudioChapters

@Test func preferencesRoundTripAndRejectInvalidCost() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("config.json")
    #expect(try Settings.load(from: path).model == "apple")
    var settings = Settings(model: OpenAIClient.selector, reasoning: "medium", maxCost: 1, editor: "Visual Studio Code")
    try settings.save(to: path)
    #expect(try Settings.load(from: path).model == OpenAIClient.selector)
    for cost in [0, -1, Double.infinity, Double.nan] {
        settings.maxCost = cost
        #expect(throws: UserError.self) { try settings.save(to: path) }
    }
    #expect(try Settings.load(from: path).maxCost == 1)
}

@Test func originalAudioFindsRememberedRundownAndRejectsWrongSource() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let audio = root.appendingPathComponent("episode.mp3")
    try Data().write(to: audio)
    let transcript = Workflow.transcriptDirectory(for: audio)
    try fm.createDirectory(at: transcript, withIntermediateDirectories: true)
    try Data().write(to: transcript.appendingPathComponent("transcript.json"))
    func save(_ name: String, source: URL = audio) throws -> URL {
        let output = transcript.appendingPathComponent(name)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let rundown = Rundown(source: source.path, transcriptFingerprint: "fixture", title: "Episode", duration: 10, createdAt: Date(), segments: [
            .init(id: "1", title: "Topic", start: 0, end: 10, summary: "Topic summary", clips: [
                .init(id: "1a", title: "Story", start: 0, end: 10, summary: "Story summary")])])
        try jsonData(rundown).write(to: output.appendingPathComponent("rundown.json"))
        return output
    }
    #expect(throws: UserError.self) { try Workflow.resolve(audio) }
    let local = try save("rundown")
    #expect(try Workflow.resolve(audio).path == local.path)
    let api = try save("rundown-openai")
    #expect(throws: UserError.self) { try Workflow.resolve(audio) }
    try Workflow.remember(output: api, transcriptInput: audio)
    #expect(try Workflow.resolve(audio).path == api.path)
    #expect(try Workflow.resolve(transcript).path == api.path)
    #expect(try Workflow.resolve(transcript.appendingPathComponent("transcript.json")).path == api.path)
    #expect(try Workflow.resolve(local).path == local.path)
    let custom = try save("custom-rundown")
    try Workflow.remember(output: custom, transcriptInput: transcript)
    #expect(try Workflow.resolve(audio).path == custom.path)
    let wrong = try save("wrong-source", source: root.appendingPathComponent("another.mp3"))
    try Workflow.remember(output: wrong, transcriptInput: audio)
    #expect(throws: UserError.self) { try Workflow.resolve(audio) }
    try fm.removeItem(at: wrong)
    #expect(throws: (any Error).self) { try Workflow.resolve(audio) }
}

@Test func compactTitlesPreserveWordsAndUnicode() {
    #expect(Clips.shortened("  A short\n title ", limit: 30) == "A short title")
    #expect(Clips.shortened("A rather long description of this discussion", limit: 20) == "A rather long…")
    #expect(Clips.shortened(String(repeating: "🎧", count: 100), limit: 40).count == 40)
    #expect(Workflow.quote("it's $safe") == "'it'\"'\"'s $safe'")
}
