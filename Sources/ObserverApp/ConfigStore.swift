import Foundation

final class ConfigStore {
    private let directory: URL
    private let encoder = JSONEncoder.prettyPrintedObserverEncoder
    private let decoder = JSONDecoder.observerDecoder

    init(directory: URL) {
        self.directory = directory
    }

    func loadOrCreateTopology() throws -> WorkspaceTopology {
        let url = directory.appendingPathComponent("workspace-topology.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try decoder.decode(WorkspaceTopology.self, from: data)
        }

        let topology = WorkspaceTopology.defaultTwoDisplaySetup
        let data = try encoder.encode(topology)
        try data.write(to: url, options: .atomic)
        return topology
    }

    func loadOrCreateSettings() throws -> ObserverSettings {
        let url = directory.appendingPathComponent("observer-settings.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try decoder.decode(ObserverSettings.self, from: data)
        }

        let settings = ObserverSettings.defaults
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
        return settings
    }
}
