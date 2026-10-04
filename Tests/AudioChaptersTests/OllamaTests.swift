import Foundation
import Testing
@testable import AudioChapters

@Test func ollamaRejectsPartialAndEmptyResponses() throws {
    let good = Data(#"{"done":true,"done_reason":"stop","message":{"content":"Complete paragraph."}}"#.utf8)
    #expect(try OllamaClient.content(from: good) == "Complete paragraph.")
    for text in [
        #"{"done":true,"done_reason":"length","message":{"content":"Unfinished"}}"#,
        #"{"done":false,"message":{"content":"Still streaming"}}"#,
        #"{"done":true,"message":{"content":"  "}}"#
    ] {
        #expect(throws: UserError.self) { try OllamaClient.content(from: Data(text.utf8)) }
    }
}

@Test func ollamaCloudModelsCannotReceiveTranscript() throws {
    try OllamaClient.requireLocalModel(name: "qwen3.6:27b", metadata: [:])
    #expect(throws: UserError.self) { try OllamaClient.requireLocalModel(name: "example:cloud", metadata: ["remote_host": "https://example.com"]) }
    #expect(throws: UserError.self) { try OllamaClient.requireLocalModel(name: "example:cloud", metadata: ["remote_model": "example"]) }
    #expect(throws: UserError.self) { try OllamaClient.requireLocalModel(name: "example:27b-cloud", metadata: [:]) }
}

@Test func savedRundownRemembersSelectionModel() {
    #expect(LocalIntelligence.savedModelName(engine: "Ollama: qwen3.6:27b (local)") == "qwen3.6:27b")
    #expect(LocalIntelligence.savedModelName(engine: "Apple SystemLanguageModel (on device)") == "apple")
}
