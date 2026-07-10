import Foundation
import Testing
@testable import ObserverApp

struct EventStoreTests {
    @Test func redactsPayloadBeforeStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-store-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = try EventStore(directory: directory)
        try store.append(
            ObserverEvent(
                type: .screenContext,
                payload: ["selected_text": "password: hunter2"],
                workspaceTopologyVersion: 1
            )
        )

        let event = try #require(store.recentEvents(limit: 1).first)
        #expect(event.payload["selected_text"]?.contains("hunter2") == false)
    }
}
