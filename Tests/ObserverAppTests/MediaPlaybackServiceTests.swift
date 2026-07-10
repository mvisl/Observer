import Testing
@testable import ObserverApp

struct MediaPlaybackServiceTests {
    @Test func parsesPlaybackOutput() throws {
        let snapshot = try #require(MediaPlaybackService.parseOutput("Music|playing|Song|Artist|Album"))

        #expect(snapshot.source == "Music")
        #expect(snapshot.state == "playing")
        #expect(snapshot.title == "Song")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.album == "Album")
    }

    @Test func omitsEmptyTrackFields() throws {
        let snapshot = try #require(MediaPlaybackService.parseOutput("Music|stopped|||"))

        #expect(snapshot.source == "Music")
        #expect(snapshot.state == "stopped")
        #expect(snapshot.title == nil)
        #expect(snapshot.eventPayload["title"] == nil)
    }
}
