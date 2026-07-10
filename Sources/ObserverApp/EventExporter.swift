import Foundation

struct EventExporter {
    private let encoder = JSONEncoder.observerEncoder

    func exportJSONL(events: [ObserverEvent], directory: URL) throws -> URL {
        let exportsDirectory = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = exportsDirectory.appendingPathComponent("\(formatter.string(from: Date()))-events.jsonl")

        let contents = try events.map { event -> String in
            let data = try encoder.encode(event)
            return String(data: data, encoding: .utf8) ?? "{}"
        }.joined(separator: "\n")

        try (contents + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
