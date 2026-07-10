import Foundation

final class PrivacyStore {
    private struct PrivacyConfig: Codable {
        var allowedContentAppIDs: [String]
        var excludedAppIDs: [String]

        init(allowedContentAppIDs: [String], excludedAppIDs: [String]) {
            self.allowedContentAppIDs = allowedContentAppIDs
            self.excludedAppIDs = excludedAppIDs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.allowedContentAppIDs = try container.decodeIfPresent([String].self, forKey: .allowedContentAppIDs) ?? []
            self.excludedAppIDs = try container.decodeIfPresent([String].self, forKey: .excludedAppIDs) ?? []
        }
    }

    private let url: URL
    private let encoder = JSONEncoder.prettyPrintedObserverEncoder
    private let decoder = JSONDecoder.observerDecoder

    init(directory: URL) throws {
        self.url = directory.appendingPathComponent("privacy.json")
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = PrivacyConfig(allowedContentAppIDs: [], excludedAppIDs: [])
            try encoder.encode(config).write(to: url, options: .atomic)
        }
    }

    func addAllowedApp(_ appID: String) throws {
        var config = try load()
        guard !config.allowedContentAppIDs.contains(appID) else {
            return
        }
        config.allowedContentAppIDs.append(appID)
        config.allowedContentAppIDs.sort()
        try encoder.encode(config).write(to: url, options: .atomic)
    }

    func addExcludedApp(_ appID: String) throws {
        var config = try load()
        guard !config.excludedAppIDs.contains(appID) else {
            return
        }
        config.excludedAppIDs.append(appID)
        config.excludedAppIDs.sort()
        try encoder.encode(config).write(to: url, options: .atomic)
    }

    func isContentAllowed(_ appID: String) -> Bool {
        guard let config = try? load() else {
            return false
        }
        return config.allowedContentAppIDs.contains(appID) && !config.excludedAppIDs.contains(appID)
    }

    func isExcluded(_ appID: String) -> Bool {
        guard let config = try? load() else {
            return false
        }
        return config.excludedAppIDs.contains(appID)
    }

    private func load() throws -> PrivacyConfig {
        let data = try Data(contentsOf: url)
        return try decoder.decode(PrivacyConfig.self, from: data)
    }
}
