import Foundation

struct GeminiKeyStore {
    let directory: URL

    private var fileURL: URL {
        directory.appendingPathComponent("gemini-api-key.local", isDirectory: false)
    }

    func hasKey() -> Bool {
        apiKey(allowKeychainMigration: false)?.isEmpty == false
    }

    func apiKey(allowKeychainMigration: Bool = false) -> String? {
        _ = allowKeychainMigration
        let environmentKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
        if let key = environmentKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }

        if let data = try? Data(contentsOf: fileURL),
           let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }

        return nil
    }

    func setAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func deleteAPIKey() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
