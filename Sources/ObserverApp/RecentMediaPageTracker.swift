import Foundation

/// Remembers a recently visible media page locally. This is a fallback only for
/// dispatching the standard macOS media key when CoreAudio cannot report browser
/// playback. It does not claim to identify a track or prove that it is playing.
struct RecentMediaPageTracker {
    private(set) var lastSeenAt: Date?
    private(set) var source: String?

    mutating func observe(
        resourceURL: String?,
        appName: String,
        windowTitle: String?,
        now: Date = Date()
    ) {
        guard let source = Self.mediaSource(
            resourceURL: resourceURL,
            appName: appName,
            windowTitle: windowTitle
        ) else {
            return
        }
        self.source = source
        lastSeenAt = now
    }

    func recentSource(now: Date = Date(), maximumAge: TimeInterval = 20 * 60) -> String? {
        guard let lastSeenAt, now.timeIntervalSince(lastSeenAt) <= maximumAge else {
            return nil
        }
        return source
    }

    static func mediaSource(resourceURL: String?, appName: String, windowTitle: String?) -> String? {
        let text = [resourceURL, appName, windowTitle]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if text.contains("youtube.com/watch") || text.contains("youtu.be/") || text.contains("youtube music") {
            return "YouTube"
        }
        if text.contains("music.apple.com") || text.contains("apple music") || text == "music" {
            return "Apple Music"
        }
        if text.contains("open.spotify.com") || text.contains("spotify") {
            return "Spotify"
        }
        if text.contains("soundcloud.com") || text.contains("soundcloud") {
            return "SoundCloud"
        }
        return nil
    }
}
