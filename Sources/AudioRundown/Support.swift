import Foundation

struct UserError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

func requireFile(_ url: URL) throws {
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
          !directory.boolValue, FileManager.default.isReadableFile(atPath: url.path) else {
        throw UserError("Cannot read file: \(url.path)")
    }
}

func requireNew(_ url: URL) throws {
    // attributesOfItem also detects dangling symlinks.
    if (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
        throw UserError("Output already exists: \(url.path). Choose a new output path.")
    }
}

func writeText(_ text: String, to url: URL) throws {
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func jsonData<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
}

/// Build a directory beside its destination, publishing only after every file succeeds.
func withNewDirectory(at destination: URL, body: (URL) async throws -> Void) async throws {
    try requireNew(destination)
    let fm = FileManager.default
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = destination.deletingLastPathComponent().appendingPathComponent(".audiorundown-\(UUID().uuidString)")
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    try await body(staging)
    try requireNew(destination)
    try fm.moveItem(at: staging, to: destination)
}

enum Timecode {
    /// Seconds, MM:SS, or HH:MM:SS, with optional fractional seconds.
    static func parse(_ input: String) throws -> Double {
        let fields = input.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(fields.count) else { throw invalid(input) }
        var total = 0.0
        for (index, field) in fields.enumerated() {
            let last = index == fields.count - 1
            let pattern = last ? #"^[0-9]+(?:\.[0-9]+)?$"# : #"^[0-9]+$"#
            guard field.range(of: pattern, options: .regularExpression) != nil,
                  let number = Double(field), number.isFinite,
                  (index == 0 || number < 60) else { throw invalid(input) }
            total = total * 60 + number
        }
        guard total.isFinite, total < 1_000_000_000 else { throw invalid(input) }
        return total
    }

    private static func invalid(_ input: String) -> UserError {
        UserError("Invalid time '\(input)'. Use seconds, MM:SS, or HH:MM:SS (e.g. 42:15.5).")
    }

    static func format(_ seconds: Double, srt: Bool = false) -> String {
        let milliseconds = Int64((max(0, seconds) * 1000).rounded())
        return String(format: "%02lld:%02lld:%02lld%@%03lld", milliseconds / 3_600_000,
                      milliseconds / 60_000 % 60, milliseconds / 1000 % 60,
                      srt ? "," : ".", milliseconds % 1000)
    }
}

struct AudioRange: Equatable {
    let start: Double
    let end: Double
    var duration: Double { end - start }

    init(start: Double, end: Double, sourceDuration: Double) throws {
        guard start.isFinite, end.isFinite, sourceDuration.isFinite,
              start >= 0, end > start, end <= sourceDuration else {
            throw UserError("Invalid section \(start)–\(end) seconds. Require 0 ≤ start < end ≤ \(sourceDuration).")
        }
        self.start = start
        self.end = end
    }
}

func safeFilename(_ title: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let pieces = title.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
    let value = String(pieces.joined(separator: "-").prefix(80))
    return value.isEmpty ? "clip" : value
}

enum Subprocess {
    static func executable(_ name: String) throws -> URL {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw UserError("\(name) is required. Install FFmpeg (brew install ffmpeg).")
    }

    /// Arguments are passed directly, never evaluated by a shell. Stderr stays visible.
    static func run(_ executable: URL, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw UserError("\(executable.lastPathComponent) failed (status \(process.terminationStatus)); see the error above.")
        }
        return output
    }
}
