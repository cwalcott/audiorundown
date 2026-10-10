import Foundation
import Testing
@testable import AudioRundown

private func rangeFixture() -> Rundown {
    var result = Rundown(source: "/fixture.mp3", transcriptFingerprint: "test", title: "Episode", duration: 100, createdAt: Date(), segments: [
        .init(id: "1", title: "Recording techniques", start: 0, end: 60, summary: "Equipment and technique", clips: [
            .init(id: "1a", title: "Microphones", start: 0, end: 10, summary: "Choosing a microphone."),
            .init(id: "1b", title: "Placement", start: 20, end: 30, summary: "Positioning the microphone."),
            .init(id: "1c", title: "Levels", start: 40, end: 60, summary: "Setting levels.")]),
        .init(id: "2", title: "Editing", start: 70, end: 100, summary: "Editing tips", clips: [
            .init(id: "2a", title: "Cuts", start: 70, end: 80, summary: "Making cuts."),
            .init(id: "2b", title: "Finishing", start: 90, end: 100, summary: "Finishing the edit.")])])
    result.schemaVersion = 2
    return result
}

@Test func exactRangesExportOneContinuousSpanWithoutModel() async throws {
    let rundown = rangeFixture()
    try rundown.validate()
    let response = try await Selection.resolve("1A – 1B", rundown: rundown, modelName: "missing-model")
    #expect(response.ids == ["1a-1b"])
    let plan = try Selection.plan(response, rundown: rundown)
    #expect(plan.clips.count == 1)
    #expect(plan.clips[0].start == "00:00:00.000")
    #expect(plan.clips[0].end == "00:00:30.000")
    #expect(plan.clips[0].title == "1a-1b. Recording techniques")
    #expect(plan.clips[0].summary?.contains("Choosing a microphone.") == true)
    #expect(plan.clips[0].summary?.contains("Positioning the microphone.") == true)
    #expect(plan.clips[0].summary?.contains("Setting levels.") == false)
    let names = try Clips.selectedNames(clip: plan.clips[0], episode: "Studio Notes 2026-10-10")
    #expect(names.file == "Studio Notes 2026-10-10 - 01a-01b - Recording techniques.mp3")
    #expect(names.title == "Studio Notes 2026-10-10 · 1a-1b · Recording techniques")
}

@Test func rangesMixWithIDsAndDeduplicateContainedCuts() async throws {
    let response = try await Selection.resolve("2b, 1a-1b, 1b, 1a-1b", rundown: rangeFixture())
    let plan = try Selection.plan(response, rundown: rangeFixture())
    #expect(plan.clips.count == 2)
    #expect(plan.clips[0].title.hasPrefix("1a-1b."))
    #expect(plan.clips[1].title.hasPrefix("2b."))
    let parent = try await Selection.resolve("1a-1c, 1", rundown: rangeFixture())
    #expect(try Selection.plan(parent, rundown: rangeFixture()).clips.map(\.title) == ["1. Recording techniques"])
    let separate = try await Selection.resolve("1a, 1b", rundown: rangeFixture())
    #expect(try Selection.plan(separate, rundown: rangeFixture()).clips.count == 2)
}

@Test func rangesCrossSegmentsAndApplyPaddingAtOuterEdges() throws {
    let plan = try Selection.plan(.init(ids: ["1c-2a"], beforeSeconds: 5, afterSeconds: 3, clarification: nil), rundown: rangeFixture())
    #expect(plan.clips.count == 1)
    #expect(plan.clips[0].title == "1c-2a. Recording techniques / Editing")
    #expect(plan.clips[0].start == "00:00:35.000")
    #expect(plan.clips[0].end == "00:01:23.000")
    #expect(plan.clips[0].includeRangeInFilename == true)
    let whole = try Selection.plan(.init(ids: ["1-2"], beforeSeconds: 0, afterSeconds: 0, clarification: nil), rundown: rangeFixture())
    #expect(whole.clips.count == 1)
    #expect(whole.clips[0].end == "00:01:40.000")
    let same = try Selection.selectedItem("1b-1b", rundown: rangeFixture())
    #expect(same.id == "1b")
}

@Test func invalidOrPartiallyOverlappingRangesCannotExport() async throws {
    for request in ["1b-1a", "1a-9z", "1-1b", "1a-2", "1a--1b", "1a-", "1a-1b-1c"] {
        await #expect(throws: UserError.self) {
            _ = try await Selection.resolve(request, rundown: rangeFixture(), modelName: "missing-model")
        }
    }
    #expect(throws: UserError.self) {
        try Selection.plan(.init(ids: ["1a-1b", "1b-1c"], beforeSeconds: 0, afterSeconds: 0, clarification: nil), rundown: rangeFixture())
    }
}

@Test func rangeOrderFollowsCatalogThroughMultipleLetterIDs() throws {
    let clips: [Rundown.Clip] = (0..<28).map { index in
        .init(id: "1" + Rundown.letters(index), title: "Topic \(index)", start: Double(index), end: Double(index + 1), summary: "Summary \(index)")
    }
    let rundown = Rundown(source: "/fixture.mp3", transcriptFingerprint: "test", title: "Episode", duration: 28, createdAt: Date(), segments: [
        .init(id: "1", title: "Topics", start: 0, end: 28, summary: "All topics", clips: clips)])
    let item = try Selection.selectedItem("1z-1ab", rundown: rundown)
    #expect(item.start == 25)
    #expect(item.end == 28)
    #expect(item.summary.contains("1aa. Topic 26"))
}
