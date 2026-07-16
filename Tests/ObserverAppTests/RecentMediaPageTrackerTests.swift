import Foundation
import Testing
@testable import ObserverApp

struct RecentMediaPageTrackerTests {
    @Test func tracksKnownBrowserMediaPageWithoutTrackMetadata() {
        var tracker = RecentMediaPageTracker()
        let start = Date(timeIntervalSince1970: 1_000)

        tracker.observe(
            resourceURL: "https://www.youtube.com/watch?v=example",
            appName: "Google Chrome",
            windowTitle: "A music video - YouTube",
            now: start
        )

        #expect(tracker.recentSource(now: start.addingTimeInterval(5)) == "YouTube")
    }

    @Test func expiresMediaPageFallbackInsteadOfTogglingAnUnknownPlayer() {
        var tracker = RecentMediaPageTracker()
        let start = Date(timeIntervalSince1970: 1_000)
        tracker.observe(
            resourceURL: "https://music.apple.com/library",
            appName: "Music",
            windowTitle: "Apple Music",
            now: start
        )

        #expect(tracker.recentSource(now: start.addingTimeInterval(20 * 60 + 1)) == nil)
    }
}
