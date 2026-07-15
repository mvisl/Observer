import Foundation

struct MediaReaction: Equatable {
    let name: String
    let preference: String
    let insight: String
    let confidence: Double
    let payload: [String: String]
}

struct MediaReactionBuilder {
    private let quickSkipThresholdSeconds: TimeInterval = 75
    private let volumeIncreaseThreshold = 10

    func build(
        previous: MediaPlaybackSnapshot?,
        current: MediaPlaybackSnapshot,
        secondsOnPrevious: TimeInterval?,
        userAppearsAway: Bool,
        activityInsight: String?,
        activeAppName: String?
    ) -> MediaReaction? {
        guard current.isPreferenceSource else {
            return nil
        }
        guard let previous, previous.source == current.source else {
            return nil
        }

        if previous.trackIdentityKey != current.trackIdentityKey {
            return quickSkipReaction(
                previous: previous,
                current: current,
                secondsOnPrevious: secondsOnPrevious,
                userAppearsAway: userAppearsAway,
                activityInsight: activityInsight,
                activeAppName: activeAppName
            )
        }

        return volumeReaction(
            previous: previous,
            current: current,
            userAppearsAway: userAppearsAway,
            activityInsight: activityInsight,
            activeAppName: activeAppName
        )
    }

    func sustainedListenReaction(
        current: MediaPlaybackSnapshot,
        listenSeconds: TimeInterval,
        observationSamples: Int,
        userAppearsAway: Bool,
        inputActiveDuringTrack: Bool,
        activeAppName: String?
    ) -> MediaReaction? {
        guard current.isPreferenceSource else {
            return nil
        }
        guard !userAppearsAway else {
            return nil
        }
        guard current.state == "playing" else {
            return nil
        }
        guard listenSeconds >= 180, observationSamples >= 12 else {
            return nil
        }

        var payload = currentPayload(
            reaction: "sustained_listen",
            preference: "positive_candidate",
            current: current,
            activeAppName: activeAppName
        )
        payload["listen_seconds"] = String(format: "%.1f", listenSeconds)
        payload["observation_samples"] = "\(observationSamples)"
        payload["preference_recorded"] = "true"
        payload["productivity_after_music"] = inputActiveDuringTrack ? "active_input_during_track" : "unknown"
        if inputActiveDuringTrack {
            payload["productivity_signal"] = "input stayed active while track repeated or continued"
        }

        let base = inputActiveDuringTrack ? 0.64 : 0.54
        let adjusted = adjustedConfidence(base, activeAppName: activeAppName, payload: &payload)
        return MediaReaction(
            name: "sustained_listen",
            preference: "positive_candidate",
            insight: current.isYouTube
                ? "Контент: удерживает внимание, проверяю влияние на работу"
                : "Музыка: трек держится, проверяю влияние на темп",
            confidence: adjusted,
            payload: payload
        )
    }

    private func quickSkipReaction(
        previous: MediaPlaybackSnapshot,
        current: MediaPlaybackSnapshot,
        secondsOnPrevious: TimeInterval?,
        userAppearsAway: Bool,
        activityInsight: String?,
        activeAppName: String?
    ) -> MediaReaction? {
        guard !userAppearsAway else {
            return nil
        }
        guard previous.state == "playing", current.state == "playing" else {
            return nil
        }
        guard let secondsOnPrevious, secondsOnPrevious <= quickSkipThresholdSeconds else {
            return nil
        }

        var payload = basePayload(
            reaction: "quick_skip",
            preference: "negative_candidate",
            previous: previous,
            current: current,
            activityInsight: activityInsight,
            activeAppName: activeAppName
        )
        payload["seconds_on_previous_track"] = String(format: "%.1f", secondsOnPrevious)
        payload["threshold_seconds"] = "\(Int(quickSkipThresholdSeconds))"
        payload["preference_recorded"] = "true"

        let adjusted = adjustedConfidence(0.58, activeAppName: activeAppName, payload: &payload)
        return MediaReaction(
            name: "quick_skip",
            preference: "negative_candidate",
            insight: current.isYouTube
                ? "Контент: быстро переключил, не удержал внимание"
                : "Музыка: быстрый скип, трек не зашел",
            confidence: adjusted,
            payload: payload
        )
    }

    private func volumeReaction(
        previous: MediaPlaybackSnapshot,
        current: MediaPlaybackSnapshot,
        userAppearsAway: Bool,
        activityInsight: String?,
        activeAppName: String?
    ) -> MediaReaction? {
        guard !userAppearsAway else {
            return nil
        }
        guard current.state == "playing" else {
            return nil
        }
        guard let previousVolume = previous.volume, let currentVolume = current.volume else {
            return nil
        }

        let delta = currentVolume - previousVolume
        guard delta >= volumeIncreaseThreshold else {
            return nil
        }

        var payload = basePayload(
            reaction: "volume_up",
            preference: "positive_candidate",
            previous: previous,
            current: current,
            activityInsight: activityInsight,
            activeAppName: activeAppName
        )
        payload["volume_delta"] = "\(delta)"
        payload["preference_recorded"] = "true"

        let adjusted = adjustedConfidence(0.45, activeAppName: activeAppName, payload: &payload)
        return MediaReaction(
            name: "volume_up",
            preference: "positive_candidate",
            insight: current.isYouTube
                ? "Контент: прибавил громкость, стоит запомнить"
                : "Музыка: прибавил громкость, трек зашел",
            confidence: adjusted,
            payload: payload
        )
    }

    private func basePayload(
        reaction: String,
        preference: String,
        previous: MediaPlaybackSnapshot,
        current: MediaPlaybackSnapshot,
        activityInsight: String?,
        activeAppName: String?
    ) -> [String: String] {
        var payload: [String: String] = [
            "reaction": reaction,
            "preference": preference,
            "source": current.source,
            "source_family": current.sourceFamily,
            "content_type": current.contentType,
            "previous_state": previous.state,
            "current_state": current.state
        ]

        if let title = previous.title {
            payload["previous_title"] = title
        }
        if let artist = previous.artist {
            payload["previous_artist"] = artist
        }
        if let title = current.title {
            payload["current_title"] = title
        }
        if let artist = current.artist {
            payload["current_artist"] = artist
        }
        if let previousVolume = previous.volume {
            payload["previous_volume"] = "\(previousVolume)"
        }
        if let currentVolume = current.volume {
            payload["current_volume"] = "\(currentVolume)"
        }
        if let activityInsight {
            payload["activity_insight"] = activityInsight
        }
        if let activeAppName {
            payload["app_name"] = activeAppName
        }

        return payload
    }

    private func currentPayload(
        reaction: String,
        preference: String,
        current: MediaPlaybackSnapshot,
        activeAppName: String?
    ) -> [String: String] {
        var payload: [String: String] = [
            "reaction": reaction,
            "preference": preference,
            "source": current.source,
            "source_family": current.sourceFamily,
            "content_type": current.contentType,
            "current_state": current.state
        ]

        if let title = current.title {
            payload["current_title"] = title
        }
        if let artist = current.artist {
            payload["current_artist"] = artist
        }
        if let currentVolume = current.volume {
            payload["current_volume"] = "\(currentVolume)"
        }
        if let activeAppName {
            payload["app_name"] = activeAppName
        }

        return payload
    }

    private func adjustedConfidence(
        _ base: Double,
        activeAppName: String?,
        payload: inout [String: String]
    ) -> Double {
        guard activeAppName?.isCommunicationContext == true else {
            return base
        }

        payload["confounder"] = "communication_context"
        payload["confidence_note"] = "positive or negative reaction may belong to message context, not music"
        return max(0.2, base - 0.12)
    }
}

private extension MediaPlaybackSnapshot {
    var isYouTube: Bool {
        source.contains("YouTube")
    }

    var isPreferenceSource: Bool {
        source == "Music" || isYouTube
    }

    var sourceFamily: String {
        isYouTube ? "youtube" : "apple_music"
    }

    var contentType: String {
        isYouTube ? "unknown_youtube_media" : "music"
    }
}

private extension String {
    var isCommunicationContext: Bool {
        let lowercased = lowercased()
        return lowercased.contains("telegram")
            || lowercased.contains("slack")
            || lowercased.contains("messages")
            || lowercased.contains("whatsapp")
            || lowercased.contains("discord")
            || lowercased.contains("mail")
    }
}
