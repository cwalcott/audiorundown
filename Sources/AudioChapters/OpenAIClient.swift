import Foundation

struct OpenAIUsage: Codable {
    struct InputDetails: Codable { let cached_tokens: Int?; let cache_write_tokens: Int? }
    struct OutputDetails: Codable { let reasoning_tokens: Int? }
    let input_tokens: Int
    let output_tokens: Int
    let input_tokens_details: InputDetails?
    let output_tokens_details: OutputDetails?

    /// Standard short-context GPT-6.1 Sol prices checked 2026-10-04; excludes taxes.
    func estimatedUSD() throws -> Double {
        let cached = input_tokens_details?.cached_tokens ?? 0
        let written = input_tokens_details?.cache_write_tokens ?? 0
        guard input_tokens >= 0, input_tokens <= 272_000, output_tokens >= 0,
              cached >= 0, written >= 0, cached <= input_tokens, written <= input_tokens - cached else {
            throw UserError("Unsupported API usage; consult the OpenAI dashboard for cost.")
        }
        return (Double(input_tokens - cached - written) * 2 + Double(cached) * 0.1 + Double(written) * 2.5 + Double(output_tokens) * 10) / 1_000_000
    }
}

struct OpenAIResponse: Decodable {
    struct Item: Decodable {
        struct Content: Decodable { let type: String; let text: String? }
        let type: String
        let role: String?
        let status: String?
        let content: [Content]?
    }
    let id: String?
    let model: String?
    let status: String
    let output: [Item]?
    let usage: OpenAIUsage?

    func completedText() throws -> String {
        guard status == "completed" else {
            throw UserError("OpenAI did not complete the response (possibly the output-token limit). The response is retained locally; no automatic paid retry was made.")
        }
        let messages = (output ?? []).filter { $0.type == "message" && $0.role == "assistant" }
        guard !messages.isEmpty, messages.allSatisfy({ $0.status == "completed" }),
              !messages.flatMap({ $0.content ?? [] }).contains(where: { $0.type == "refusal" }) else {
            throw UserError("OpenAI did not return a complete assistant answer, or declined the request. No rundown was published.")
        }
        let text = messages.flatMap { $0.content ?? [] }.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UserError("OpenAI returned an empty answer.") }
        return text
    }
}

/// Explicit HTTPS transport. Keys never appear in URLs, files, or error messages.
struct OpenAIClient {
    static let model = "gpt-6.1-sol"
    static let selector = "openai:" + model
    private let key: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let value = (environment["OPENAI_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else {
            throw UserError("Set OPENAI_API_KEY in the shell running audiochapters. Do not pass the key as a command-line argument.")
        }
        key = value
    }

    func countInput(_ payload: [String: Any]) async throws -> Int {
        let allowed = Set(["model", "input", "instructions", "text", "reasoning"])
        struct Count: Decodable { let input_tokens: Int }
        let data = try await request(path: "responses/input_tokens", payload: payload.filter { allowed.contains($0.key) })
        let count = try JSONDecoder().decode(Count.self, from: data).input_tokens
        guard count > 0, count <= 250_000 else {
            throw UserError("API rundowns currently support up to 250,000 input tokens. No generation request was sent.")
        }
        return count
    }

    func generate(_ payload: [String: Any]) async throws -> Data {
        try await request(path: "responses", payload: payload)
    }

    private func request(path: String, payload: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/" + path)!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1800
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            throw UserError("OpenAI connection failed or timed out. No automatic retry was made; a generation request may still have incurred usage. Check the dashboard before retrying.")
        }
        guard let http = response as? HTTPURLResponse else { throw UserError("Unexpected OpenAI HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let hint: String
            switch http.statusCode {
            case 401: hint = "Check OPENAI_API_KEY and its expiration."
            case 403: hint = "Check Responses API permissions and project/model access."
            case 404: hint = "The requested endpoint or model is not available to this project."
            case 429: hint = "Check API billing, available credits, and rate limits."
            case 400: hint = "The API rejected the request parameters."
            default: hint = "Check API availability and project settings."
            }
            // Provider messages can echo request content or credentials. Never print them.
            throw UserError("OpenAI HTTP \(http.statusCode). \(hint) No automatic retry was made.")
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
