import Foundation
import Testing
@testable import AudioChapters

private func fixture() -> Rundown {
    Rundown(source: "/audio.mp3", transcriptFingerprint: "test", title: "Episode", duration: 100, createdAt: Date(), segments: [
        .init(id: "1", title: "First", start: 0, end: 60, summary: "First summary", clips: [
            .init(id: "1a", title: "Opening", start: 0, end: 30, summary: "Opening story"),
            .init(id: "1b", title: "Follow-up", start: 30, end: 60, summary: "Next story")]),
        .init(id: "2", title: "Second", start: 60, end: 100, summary: "Second summary", clips: [
            .init(id: "2a", title: "Ending", start: 60, end: 100, summary: "Closing story")])])
}

@Test func rejectsInventedOrUnorderedModelBoundaries() throws {
    try RundownGenerator.validateStarts([5, 8, 10], first: 5, upper: 11)
    for starts in [[], [6], [5, 5], [5, 4], [5, 11], [5, 9, 8]] {
        #expect(throws: UserError.self) { try RundownGenerator.validateStarts(starts, first: 5, upper: 11) }
    }
}

@Test func rundownRequiresFullCoverageAndStableIDs() throws {
    let original = fixture()
    try original.validate()
    let gap = Rundown(source: original.source, transcriptFingerprint: "test", title: "Episode", duration: 101, createdAt: Date(), segments: original.segments)
    #expect(throws: UserError.self) { try gap.validate() }
    #expect(original.markdown.contains("### Summary\n"))
    #expect(original.markdown.contains("### Detailed rundown\n"))
    #expect(original.markdown.contains("#### 1b. Follow-up"))
    #expect(Rundown.letters(26) == "aa")
}

@Test func selectionDeduplicatesAndClampsExplicitPadding() throws {
    let plan = try Selection.plan(.init(ids: ["2a", "1b", "1", "1"], beforeSeconds: 10, afterSeconds: 10, clarification: nil), rundown: fixture())
    #expect(plan.clips.count == 2)
    #expect(plan.clips[0].title == "1. First")
    #expect(plan.clips[0].start == "00:00:00.000")
    #expect(plan.clips[0].end == "00:01:10.000")
    #expect(plan.clips[1].end == "00:01:40.000")
}

@Test func unsafeOrAmbiguousSelectionsCannotProducePlan() {
    for response in [
        SelectionResponse(ids: ["9z"], beforeSeconds: 0, afterSeconds: 0, clarification: nil),
        .init(ids: ["1"], beforeSeconds: -1, afterSeconds: 0, clarification: nil),
        .init(ids: ["1"], beforeSeconds: .infinity, afterSeconds: 0, clarification: nil),
        .init(ids: [], beforeSeconds: 0, afterSeconds: 0, clarification: nil),
        .init(ids: ["1"], beforeSeconds: 0, afterSeconds: 0, clarification: "Which story?")
    ] {
        #expect(throws: UserError.self) { try Selection.plan(response, rundown: fixture()) }
    }
    #expect(Selection.exactIDs("1, 2A") == ["1", "2a"])
    #expect(Selection.exactIDs("export 1 with 10 seconds before") == nil)
}

@Test func fractionalSourceEndNeverRoundsPastAudio() throws {
    let clip = Rundown.Clip(id: "1a", title: "End", start: 0, end: 10.9998, summary: "Summary")
    let rundown = Rundown(source: "/audio.mp3", transcriptFingerprint: "test", title: "Episode", duration: 10.9998, createdAt: Date(), segments: [
        .init(id: "1", title: "Segment", start: 0, end: 10.9998, summary: "Summary", clips: [clip])])
    let plan = try Selection.plan(.init(ids: ["1"], beforeSeconds: 0, afterSeconds: 0, clarification: nil), rundown: rundown)
    #expect(try Timecode.parse(plan.clips[0].end) <= rundown.duration)
}

@Test func groupPlansCoverEveryBeatExactlyOnce() throws {
    try RundownGenerator.validateGroups([
        .init(title: "Opening", startBeat: 0, endBeat: 2),
        .init(title: "Ending", startBeat: 3, endBeat: 5)
    ], count: 6)
    for groups in [
        [DraftGroup(title: "Missing end", startBeat: 0, endBeat: 3)],
        [.init(title: "Opening", startBeat: 0, endBeat: 2), .init(title: "Gap", startBeat: 4, endBeat: 5)],
        [.init(title: "Opening", startBeat: 0, endBeat: 3), .init(title: "Overlap", startBeat: 3, endBeat: 5)],
        [.init(title: "Outside", startBeat: 0, endBeat: 6)]
    ] {
        #expect(throws: UserError.self) { try RundownGenerator.validateGroups(groups, count: 6) }
    }
}

@Test func fallbackGroupingKeepsCompleteOrderedCoverage() {
    let notes = ["guitar music strings", "guitar music practice", "traffic road driving", "traffic road delays", "film actor movie", "film actor role"]
    let ranges = TopicGrouping.boundaries(notes, desiredCount: 3)
    #expect(ranges.count == 3)
    #expect(ranges.flatMap(Array.init) == Array(notes.indices))
    #expect(TopicGrouping.boundaries([], desiredCount: 5).isEmpty)
    #expect(TopicGrouping.boundaries(["one"], desiredCount: 5) == [0..<1])
}

@Test func ambiguousModelIntentCannotExportEvenWithKnownIDs() {
    let intent = ClipIntent(hasClearMatch: false, ids: ["1"], beforeSeconds: 0, afterSeconds: 0)
    #expect(throws: UserError.self) { try Selection.plan(intent.selection, rundown: fixture()) }
}
