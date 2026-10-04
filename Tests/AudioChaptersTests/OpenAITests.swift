import Foundation
import Testing
@testable import AudioChapters

private func apiTranscript() -> Transcript {
    .init(source: "/fixture.mp3", language: "en-US", duration: 30, createdAt: Date(), segments: [
        .init(start: 1.25, end: 5.5, text: "Opening", words: []),
        .init(start: 6, end: 15.25, text: "Second story", words: []),
        .init(start: 17.75, end: 29, text: "Final interview", words: [])])
}
private func apiDraft(clips: [EpisodeDraft.Clip]? = nil, end: Int = 2) -> EpisodeDraft {
    .init(title: "Fixture", segments: [.init(title: "Conversation", startEntry: 0, endEntry: end, summary: "A conversation.", clips: clips ?? [
        .init(title: "Opening", startEntry: 0, endEntry: 0, summary: "Opening story."),
        .init(title: "Interview", startEntry: 1, endEntry: 2, summary: "Second story and final interview.")])])
}

@Test func apiBoundariesUseOriginalEntriesAndCoverEnding() throws {
    let rundown = try OpenAIRundown.materialize(apiDraft(), transcript: apiTranscript(), fingerprint: "fixture", reasoning: "medium")
    #expect(rundown.segments[0].clips[0].start == 1.25)
    #expect(rundown.segments[0].clips[0].end == 5.5)
    #expect(rundown.segments[0].clips[1].start == 6)
    #expect(rundown.segments[0].clips[1].end == 29)
    #expect(rundown.markdown.contains("via API"))
    #expect(!rundown.markdown.contains("Imported from"))
    let plan = try Selection.plan(.init(ids: ["1b"], beforeSeconds: 10, afterSeconds: 10, clarification: nil), rundown: rundown)
    #expect(plan.clips[0].start == "00:00:00.000")
    #expect(plan.clips[0].end == "00:00:30.000")
    #expect(throws: UserError.self) { try OpenAIRundown.materialize(apiDraft(end: 1), transcript: apiTranscript(), fingerprint: "fixture", reasoning: "medium") }
}

@Test func apiRejectsInvalidEntryIndicesWithoutCrashing() {
    for (start, end) in [(Int.min, 0), (0, Int.max), (1, 2), (0, -1), (0, 1)] {
        let clips = [EpisodeDraft.Clip(title: "Bad", startEntry: start, endEntry: end, summary: "Bad range.")]
        #expect(throws: UserError.self) {
            try OpenAIRundown.materialize(apiDraft(clips: clips), transcript: apiTranscript(), fingerprint: "fixture", reasoning: "medium")
        }
    }
}

@Test func apiRejectsPartialRefusedOrEmptyAnswers() throws {
    func response(status: String = "completed", itemStatus: String = "completed", type: String = "output_text", text: String = "{}") throws -> OpenAIResponse {
        let json: [String: Any] = ["status": status, "output": [["type": "message", "role": "assistant", "status": itemStatus, "content": [["type": type, "text": text]]]]]
        return try JSONDecoder().decode(OpenAIResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }
    #expect(try response().completedText() == "{}")
    #expect(throws: UserError.self) { try response(status: "incomplete").completedText() }
    #expect(throws: UserError.self) { try response(itemStatus: "in_progress").completedText() }
    #expect(throws: UserError.self) { try response(type: "refusal").completedText() }
    #expect(throws: UserError.self) { try response(text: " ").completedText() }
}

@Test func apiUsageIncludesReasoningAndCacheWritePricing() throws {
    let usage = OpenAIUsage(input_tokens: 100_000, output_tokens: 10_000,
                            input_tokens_details: .init(cached_tokens: 20_000, cache_write_tokens: 30_000),
                            output_tokens_details: .init(reasoning_tokens: 4_000))
    #expect(abs(try usage.estimatedUSD() - 0.277) < 0.000001)
    #expect(abs(OpenAIRundown.maximumEstimatedUSD(inputTokens: 100_000) - 0.5) < 0.000001)
    let invalid = OpenAIUsage(input_tokens: 10, output_tokens: 20, input_tokens_details: .init(cached_tokens: 11, cache_write_tokens: nil), output_tokens_details: nil)
    #expect(throws: UserError.self) { try invalid.estimatedUSD() }
}

@Test func apiRequestHasFullTranscriptAndExplicitSettings() throws {
    let payload = OpenAIRundown.payload(transcript: apiTranscript(), reasoning: "medium")
    let input = try #require(payload["input"] as? String)
    #expect(input.contains("[entry 0] [00:00:01.250–00:00:05.500] Opening"))
    #expect(input.contains("[entry 2] [00:00:17.750–00:00:29.000] Final interview"))
    #expect(payload["model"] as? String == "gpt-6.1-sol")
    #expect(payload["store"] as? Bool == false)
    #expect(payload["service_tier"] as? String == "default")
    #expect(payload["tools"] == nil)
    #expect(payload["max_output_tokens"] as? Int == 25_000)
    try OpenAIRundown.validateOptions(reasoning: "medium", maxCost: 1)
    #expect(throws: UserError.self) { try OpenAIRundown.validateOptions(reasoning: "none", maxCost: 1) }
    #expect(throws: UserError.self) { try OpenAIRundown.validateOptions(reasoning: "medium", maxCost: .nan) }
    #expect(throws: UserError.self) { try OpenAIClient(environment: [:]) }
}

@Test func apiResponseCacheCanPublishAndReuseWithoutCredentials() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let transcriptFile = directory.appendingPathComponent("transcript.json")
    let transcript = apiTranscript()
    let data = try jsonData(transcript)
    try data.write(to: transcriptFile)
    let fingerprint = LocalIntelligence.fingerprint(String(decoding: data, as: UTF8.self))
    let payload = OpenAIRundown.payload(transcript: transcript, reasoning: "medium")
    let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let hash = LocalIntelligence.fingerprint(OpenAIRundown.promptVersion + fingerprint + String(decoding: body, as: UTF8.self))
    let cache = directory.appendingPathComponent(".openai-rundown-cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let response: [String: Any] = ["id": "fixture-response", "model": "gpt-6.1-sol", "status": "completed", "output": [
        ["type": "message", "role": "assistant", "status": "completed", "content": [["type": "output_text", "text": String(decoding: try jsonData(apiDraft()), as: UTF8.self)]]]]]
    try JSONSerialization.data(withJSONObject: response).write(to: cache.appendingPathComponent(hash + ".response.json"))
    let output = try await OpenAIRundown.run(input: transcriptFile, destination: nil, language: "en-US", downloadAssets: false, reasoning: "medium", maxCost: 0.001)
    let first = try Data(contentsOf: output.appendingPathComponent("rundown.json"))
    _ = try await OpenAIRundown.run(input: transcriptFile, destination: nil, language: "en-US", downloadAssets: false, reasoning: "medium", maxCost: 0.001)
    #expect(try Data(contentsOf: output.appendingPathComponent("rundown.json")) == first)
}
