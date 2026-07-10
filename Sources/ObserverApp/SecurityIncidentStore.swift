import Foundation

struct SecurityIncidentSummary: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let photoURL: URL?
    let screenshotURL: URL?
    let transcriptURL: URL?
    let audioURL: URL?
    let severity: String
    let summary: String
    let payload: [String: String]
    var seen: Bool
    var reviewAvailable: Bool

    init(
        id: UUID,
        createdAt: Date,
        photoURL: URL?,
        screenshotURL: URL?,
        transcriptURL: URL?,
        audioURL: URL?,
        severity: String,
        summary: String,
        payload: [String: String],
        seen: Bool,
        reviewAvailable: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.photoURL = photoURL
        self.screenshotURL = screenshotURL
        self.transcriptURL = transcriptURL
        self.audioURL = audioURL
        self.severity = severity
        self.summary = summary
        self.payload = payload
        self.seen = seen
        self.reviewAvailable = reviewAvailable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        screenshotURL = try container.decodeIfPresent(URL.self, forKey: .screenshotURL)
        transcriptURL = try container.decodeIfPresent(URL.self, forKey: .transcriptURL)
        audioURL = try container.decodeIfPresent(URL.self, forKey: .audioURL)
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? "amber"
        summary = try container.decode(String.self, forKey: .summary)
        payload = try container.decode([String: String].self, forKey: .payload)
        seen = try container.decodeIfPresent(Bool.self, forKey: .seen) ?? false
        reviewAvailable = try container.decodeIfPresent(Bool.self, forKey: .reviewAvailable) ?? false
    }
}

final class SecurityIncidentStore {
    private let directory: URL
    private let metadataDirectory: URL
    private let encoder = JSONEncoder.observerEncoder
    private let decoder = JSONDecoder.observerDecoder

    init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("security-incidents", isDirectory: true)
        self.metadataDirectory = self.directory.appendingPathComponent("metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    var directoryURL: URL {
        directory
    }

    func record(payload: [String: String], jpegData: Data?) throws -> SecurityIncidentSummary {
        cleanupExpiredSeenIncidents()

        let id = UUID()
        let now = Date()
        let dayDirectory = directory.appendingPathComponent(Self.dayKey(for: now), isDirectory: true)
        try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)

        let photoURL: URL?
        if let jpegData {
            let url = dayDirectory.appendingPathComponent("\(id.uuidString).jpg")
            try jpegData.write(to: url, options: .atomic)
            photoURL = url
        } else {
            photoURL = nil
        }

        let screenshotCandidateURL = dayDirectory.appendingPathComponent("\(id.uuidString).screen.png")
        let screenshotURL = SecurityScreenshotCapture.capture(to: screenshotCandidateURL)
            ? screenshotCandidateURL
            : nil

        let transcriptURL = dayDirectory.appendingPathComponent("\(id.uuidString).transcript.txt")
        let transcript = Self.transcriptPlaceholder(
            from: payload,
            photoURL: photoURL,
            screenshotURL: screenshotURL
        )
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)

        let severity = Self.severity(from: payload)
        let summary = Self.summary(from: payload, photoURL: photoURL)
        let incident = SecurityIncidentSummary(
            id: id,
            createdAt: now,
            photoURL: photoURL,
            screenshotURL: screenshotURL,
            transcriptURL: transcriptURL,
            audioURL: nil,
            severity: severity,
            summary: summary,
            payload: payload,
            seen: false,
            reviewAvailable: false
        )
        try write(incident)
        return incident
    }

    func unseenCount() -> Int {
        (try? all().filter { $0.reviewAvailable && !$0.seen }.count) ?? 0
    }

    func latestUnseen() -> SecurityIncidentSummary? {
        try? all()
            .filter { $0.reviewAvailable && !$0.seen }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func latestReviewable() -> SecurityIncidentSummary? {
        try? all()
            .filter(\.reviewAvailable)
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func releasePendingForReview() -> Int {
        guard let incidents = try? all() else {
            return 0
        }

        var released = 0
        for var incident in incidents where !incident.seen && !incident.reviewAvailable {
            incident.reviewAvailable = true
            try? write(incident)
            released += 1
        }
        return released
    }

    func markAllSeen() {
        guard let incidents = try? all() else {
            return
        }
        for var incident in incidents where !incident.seen {
            incident.seen = true
            try? write(incident)
        }
    }

    func cleanupExpiredSeenIncidents(now: Date = Date(), ttl: TimeInterval = 86_400) {
        guard let incidents = try? all() else {
            return
        }

        for incident in incidents where incident.seen && now.timeIntervalSince(incident.createdAt) >= ttl {
            if let photoURL = incident.photoURL {
                try? FileManager.default.removeItem(at: photoURL)
            }
            if let screenshotURL = incident.screenshotURL {
                try? FileManager.default.removeItem(at: screenshotURL)
            }
            if let transcriptURL = incident.transcriptURL {
                try? FileManager.default.removeItem(at: transcriptURL)
            }
            if let audioURL = incident.audioURL {
                try? FileManager.default.removeItem(at: audioURL)
            }
            let metadataURL = metadataDirectory.appendingPathComponent("\(incident.id.uuidString).json")
            try? FileManager.default.removeItem(at: metadataURL)
        }
    }

    private func all() throws -> [SecurityIncidentSummary] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: metadataDirectory,
            includingPropertiesForKeys: nil
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? decoder.decode(SecurityIncidentSummary.self, from: data)
            }
    }

    private func write(_ incident: SecurityIncidentSummary) throws {
        let url = metadataDirectory.appendingPathComponent("\(incident.id.uuidString).json")
        let data = try encoder.encode(incident)
        try data.write(to: url, options: .atomic)
    }

    private static func summary(from payload: [String: String], photoURL: URL?) -> String {
        let app = payload["app_name"] ?? "неизвестное приложение"
        let idle = payload["seconds_since_any_input"].flatMap(Double.init).map { "\(Int($0))с без ввода" }
            ?? "был простой"
        let photo = photoURL == nil ? "фото нет" : "фото сохранено"
        return "После отсутствия появился человек; \(idle); открыто: \(app); \(photo)."
    }

    private static func severity(from payload: [String: String]) -> String {
        if payload["owner_related_audio"] == "true" || payload["owner_related_context"] == "true" {
            return "red"
        }
        return "amber"
    }

    private static func transcriptPlaceholder(
        from payload: [String: String],
        photoURL: URL?,
        screenshotURL: URL?
    ) -> String {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let app = payload["app_name"] ?? "unknown"
        let idle = payload["seconds_since_any_input"] ?? "unknown"
        let photo = photoURL?.path ?? "none"
        let screenshot = screenshotURL?.path ?? "none"
        return """
        Observer security incident
        Created: \(createdAt)
        App: \(app)
        Idle seconds before appearance: \(idle)
        Photo: \(photo)
        Screen: \(screenshot)

        Transcript: not recorded yet. Local STT/audio capture is reserved for the next step.
        Policy: local protective incident, visible app indicators, no cloud upload.
        """
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private enum SecurityScreenshotCapture {
    static func capture(to url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", url.path]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }
}
