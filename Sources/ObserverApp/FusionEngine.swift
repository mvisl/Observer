import Foundation

struct FusionDecision: Equatable {
    let publicationState: String
    let surfaceAllowed: Bool
    let confidence: Double
    let channels: [String]
    let evidenceEventIDs: [String]
    let payload: [String: String]
}

struct FusionEngine {
    private let windowSeconds: TimeInterval

    init(windowSeconds: TimeInterval = 120) {
        self.windowSeconds = windowSeconds
    }

    func decide(candidate: ObserverEvent, recentEvents: [ObserverEvent]) -> FusionDecision {
        let candidateChannel = channel(for: candidate) ?? "unknown"
        let lowerBound = candidate.timestamp.addingTimeInterval(-windowSeconds)
        let upperBound = candidate.timestamp.addingTimeInterval(windowSeconds)

        let evidence = recentEvents
            .filter { event in
                event.id != candidate.id
                    && event.timestamp >= lowerBound
                    && event.timestamp <= upperBound
            }
            .compactMap { event -> (channel: String, event: ObserverEvent)? in
                guard let channel = channel(for: event), channel != candidateChannel else {
                    return nil
                }
                return (channel, event)
            }

        var channelSet = Set([candidateChannel])
        evidence.forEach { channelSet.insert($0.channel) }
        let channels = channelSet.sorted()
        let publishable = channels.filter { $0 != "unknown" }.count >= 2
        let supportingEvents = evidence.prefix(6).map(\.event)

        var payload: [String: String] = [
            "candidate_event_id": candidate.id.uuidString,
            "candidate_type": candidate.type.rawValue,
            "candidate_channel": candidateChannel,
            "channels": channels.joined(separator: ","),
            "evidence_event_ids": supportingEvents.map { $0.id.uuidString }.joined(separator: ","),
            "evidence_channels": supportingEvents.compactMap { channel(for: $0) }.joined(separator: ","),
            "publication_state": publishable ? "publishable" : "shadow",
            "surface_allowed": publishable ? "true" : "false",
            "window_seconds": String(format: "%.0f", windowSeconds)
        ]

        if let cue = candidate.payload["cue"] {
            payload["cue"] = cue
        }
        if let interpretation = candidate.payload["interpretation"] {
            payload["interpretation"] = interpretation
        }

        // A chat can explain a reaction, but it must not count as a second independent
        // channel when the candidate itself came from text. It is attribution evidence only.
        if let context = freshestCommunicationContext(for: candidate, events: recentEvents) {
            payload["causal_context_event_id"] = context.id.uuidString
            payload["causal_context_kind"] = context.payload["content_kind"] ?? "message"
            payload["causal_context_sentiment"] = context.payload["sentiment"] ?? "neutral"
            if let topic = context.payload["topic"], !topic.isEmpty {
                payload["causal_context_topic"] = topic
            }
            payload["causal_attribution"] = "fresh_communication_context"
            payload["evidence_event_ids"] = (supportingEvents.map { $0.id.uuidString } + [context.id.uuidString])
                .uniqued()
                .joined(separator: ",")
        }

        let confidence = publishable
            ? min(0.95, candidate.confidence + 0.18)
            : min(candidate.confidence, 0.35)

        return FusionDecision(
            publicationState: publishable ? "publishable" : "shadow",
            surfaceAllowed: publishable,
            confidence: confidence,
            channels: channels,
            evidenceEventIDs: supportingEvents.map { $0.id.uuidString },
            payload: payload
        )
    }

    private func channel(for event: ObserverEvent) -> String? {
        switch event.type {
        case .attention:
            return event.payload["face_present"] == "true" ? "camera" : nil
        case .behaviorCue:
            return behaviorCueChannel(event.payload)
        case .contentContext, .writingContext, .ocrContext, .screenContext:
            return "content"
        case .inputActivity, .typingRhythm, .mouseDynamics:
            return "input"
        case .scrollProfile:
            return "scroll"
        case .mediaPlayback, .mediaReaction:
            return "media"
        case .objectPresence:
            return "object"
        default:
            return nil
        }
    }

    private func behaviorCueChannel(_ payload: [String: String]) -> String {
        let cue = [payload["cue"], payload["interpretation"]]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if cue.contains("smile")
            || cue.contains("posture")
            || cue.contains("concentration")
            || cue.contains("difficulty")
            || cue.contains("yawn")
            || cue.contains("energy_drop")
            || cue.contains("fatigue") {
            return "camera"
        }
        if cue.contains("writing") || cue.contains("text") || cue.contains("tone") {
            return "content"
        }
        if cue.contains("media") || cue.contains("music") {
            return "media"
        }
        return "input"
    }

    private func freshestCommunicationContext(
        for candidate: ObserverEvent,
        events: [ObserverEvent]
    ) -> ObserverEvent? {
        guard ["frustration_candidate", "friction_candidate"].contains(candidate.payload["cue"] ?? "") else {
            return nil
        }

        let lowerBound = candidate.timestamp.addingTimeInterval(-45)
        let upperBound = candidate.timestamp.addingTimeInterval(10)
        return events
            .filter { event in
                event.type == .contentContext
                    && event.timestamp >= lowerBound
                    && event.timestamp <= upperBound
                    && ["message", "email"].contains(event.payload["content_kind"])
                    && ["neg", "mixed"].contains(event.payload["sentiment"])
            }
            .max(by: { $0.timestamp < $1.timestamp })
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
