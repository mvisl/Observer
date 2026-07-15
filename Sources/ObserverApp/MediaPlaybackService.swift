import Foundation

struct MediaPlaybackSnapshot: Equatable {
    let source: String
    let state: String
    let title: String?
    let artist: String?
    let album: String?
    let volume: Int?

    var identityKey: String {
        [
            source,
            state,
            title ?? "",
            artist ?? "",
            album ?? "",
            volume.map(String.init) ?? ""
        ].joined(separator: "|")
    }

    var trackIdentityKey: String {
        [
            source,
            title ?? "",
            artist ?? "",
            album ?? ""
        ].joined(separator: "|")
    }

    var eventPayload: [String: String] {
        var payload: [String: String] = [
            "source": source,
            "state": state
        ]
        if let title, !title.isEmpty {
            payload["title"] = title
        }
        if let artist, !artist.isEmpty {
            payload["artist"] = artist
        }
        if let album, !album.isEmpty {
            payload["album"] = album
        }
        if let volume {
            payload["volume"] = "\(volume)"
        }
        return payload
    }

    var sourceForObserverResume: String? {
        guard state == "playing" else {
            return nil
        }
        switch source {
        case "Music", "Spotify", "YouTube Chrome", "YouTube Safari":
            return source
        default:
            return nil
        }
    }
}

struct MediaPlaybackService {
    struct ProbeResult {
        let snapshot: MediaPlaybackSnapshot?
        let failures: [String]
    }

    func currentPlayback() -> MediaPlaybackSnapshot? {
        currentPlaybackProbe().snapshot
    }

    func currentPlaybackProbe() -> ProbeResult {
        var failures: [String] = []
        let snapshots = [
            currentAppleMusicPlayback(failures: &failures),
            currentYouTubePlaybackInChrome(failures: &failures),
            currentYouTubePlaybackInSafari(failures: &failures),
            currentSpotifyPlayback(failures: &failures)
        ].compactMap { $0 }

        return ProbeResult(
            snapshot: snapshots.first { $0.state == "playing" } ?? snapshots.first,
            failures: failures
        )
    }

    func pauseAllKnownSources() -> [String] {
        [
            pauseAppleMusic(),
            pauseSpotify(),
            pauseYouTubeInChrome(),
            pauseYouTubeInSafari()
        ].compactMap { $0 }
    }

    func resumeSources(_ sources: [String]) -> [String] {
        sources.compactMap { source in
            switch source {
            case "Music":
                return resumeAppleMusic()
            case "Spotify":
                return resumeSpotify()
            case "YouTube Chrome":
                return resumeYouTubeInChrome()
            case "YouTube Safari":
                return resumeYouTubeInSafari()
            default:
                return nil
            }
        }
    }

    private func currentAppleMusicPlayback(failures: inout [String]) -> MediaPlaybackSnapshot? {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return ""
        end tell
        tell application "Music"
            set playerState to player state as string
            set playerVolume to sound volume as integer
            if playerState is "stopped" then return "Music|stopped||||" & playerVolume
            set trackName to ""
            set trackArtist to ""
            set trackAlbum to ""
            try
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
            end try
            return "Music|" & playerState & "|" & trackName & "|" & trackArtist & "|" & trackAlbum & "|" & playerVolume
        end tell
        """
        return runPlaybackScript(script, label: "Music playback", failures: &failures)
    }

    private func currentSpotifyPlayback(failures: inout [String]) -> MediaPlaybackSnapshot? {
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return ""
        end tell
        tell application "Spotify"
            set playerState to player state as string
            set playerVolume to sound volume as integer
            if playerState is "stopped" then return "Spotify|stopped||||" & playerVolume
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            return "Spotify|" & playerState & "|" & trackName & "|" & trackArtist & "|" & trackAlbum & "|" & playerVolume
        end tell
        """
        return runPlaybackScript(script, label: "Spotify playback", failures: &failures)
    }

    private func currentYouTubePlaybackInChrome(failures: inout [String]) -> MediaPlaybackSnapshot? {
        let script = """
        tell application "System Events"
            if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com" then
                        set playbackInfo to execute javascript "(function(){ const videos = Array.from(document.querySelectorAll('video')); const video = videos.find(v => !v.paused) || videos[0]; if (!video) return ''; const heading = document.querySelector('h1 yt-formatted-string, h1.title, h1'); const rawTitle = ((heading && heading.innerText) || document.title || '').replace(/\\|/g, '/').replace(/ - YouTube$/i, '').trim(); const state = video.paused ? 'paused' : 'playing'; const volume = Math.round((video.volume || 0) * 100); return 'YouTube Chrome|' + state + '|' + rawTitle + '||YouTube|' + volume; })();"
                        if playbackInfo is not "" then return playbackInfo
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        return runPlaybackScript(script, label: "YouTube Chrome playback", failures: &failures)
    }

    private func currentYouTubePlaybackInSafari(failures: inout [String]) -> MediaPlaybackSnapshot? {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com" then
                        set playbackInfo to do JavaScript "(function(){ const videos = Array.from(document.querySelectorAll('video')); const video = videos.find(v => !v.paused) || videos[0]; if (!video) return ''; const heading = document.querySelector('h1 yt-formatted-string, h1.title, h1'); const rawTitle = ((heading && heading.innerText) || document.title || '').replace(/\\|/g, '/').replace(/ - YouTube$/i, '').trim(); const state = video.paused ? 'paused' : 'playing'; const volume = Math.round((video.volume || 0) * 100); return 'YouTube Safari|' + state + '|' + rawTitle + '||YouTube|' + volume; })();" in t
                        if playbackInfo is not "" then return playbackInfo
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """
        return runPlaybackScript(script, label: "YouTube Safari playback", failures: &failures)
    }

    private func runPlaybackScript(
        _ source: String,
        label: String,
        failures: inout [String]
    ) -> MediaPlaybackSnapshot? {
        guard let output = runScript(source, label: label, failures: &failures) else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Self.parseOutput(trimmed)
    }

    private func pauseAppleMusic() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return ""
        end tell
        tell application "Music"
            if player state is playing then
                pause
                return "Music"
            end if
        end tell
        return ""
        """
        return runActionScript(script)
    }

    private func pauseSpotify() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return ""
        end tell
        tell application "Spotify"
            if player state is playing then
                pause
                return "Spotify"
            end if
        end tell
        return ""
        """
        return runActionScript(script)
    }

    private func pauseYouTubeInChrome() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
            set didPause to false
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com" then
                        set pauseInfo to execute javascript "(function(){ let didPause = false; document.querySelectorAll('video').forEach(v => { if (!v.paused) { v.pause(); didPause = true; } }); return didPause ? 'paused' : ''; })();"
                        if pauseInfo is "paused" then set didPause to true
                    end if
                end repeat
            end repeat
            if didPause then return "YouTube Chrome"
        end tell
        return ""
        """
        return runActionScript(script)
    }

    private func pauseYouTubeInSafari() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            set didPause to false
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com" then
                        set pauseInfo to do JavaScript "(function(){ let didPause = false; document.querySelectorAll('video').forEach(v => { if (!v.paused) { v.pause(); didPause = true; } }); return didPause ? 'paused' : ''; })();" in t
                        if pauseInfo is "paused" then set didPause to true
                    end if
                end repeat
            end repeat
            if didPause then return "YouTube Safari"
        end tell
        return ""
        """
        return runActionScript(script)
    }

    private func resumeAppleMusic() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return ""
        end tell
        tell application "Music"
            play
            return "Music"
        end tell
        """
        return runActionScript(script)
    }

    private func resumeSpotify() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return ""
        end tell
        tell application "Spotify"
            play
            return "Spotify"
        end tell
        """
        return runActionScript(script)
    }

    private func resumeYouTubeInChrome() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Google Chrome") then return ""
        end tell
        tell application "Google Chrome"
            set didResume to false
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com" then
                        set resumeInfo to execute javascript "(function(){ let didResume = false; document.querySelectorAll('video').forEach(v => { if (v.paused) { v.play(); didResume = true; } }); return didResume ? 'resumed' : ''; })();"
                        if resumeInfo is "resumed" then set didResume to true
                    end if
                end repeat
            end repeat
            if didResume then return "YouTube Chrome"
        end tell
        return ""
        """
        return runActionScript(script)
    }

    private func resumeYouTubeInSafari() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell
        tell application "Safari"
            set didResume to false
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "youtube.com" then
                        set resumeInfo to do JavaScript "(function(){ let didResume = false; document.querySelectorAll('video').forEach(v => { if (v.paused) { v.play(); didResume = true; } }); return didResume ? 'resumed' : ''; })();" in t
                        if resumeInfo is "resumed" then set didResume to true
                    end if
                end repeat
            end repeat
            if didResume then return "YouTube Safari"
        end tell
        return ""
        """
        return runActionScript(script)
    }

    private func runActionScript(_ source: String) -> String? {
        var failures: [String] = []
        guard let output = runScript(source, label: "media action", failures: &failures) else {
            return nil
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func runScript(
        _ source: String,
        label: String,
        failures: inout [String]
    ) -> String? {
        var error: NSDictionary?
        if let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue {
            return output
        }

        if let error {
            failures.append("\(label): NSAppleScript \(Self.errorSummary(error))")
        } else {
            failures.append("\(label): NSAppleScript returned no output")
        }

        if let output = runOSAScript(source) {
            return output
        }

        failures.append("\(label): osascript fallback returned no output")
        return nil
    }

    private func runOSAScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func errorSummary(_ error: NSDictionary) -> String {
        let number = error[NSAppleScript.errorNumber] ?? "unknown"
        let message = error[NSAppleScript.errorMessage] ?? "unknown"
        return "\(number) \(message)"
    }

    static func parseOutput(_ output: String) -> MediaPlaybackSnapshot? {
        let parts = output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else {
            return nil
        }

        return MediaPlaybackSnapshot(
            source: parts[0],
            state: parts[1],
            title: parts[2].isEmpty ? nil : parts[2],
            artist: parts[3].isEmpty ? nil : parts[3],
            album: parts[4].isEmpty ? nil : parts[4],
            volume: parts.count >= 6 ? Int(parts[5]) : nil
        )
    }
}
