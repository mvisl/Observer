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
        try "\(getpid())".write(to: url, atomically: true, encoding: .utf8)
        ownsLock = true
        return true
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
