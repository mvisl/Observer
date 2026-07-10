import Foundation

struct EpisodeCandidate: Equatable {
    let confidence: Double
    let payload: [String: String]
}

struct EpisodeBuilder {
    var minimumDurationSeconds: TimeInterval = 60

    func build(
        events: [ObserverEvent],
        start: Date,
        end: Date,
        outcome: String
    ) -> EpisodeCandidate? {
        let episodeEvents = events.filter { $0.timestamp >= start && $0.timestamp <= end }
        guard end.timeIntervalSince(start) >= minimumDurationSeconds, !episodeEvents.isEmpty else {
            return nil
        }

        let spans = episodeEvents.filter { $0.type == .attentionSpan }
        let focusEvents = episodeEvents.filter { $0.type == .appFocus || $0.type == .appFocusInterval }
        let apps = orderedUnique(
            (spans.flatMap { ($0.payload["apps"] ?? "").components(separatedBy: " -> ") }
                + focusEvents.compactMap { $0.payload["app_name"] ?? $0.appID })
                .filter { !$0.isEmpty }
        )
        let kind = inferKind(spans: spans, apps: apps)
        let dominant = dominantContext(spans: spans, apps: apps)
        let switchesWithinSpans = spans
            .compactMap { Int($0.payload["switches_within_span"] ?? "") }
            .reduce(0, +)
        let entities = orderedUnique(episodeEvents.compactMap { $0.payload["entity_id"] }.filter { !$0.isEmpty })
        let traceIDs = episodeEvents.suffix(40).map(\.id.uuidString).joined(separator: ",")

        var payload: [String: String] = [
            "episode_kind": kind,
            "start": ISO8601DateFormatter().string(from: start),
            "end": ISO8601DateFormatter().string(from: end),
            "duration_seconds": String(format: "%.1f", end.timeIntervalSince(start)),
            "dominant_context": dominant,
            "apps": apps.joined(separator: " -> "),
            "apps_count": "\(apps.count)",
            "span_count": "\(spans.count)",
            "switches_within_span": "\(switchesWithinSpans)",
            "outcome": outcome,
            "trace_event_ids": traceIDs,
            "shadow_mode": "true"
        ]
        if !entities.isEmpty {
            payload["entity_ids"] = entities.joined(separator: ",")
        }

        return EpisodeCandidate(
            confidence: confidence(spans: spans, apps: apps, duration: end.timeIntervalSince(start)),
            payload: payload
        )
    }

    private func dominantContext(spans: [ObserverEvent], apps: [String]) -> String {
        if let latestSpan = spans.last?.payload["span_kind"] {
            return latestSpan
        }
        return apps.first ?? "unknown"
    }

    private func inferKind(spans: [ObserverEvent], apps: [String]) -> String {
        if let latestSpanKind = spans.last?.payload["span_kind"] {
            switch latestSpanKind {
            case "ai_assisted_design":
                return "ai_assisted_work"
            case "single_context":
                return singleContextKind(apps: apps)
            default:
                return latestSpanKind
            }
        }
        return singleContextKind(apps: apps)
    }

    private func singleContextKind(apps: [String]) -> String {
        let joined = apps.joined(separator: " ").lowercased()
        if joined.contains("chatgpt") || joined.contains("claude") || joined.contains("gemini") || joined.contains("codex") {
            return "ai_assisted_work"
        }
        if joined.contains("figma") || joined.contains("sketch") {
            return "design_work"
        }
        if joined.contains("telegram") || joined.contains("whatsapp") || joined.contains("viber") || joined.contains("mail") {
            return "communication"
        }
        return apps.count > 1 ? "mixed" : "admin"
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    private func confidence(spans: [ObserverEvent], apps: [String], duration: TimeInterval) -> Double {
        min(0.9, 0.5 + min(0.2, Double(spans.count) * 0.04) + min(0.1, Double(apps.count) * 0.02) + min(0.1, duration / 3600))
    }
}
