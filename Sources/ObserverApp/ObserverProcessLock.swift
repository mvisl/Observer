import Foundation
import Darwin

/// Prevents two bundles (for example /Applications and a development build)
/// from observing the same desktop at once and duplicating summaries.
final class ObserverProcessLock {
    private let url: URL
    private var ownsLock = false

    init(directory: URL) {
        url = directory.appendingPathComponent("observer-process.lock")
    }

    func acquire() throws -> Bool {
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 0,
           kill(pid, 0) == 0 {
            return false
        }
        // O_EXCL makes the final claim atomic. Two app bundles can otherwise
        // both pass the stale-lock check and start observing at once.
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        if descriptor >= 0 {
            let data = Data("\(getpid())\n".utf8)
            _ = data.withUnsafeBytes { write(descriptor, $0.baseAddress, data.count) }
            close(descriptor)
            ownsLock = true
            return true
        }

        guard errno == EEXIST else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        // A stale file can be left by a crash between the liveness check and
        // the atomic claim. Remove only after confirming the recorded PID died.
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           pid > 0,
           kill(pid, 0) == 0 {
            return false
        }
        try? FileManager.default.removeItem(at: url)
        return try acquire()
    }

    func release() {
        guard ownsLock else { return }
        try? FileManager.default.removeItem(at: url)
        ownsLock = false
    }

    deinit { release() }
}

/// A crash leaves this state behind. The next launch delays sensor startup so a
/// broken configuration cannot create a tight crash/restart loop.
final class ObserverRestartBackoff {
    private struct State: Codable {
        var launches: [Date]
    }

    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) {
        url = directory.appendingPathComponent("observer-restart-state.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func recordLaunchAndBackoff(now: Date = Date()) -> TimeInterval {
        let recentCutoff = now.addingTimeInterval(-10 * 60)
        var launches = (try? readState().launches) ?? []
        launches = launches.filter { $0 >= recentCutoff }
        launches.append(now)
        write(State(launches: launches))

        // The first normal launch starts immediately. Repeated unclean launches
        // delay only sensor startup, capped at five minutes.
        let restartCount = max(0, launches.count - 1)
        guard restartCount > 0 else { return 0 }
        return min(5 * 60, pow(2, Double(restartCount - 1)) * 5)
    }

    func recordGracefulShutdown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func readState() throws -> State {
        let data = try Data(contentsOf: url)
        return try decoder.decode(State.self, from: data)
    }

    private func write(_ state: State) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
