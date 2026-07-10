import Testing
@testable import ObserverApp

struct MediaPlaybackServiceTests {
    @Test func parsesPlaybackOutput() throws {
        let snapshot = try #require(MediaPlaybackService.parseOutput("Music|playing|Song|Artist|Album|42"))

        #expect(snapshot.source == "Music")
        #expect(snapshot.state == "playing")
        #expect(snapshot.title == "Song")
        #expect(snapshot.artist == "Artist")
        #expect(snapshot.album == "Album")
        #expect(snapshot.volume == 42)
        #expect(snapshot.eventPayload["volume"] == "42")
    }

    @Test func omitsEmptyTrackFields() throws {
        let snapshot = try #require(MediaPlaybackService.parseOutput("Music|stopped|||"))

        #expect(snapshot.source == "Music")
        #expect(snapshot.state == "stopped")
        #expect(snapshot.title == nil)
        #expect(snapshot.eventPayload["title"] == nil)
    }

    @Test func parsesYouTubePlaybackOutput() throws {
        let snapshot = try #require(MediaPlaybackService.parseOutput("YouTube Chrome|playing|Deep Work Mix||YouTube|76"))

        #expect(snapshot.source == "YouTube Chrome")
        #expect(snapshot.title == "Deep Work Mix")
        #expect(snapshot.album == "YouTube")
        #expect(snapshot.volume == 76)
    }

    @Test func resumeSourceIsOnlySetForPlayingKnownSources() throws {
        let playing = try #require(MediaPlaybackService.parseOutput("Music|playing|Track|Artist|Album|50"))
        let paused = try #require(MediaPlaybackService.parseOutput("Music|paused|Track|Artist|Album|50"))

        #expect(playing.sourceForObserverResume == "Music")
        #expect(paused.sourceForObserverResume == nil)
    }
}
