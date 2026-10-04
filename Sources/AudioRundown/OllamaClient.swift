import Foundation

/// Fixed loopback transport: no hosted endpoints, cloud models, or automatic downloads.
struct OllamaClient {
    let modelName: String
    let digest: String
    let contextSize = 32_768
    static let baseURL = URL(string: "http://127.0.0.1:11434")!

    static func connect(modelName: String) async throws -> OllamaClient {
        struct Inventory: Decodable {
            struct Model: Decodable { let name: String; let digest: String }
            let models: [Model]
        }
        let inventory = try JSONDecoder().decode(Inventory.self, from: await request(path: "api/tags"))
        let name = modelName.contains(":") ? modelName : modelName + ":latest"
        guard let installed = inventory.models.first(where: { $0.name == name }) else {
            throw UserError("Ollama model '\(name)' is not installed. Install it with ollama pull \(name), then retry.")
        }
        let show = try await request(path: "api/show", body: JSONSerialization.data(withJSONObject: ["model": name]))
        let metadata = try JSONSerialization.jsonObject(with: show) as? [String: Any] ?? [:]
        try requireLocalModel(name: name, metadata: metadata)
        return OllamaClient(modelName: name, digest: installed.digest)
    }

    static func requireLocalModel(name: String, metadata: [String: Any]) throws {
        guard !name.hasSuffix("-cloud"), (metadata["remote_host"] as? String ?? "").isEmpty,
              (metadata["remote_model"] as? String ?? "").isEmpty else {
            throw UserError("Use a locally installed Ollama model; cloud models are not supported.")
        }
    }

    func complete(instructions: String, prompt: String, outputTokens: Int, schema: Data? = nil) async throws -> String {
        var payload: [String: Any] = [
            "model": modelName,
            "messages": [["role": "system", "content": instructions], ["role": "user", "content": prompt]],
            "stream": false, "think": false, "keep_alive": "15m",
            "options": ["temperature": 0, "num_ctx": contextSize, "num_predict": outputTokens]
        ]
        if let schema { payload["format"] = try JSONSerialization.jsonObject(with: schema) }
        let data = try await Self.request(path: "api/chat", body: JSONSerialization.data(withJSONObject: payload))
        return try Self.content(from: data)
    }

    static func content(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
            let done: Bool
            let done_reason: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.done, response.done_reason != "length" else {
            throw UserError("Ollama stopped before completing its response. No partial result was saved.")
        }
        guard !response.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UserError("Ollama returned an empty response.")
        }
        return response.message.content
    }

    static func request(path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1800
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw UserError("Could not reach local Ollama at 127.0.0.1:11434: \(error.localizedDescription). Start Ollama and retry; completed analysis is cached.") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "Unexpected HTTP response."
            throw UserError("Ollama: \(message.prefix(1000))")
        }
        return data
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
