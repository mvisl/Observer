import Foundation
import Testing
@testable import ObserverApp

struct SecurityIncidentStoreTests {
    @Test func seenIncidentsAreCleanedAfterOneDay() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-security-store-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let store = try SecurityIncidentStore(directory: root)
        let incident = try store.record(
            payload: [
                "app_name": "Test",
                "seconds_since_any_input": "60",
                "review_state": "pending_owner_return_gate"
            ],
            jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9])
        )

        #expect(store.unseenCount() == 0)
        #expect(store.releasePendingForReview() == 1)
        #expect(store.unseenCount() == 1)

        store.markAllSeen()
        #expect(store.unseenCount() == 0)

        let future = incident.createdAt.addingTimeInterval(86_401)
        store.cleanupExpiredSeenIncidents(now: future)

        #expect(store.latestReviewable() == nil)
        if let photoURL = incident.photoURL {
            #expect(!FileManager.default.fileExists(atPath: photoURL.path))
        }
        if let transcriptURL = incident.transcriptURL {
            #expect(!FileManager.default.fileExists(atPath: transcriptURL.path))
        }
    }
}
