import Foundation

enum Workflow {
    private struct ActiveRundown: Codable { let path: String }

    static func transcriptDirectory(for input: URL) -> URL {
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: input.path, isDirectory: &directory), directory.boolValue { return input }
        if input.pathExtension.lowercased() == "json" { return input.deletingLastPathComponent() }
        return input.deletingPathExtension().appendingPathExtension("transcript")
    }

    static func remember(output: URL, transcriptInput: URL) throws {
        let directory = transcriptDirectory(for: transcriptInput)
        // A successful generation/import already has a transcript here.
        try requireFile(transcriptInput.pathExtension.lowercased() == "json" ? transcriptInput : directory.appendingPathComponent("transcript.json"))
        let prefix = directory.path + "/"
        let path = output.path.hasPrefix(prefix) ? String(output.path.dropFirst(prefix.count)) : output.path
        try jsonData(ActiveRundown(path: path)).write(to: directory.appendingPathComponent("active-rundown.json"), options: .atomic)
    }

    static func resolve(_ input: URL) throws -> URL {
        let fm = FileManager.default
        var directory: ObjCBool = false
        let exists = fm.fileExists(atPath: input.path, isDirectory: &directory)
        if directory.boolValue, fm.fileExists(atPath: input.appendingPathComponent("rundown.json").path) { return input }
        if input.pathExtension.lowercased() == "json", input.lastPathComponent != "transcript.json" { return input }
        if input.pathExtension.lowercased() == "md" { return input.deletingLastPathComponent().appendingPathComponent("rundown.json") }
        guard exists else { throw UserError("Input not found: \(input.path)") }
        let root = transcriptDirectory(for: input)
        let pointer = root.appendingPathComponent("active-rundown.json")
        let selected: URL
        if fm.fileExists(atPath: pointer.path) {
            let saved = try JSONDecoder().decode(ActiveRundown.self, from: Data(contentsOf: pointer))
            selected = saved.path.hasPrefix("/") ? fileURL(saved.path) : root.appendingPathComponent(saved.path)
        } else {
            let candidates = ["rundown", "rundown-openai"].map { root.appendingPathComponent($0) }
                .filter { fm.fileExists(atPath: $0.appendingPathComponent("rundown.json").path) }
            guard candidates.count == 1 else {
                throw UserError(candidates.isEmpty
                    ? "No saved rundown found beside this input. Run audiochapters rundown \(quote(input.path)), or pass the saved rundown directory to select."
                    : "Multiple rundowns found. Pass the desired rundown directory to select, or rerun rundown with its model to make it active.")
            }
            selected = candidates[0]
        }
        let rundown = try Rundown.load(selected)
        if !directory.boolValue && input.pathExtension.lowercased() != "json" {
            guard fileURL(rundown.source).resolvingSymlinksInPath() == input.resolvingSymlinksInPath() else {
                throw UserError("The saved rundown belongs to another source. Pass its directory and --source AUDIO if you moved the recording.")
            }
        }
        return selected
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }

    static func finish(output: URL, settings: Settings, open: Bool) throws {
        let markdown = output.appendingPathComponent("rundown.md")
        let rundown = try Rundown.load(output)
        let source = fileURL(rundown.source)
        let resolved = try? resolve(source)
        let selectionInput = resolved?.resolvingSymlinksInPath().path == output.resolvingSymlinksInPath().path ? source : output
        print("\nSummary: \(markdown.path)")
        let app = settings.editor.map { " -a " + quote($0) } ?? ""
        print("Open: open\(app) \(quote(markdown.path))")
        print("Choose clips: audiochapters select \(quote(selectionInput.path))")
        if open {
            do {
                var arguments = settings.editor.map { ["-a", $0] } ?? []
                arguments.append(markdown.path)
                _ = try Subprocess.run(URL(fileURLWithPath: "/usr/bin/open"), arguments)
            } catch { log("Summary saved, but could not open the app: \(error.localizedDescription)") }
        }
    }
}
