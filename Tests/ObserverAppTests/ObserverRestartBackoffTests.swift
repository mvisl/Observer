import Foundation
import Testing
@testable import ObserverApp

struct ObserverRestartBackoffTests {
    @Test func escalatesOnlyForUncleanRapidRestartsAndResetsOnGracefulExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("observer-backoff-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let backoff = ObserverRestartBackoff(directory: directory)
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(backoff.recordLaunchAndBackoff(now: now) == 0)
        #expect(backoff.recordLaunchAndBackoff(now: now.addingTimeInterval(5)) == 5)
        #expect(backoff.recordLaunchAndBackoff(now: now.addingTimeInterval(10)) == 10)

        backoff.recordGracefulShutdown()
        #expect(backoff.recordLaunchAndBackoff(now: now.addingTimeInterval(15)) == 0)
    }
}
