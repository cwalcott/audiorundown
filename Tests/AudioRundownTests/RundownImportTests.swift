import Foundation
import Testing
@testable import AudioRundown

private let importedMarkdown = """
# Imported episode
Original introductory note.

## 1. First segment — 00:00:01–00:01:00
### Summary
First summary.
### Detailed rundown
**1a. First story — 00:00:02–00:00:20**
First story summary.
**1b. Second story — 00:00:23–00:00:59**
Second story summary.

## 2. Second segment — 00:01:02–00:01:39
### Summary
Second summary.
### Detailed rundown
**2a. Closing — 00:01:03–00:01:38**
Closing summary.
"""

private func imported(_ markdown: String = importedMarkdown) throws -> Rundown {
    let transcript = Transcript(source: "/audio.mp3", language: "en-US", duration: 100, createdAt: Date(), segments: [])
    return try RundownImport.parse(markdown, transcript: transcript, fingerprint: "fixture", engine: "Sol test")
}

@Test func importedGapsAndSelectionBoundariesSurviveJSONRoundTrip() throws {
    let rundown = try imported()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let saved = try decoder.decode(Rundown.self, from: jsonData(rundown))
    try saved.validate()
    #expect(saved.schemaVersion == 2)
    #expect(saved.engine == "Sol test")
    #expect(saved.segments[0].summary == "First summary.")
    #expect(saved.segments[0].clips[1].summary == "Second story summary.")
    let plan = try Selection.plan(.init(ids: ["1b", "2"], beforeSeconds: 0, afterSeconds: 0, clarification: nil), rundown: saved)
    #expect(plan.clips.map(\.start) == ["00:00:23.000", "00:01:02.000"])
    #expect(plan.clips.map(\.end) == ["00:00:59.000", "00:01:39.000"])
    #expect(saved.markdown.contains("Imported from Sol test"))
    #expect(!saved.markdown.contains("Generated locally"))
}

@Test func importRejectsMalformedOrUnsafeSelections() {
    let replacements = [
        ("00:01:02–00:01:39", "00:00:58–00:01:39"), // overlapping parents
        ("00:00:23–00:00:59", "00:00:19–00:00:59"), // overlapping clips
        ("00:00:23–00:00:59", "00:00:23–00:01:01"), // outside parent
        ("00:00:02–00:00:20", "00:00:00–00:00:20"), // before parent
        ("00:01:02–00:01:39", "00:01:02–00:01:41"), // outside recording
        ("00:00:02–00:00:20", "00:00:20–00:00:20"), // empty range
        ("**1b.", "**1c."), // missing stable ID
        ("## 2.", "## 3."),
        ("First story summary.", ""),
        ("### Summary", "### Overview"),
        ("00:00:02–00:00:20", "not a timestamp"),
        ("**1a.", "#### 1a.") // unsupported format must not silently drop clips
    ]
    for (old, new) in replacements {
        #expect(throws: UserError.self) { try imported(importedMarkdown.replacingOccurrences(of: old, with: new)) }
    }
}

@Test func importedGapsDoNotWeakenGeneratedRundownValidation() throws {
    var rundown = try imported()
    rundown.schemaVersion = 1
    #expect(throws: UserError.self) { try rundown.validate() }
    rundown.schemaVersion = 99
    #expect(throws: UserError.self) { try rundown.validate() }
}
