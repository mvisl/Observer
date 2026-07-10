import Foundation
import Testing
@testable import ObserverApp

struct EventDeletionTests {
    @Test func deletesAllEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-delete-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try EventStore(directory: directory)
        try store.append(ObserverEvent(type: .appLaunch, workspaceTopologyVersion: 1))
        #expect(try store.recentEvents(limit: 10).count == 1)

        try store.deleteAllEvents()
        #expect(try store.recentEvents(limit: 10).isEmpty)
    }
}
