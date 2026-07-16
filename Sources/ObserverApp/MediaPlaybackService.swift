import AppKit
import Foundation

struct MediaPlaybackSnapshot: Equatable {
    let source: String
    let state: String
    let title: String?
    let artist: String?
    let album: String?
    let volume: Int?

    var identityKey: String {
        [source, state, title ?? "", artist ?? "", album ?? "", volume.map(String.init) ?? ""].joined(separator: "|")
    }

    var trackIdentityKey: String { [source, title ?? "", artist ?? "", album ?? ""].joined(separator: "|") }

    var eventPayload: [String: String] {
        var payload = [
            "source": source,
            "state": state,
            "sensor_tier": "native_system_media",
            "track_identified": (title?.isEmpty == false) ? "true" : "false"
        ]
        if let title, !title.isEmpty { payload["title"] = title }
        if let artist, !artist.isEmpty { payload["artist"] = artist }
        if let album, !album.isEmpty { payload["album"] = album }
        if let volume { payload["volume"] = "\(volume)" }
        return payload
    }

    var sourceForObserverResume: String? {
        state == "playing" ? source : nil
    }
}

/// Deliberately uses the system media route only. AppleScript against Music,
/// Spotify and browser tabs was both permission-heavy and able to crash the app.
struct MediaPlaybackService {
    struct ProbeResult {
        let snapshot: MediaPlaybackSnapshot?
        let failures: [String]
    }

    func currentPlayback() -> MediaPlaybackSnapshot? { currentPlaybackProbe().snapshot }

    func currentPlaybackProbe() -> ProbeResult {
        // MPNowPlayingInfoCenter exposes this app's publication channel, not a
        // reliable cross-app reader. We never pretend it can identify YouTube.
        ProbeResult(snapshot: nil, failures: [])
    }

    func pauseAllKnownSources() -> [String] {
        postSystemMediaKey(.playPause) ? ["System Media Key"] : []
    }

    func pauseSystemMediaKey() -> String? {
        postSystemMediaKey(.playPause) ? "System Media Key" : nil
    }

    func resumeSources(_ sources: [String]) -> [String] {
        guard sources.contains("System Media Key") else { return [] }
        return postSystemMediaKey(.playPause) ? ["System Media Key"] : []
    }

    static func parseOutput(_ output: String) -> MediaPlaybackSnapshot? {
        let parts = output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        func value(_ index: Int) -> String? {
            guard parts.indices.contains(index), !parts[index].isEmpty else { return nil }
            return parts[index]
        }
        return MediaPlaybackSnapshot(
            source: parts[0], state: parts[1], title: value(2), artist: value(3), album: value(4), volume: value(5).flatMap(Int.init)
        )
    }

    private enum MediaKey: Int32 { case playPause = 16 }

    private func postSystemMediaKey(_ key: MediaKey) -> Bool {
        // NX_SYSDEFINED media events are routed by macOS to the current player.
        // No process automation, browser scripting, or accessibility prompt.
        let downData = Int((key.rawValue << 16) | (0xA << 8))
        let upData = Int((key.rawValue << 16) | (0xB << 8))
        guard let down = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8, data1: downData, data2: -1
        ), let up = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8, data1: upData, data2: -1
        ) else { return false }
        guard let downEvent = down.cgEvent, let upEvent = up.cgEvent else {
            return false
        }
        downEvent.post(tap: CGEventTapLocation.cghidEventTap)
        upEvent.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    }
}
