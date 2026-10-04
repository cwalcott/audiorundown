import Foundation
import Testing
@testable import AudioRundown

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

@Test func selectedNamesKeepEpisodeAndCatalogOrderFirst() throws {
    let clip = ClipPlan.Clip(title: "3f. Watch parties and beach day", start: "00:02:00.000", end: "00:05:00.000")
    let names = try Clips.selectedNames(clip: clip, episode: "Studio Notes 2026-06-15")
    #expect(names.file == "Studio Notes 2026-06-15 - 03f - Watch parties and beach day.mp3")
    #expect(names.title == "Studio Notes 2026-06-15 · 3f · Watch parties and beach day")
    let nextDay = try Clips.selectedNames(clip: clip, episode: "Studio Notes 2026-06-16")
    #expect(names.file < nextDay.file)
    var padded = clip
    padded.includeRangeInFilename = true
    #expect(try Clips.selectedNames(clip: padded, episode: "Studio Notes 2026-06-15").file.contains("[00-02-00.000_00-05-00.000]"))
    let olderPlan = try JSONDecoder().decode(ClipPlan.Clip.self, from: Data(#"{"title":"2. First topic","start":"0","end":"1"}"#.utf8))
    #expect(try Clips.selectedNames(clip: olderPlan, episode: "Episode").file == "Episode - 02 - First topic.mp3")
}

@Test func selectedNamesHandleUnsafeAndLongUnicodeTitles() throws {
    let clip = ClipPlan.Clip(title: "12a. " + String(repeating: "音楽", count: 60), start: "0", end: "1")
    let episode = "A longer episode title that retains its original date 2026-06-15"
    let names = try Clips.selectedNames(clip: clip, episode: episode)
    #expect(names.file.hasPrefix(episode + " - 12a - "))
    #expect(names.file.utf8.count <= 240)
    #expect(names.title.hasPrefix(episode + " · 12a · "))
    let unsafe = try Clips.selectedNames(clip: .init(title: "2. ../../Path: escape", start: "0", end: "1"), episode: "../Show/Name")
    #expect(!unsafe.file.contains("/"))
    #expect(!unsafe.file.hasPrefix("."))
    let custom = try Clips.selectedNames(clip: .init(title: "A custom cut", start: "0", end: "1"), episode: "Episode")
    #expect(custom.file.contains("[0_1]"))
}
