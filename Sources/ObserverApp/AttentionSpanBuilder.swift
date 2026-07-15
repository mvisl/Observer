import Foundation

struct AttentionSpanCandidate: Equatable {
    let signature: String
    let confidence: Double
    let payload: [String: String]
}

struct AttentionSpanBuilder {
    // A span is an attention unit, not an app-focus tick. Ten-minute buckets
    // keep the log inspectable while preserving closely related tool hops.
    var maximumGapSeconds: TimeInterval = 180
    var minimumDurationSeconds: TimeInterval = 180
    var emissionBucketSeconds: TimeInterval = 600

    func build(from events: [ObserverEvent], now: Date = Date()) -> AttentionSpanCandidate? {
        let focusEvents = events
            .filter { $0.type == .appFocus }
            .suffix(80)
        guard let latest = focusEvents.last else {
            return nil
        }

        var spanEvents: [ObserverEvent] = [latest]
        var previous = latest
        for event in focusEvents.dropLast().reversed() {
            guard previous.timestamp.timeIntervalSince(event.timestamp) <= maximumGapSeconds else {
                break
            }
            spanEvents.insert(event, at: 0)
            previous = event
        }

        let apps = spanEvents.compactMap { $0.payload["app_name"] ?? $0.appID }
        let uniqueApps = orderedUnique(apps)
        let switches = max(0, spanEvents.count - 1)
        let duration = now.timeIntervalSince(spanEvents.first?.timestamp ?? latest.timestamp)

        guard switches >= 1, duration >= minimumDurationSeconds else {
            return nil
        }

        let kind = inferKind(apps: uniqueApps)
        let signature = [
            kind,
            uniqueApps.joined(separator: ">"),
            String(Int((spanEvents.first?.timestamp ?? latest.timestamp).timeIntervalSince1970 / emissionBucketSeconds))
        ].joined(separator: "|")

        let eventIDs = spanEvents.map(\.id.uuidString).joined(separator: ",")
        let payload: [String: String] = [
            "span_kind": kind,
            "start": ISO8601DateFormatter().string(from: spanEvents.first?.timestamp ?? latest.timestamp),
            "end": ISO8601DateFormatter().string(from: now),
            "duration_seconds": String(format: "%.1f", duration),
            "apps": uniqueApps.joined(separator: " -> "),
            "apps_count": "\(uniqueApps.count)",
            "switches_within_span": "\(switches)",
            "trace_event_ids": eventIDs,
            "segmentation": "attention_unit_v2_gap_under_\(Int(maximumGapSeconds))s_bucket_\(Int(emissionBucketSeconds))s"
        ]

        return AttentionSpanCandidate(
            signature: signature,
            confidence: confidence(uniqueApps: uniqueApps, switches: switches, duration: duration),
            payload: payload
        )
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

    private func inferKind(apps: [String]) -> String {
        let joined = apps.joined(separator: " ").lowercased()
        let hasAI = joined.contains("chatgpt")
            || joined.contains("claude")
            || joined.contains("gemini")
            || joined.contains("codex")
        let hasDesign = joined.contains("figma") || joined.contains("sketch")
        let hasCommunication = joined.contains("telegram")
            || joined.contains("whatsapp")
            || joined.contains("viber")
            || joined.contains("mail")
        if hasAI && hasDesign {
            return "ai_assisted_design"
        }
        if hasAI {
            return "ai_assisted_work"
        }
        if hasCommunication && apps.count == 1 {
            return "communication"
        }
        if hasDesign {
            return "design_work"
        }
        return apps.count > 1 ? "mixed" : "single_context"
    }

    private func confidence(uniqueApps: [String], switches: Int, duration: TimeInterval) -> Double {
        let appComponent = min(0.2, Double(max(0, uniqueApps.count - 1)) * 0.05)
        let switchComponent = min(0.2, Double(switches) * 0.03)
        let durationComponent = min(0.15, duration / 1200)
        return min(0.85, 0.45 + appComponent + switchComponent + durationComponent)
    }
}
