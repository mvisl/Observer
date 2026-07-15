import Foundation
import Testing
@testable import ObserverApp

struct MediaReactionBuilderTests {
    @Test func quickSkipBecomesNegativePreferenceCandidate() throws {
        let reaction = try #require(MediaReactionBuilder().build(
            previous: music(title: "Old Song", artist: "Artist", volume: 40),
            current: music(title: "New Song", artist: "Artist", volume: 40),
            secondsOnPrevious: 23,
            userAppearsAway: false,
            activityInsight: "Дизайн: основной экран",
            activeAppName: "Figma"
        ))

        #expect(reaction.name == "quick_skip")
        #expect(reaction.preference == "negative_candidate")
        #expect(reaction.payload["previous_title"] == "Old Song")
        #expect(reaction.payload["preference_recorded"] == "true")
    }

    @Test func awayPlaybackDoesNotRecordPreference() {
        let reaction = MediaReactionBuilder().build(
            previous: music(title: "Old Song", artist: "Artist", volume: 40),
            current: music(title: "New Song", artist: "Artist", volume: 40),
            secondsOnPrevious: 23,
            userAppearsAway: true,
            activityInsight: nil,
            activeAppName: nil
        )

        #expect(reaction == nil)
    }

    @Test func volumeIncreaseBecomesPositivePreferenceCandidate() throws {
        let reaction = try #require(MediaReactionBuilder().build(
            previous: music(title: "Song", artist: "Artist", volume: 32),
            current: music(title: "Song", artist: "Artist", volume: 48),
            secondsOnPrevious: 120,
            userAppearsAway: false,
            activityInsight: "Код: активная правка",
            activeAppName: "Xcode"
        ))

        #expect(reaction.name == "volume_up")
        #expect(reaction.preference == "positive_candidate")
        #expect(reaction.payload["volume_delta"] == "16")
    }

    @Test func youtubeQuickSwitchBecomesContentPreferenceCandidate() throws {
        let reaction = try #require(MediaReactionBuilder().build(
            previous: youtube(title: "Old Video", volume: 50),
            current: youtube(title: "New Video", volume: 50),
            secondsOnPrevious: 18,
            userAppearsAway: false,
            activityInsight: "Веб-контекст: читает",
            activeAppName: "Google Chrome"
        ))

        #expect(reaction.name == "quick_skip")
        #expect(reaction.payload["source_family"] == "youtube")
        #expect(reaction.payload["content_type"] == "unknown_youtube_media")
        #expect(reaction.insight.contains("Контент"))
    }

    @Test func communicationContextLowersConfidence() throws {
        let reaction = try #require(MediaReactionBuilder().build(
            previous: music(title: "Song", artist: "Artist", volume: 20),
            current: music(title: "Song", artist: "Artist", volume: 35),
            secondsOnPrevious: 120,
            userAppearsAway: false,
            activityInsight: "Коммуникация: отвечает",
            activeAppName: "Telegram"
        ))

        #expect(reaction.payload["confounder"] == "communication_context")
        #expect(reaction.confidence < 0.45)
    }

    @Test func sustainedListenBecomesPositivePreferenceCandidate() throws {
        let reaction = try #require(MediaReactionBuilder().sustainedListenReaction(
            current: music(title: "Loop Song", artist: "Artist", volume: 42),
            listenSeconds: 420,
            observationSamples: 30,
            userAppearsAway: false,
            inputActiveDuringTrack: true,
            activeAppName: "Figma"
        ))

        #expect(reaction.name == "sustained_listen")
        #expect(reaction.preference == "positive_candidate")
        #expect(reaction.payload["current_title"] == "Loop Song")
        #expect(reaction.payload["productivity_after_music"] == "active_input_during_track")
    }

    @Test func awaySustainedListenDoesNotRecordPreference() {
        let reaction = MediaReactionBuilder().sustainedListenReaction(
            current: music(title: "Loop Song", artist: "Artist", volume: 42),
            listenSeconds: 420,
            observationSamples: 30,
            userAppearsAway: true,
            inputActiveDuringTrack: true,
            activeAppName: "Figma"
        )

        #expect(reaction == nil)
    }

    private func music(title: String, artist: String, volume: Int) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: "Music",
            state: "playing",
            title: title,
            artist: artist,
            album: "Album",
            volume: volume
        )
    }

    private func youtube(title: String, volume: Int) -> MediaPlaybackSnapshot {
        MediaPlaybackSnapshot(
            source: "YouTube Chrome",
            state: "playing",
            title: title,
            artist: nil,
            album: "YouTube",
            volume: volume
        )
    }
}
