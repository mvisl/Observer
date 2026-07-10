import Foundation

struct AppEnvironment {
    let dataDirectory: URL
    let configStore: ConfigStore
    let eventStore: EventStore
    let entityStore: EntityStore
    let privacyStore: PrivacyStore
    let settings: ObserverSettings
    let topology: WorkspaceTopology

    static func bootstrap() throws -> AppEnvironment {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("Observer", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let configStore = ConfigStore(directory: directory)
        let topology = try configStore.loadOrCreateTopology()
        let settings = try configStore.loadOrCreateSettings()
        let eventStore = try EventStore(directory: directory)
        let entityStore = try EntityStore(directory: directory)
        try eventStore.pruneEvents(olderThanDays: settings.retentionDays, keepingTypes: [.localSummary])
        let privacyStore = try PrivacyStore(directory: directory)

        return AppEnvironment(
            dataDirectory: directory,
            configStore: configStore,
            eventStore: eventStore,
            entityStore: entityStore,
            privacyStore: privacyStore,
            settings: settings,
            topology: topology
        )
    }
}
