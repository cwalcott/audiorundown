import Foundation

/// Explicit saved preferences; a fresh installation stays local.
struct Settings: Codable {
    var model: String = "apple"
    var reasoning: String = "medium"
    var maxCost: Double = 1
    var editor: String? = nil

    static var location: URL {
        if let path = ProcessInfo.processInfo.environment["AUDIORUNDOWN_CONFIG"] { return fileURL(path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/audiorundown/config.json")
    }

    static func load(from url: URL = location) throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else { return Settings() }
        let settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
        try settings.validate()
        return settings
    }

    func validate() throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.hasPrefix("openai:") || model == OpenAIClient.selector else {
            throw UserError("Choose apple, an installed Ollama model, or \(OpenAIClient.selector).")
        }
        guard ["low", "medium", "high", "xhigh", "max"].contains(reasoning) else {
            throw UserError("Reasoning must be low, medium, high, xhigh, or max.")
        }
        guard maxCost.isFinite, maxCost > 0 else { throw UserError("--max-cost must be a positive finite USD amount.") }
        if let editor, editor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw UserError("--editor must name a macOS application, such as 'Visual Studio Code'.")
        }
    }

    func save(to url: URL = location) throws {
        try validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonData(self).write(to: url, options: .atomic)
    }

    static func configure(_ arguments: Arguments) throws {
        guard arguments.positional.isEmpty else { throw UserError("configure takes options only.") }
        var settings = try load()
        if let model = arguments.options["--model"] { settings.model = model }
        if let reasoning = arguments.options["--reasoning"] { settings.reasoning = reasoning }
        if let amount = arguments.options["--max-cost"] {
            guard let cost = Double(amount) else { throw UserError("--max-cost must be a positive USD amount.") }
            settings.maxCost = cost
        }
        if let editor = arguments.options["--editor"] { settings.editor = editor }
        if !arguments.options.isEmpty { try settings.save() }
        print("Preferences: \(location.path)\nRundown model: \(settings.model)\nAPI reasoning: \(settings.reasoning)\nEstimated API cap: $\(settings.maxCost)\nSummary app: \(settings.editor ?? "system default")")
    }
}
