import Foundation

struct ArtifactExporter {
    let directory: URL

    func export(name: String, contents: String) throws -> URL {
        let exportsDirectory = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let timestamp = Self.filenameTimestamp()
        let safeName = name
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        let url = exportsDirectory.appendingPathComponent("\(timestamp)-\(safeName).md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
