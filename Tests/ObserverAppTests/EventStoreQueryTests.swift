import Foundation
import Testing
@testable import ObserverApp

struct EventStoreQueryTests {
    @Test func readsAllEventsInAscendingOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-query-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try EventStore(directory: directory)
        try store.append(ObserverEvent(type: .appLaunch, workspaceTopologyVersion: 1))
        try store.append(ObserverEvent(type: .appShutdown, workspaceTopologyVersion: 1))

        let events = try store.allEvents()
        #expect(events.map(\.type) == [.appLaunch, .appShutdown])
    }
}
