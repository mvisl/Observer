import Foundation

struct BoundReactionBuilder {
    func build(
        cueEvent: ObserverEvent,
        recentEvents: [ObserverEvent],
        windowSeconds: TimeInterval = 5
    ) -> [String: String]? {
        guard cueEvent.type == .behaviorCue else {
            return nil
        }

        let lower = cueEvent.timestamp.addingTimeInterval(-windowSeconds)
        let upper = cueEvent.timestamp.addingTimeInterval(windowSeconds)
        guard let content = recentEvents
            .filter({ $0.type == .contentContext && $0.timestamp >= lower && $0.timestamp <= upper })
            .last
        else {
            return nil
        }

        let entityID = content.payload["source_entity_id"]
        let topic = content.payload["topic"]
        guard entityID != nil || topic != nil else {
            return nil
        }

        var payload: [String: String] = [
            "cue": cueEvent.payload["cue"] ?? "unknown",
            "content_kind": content.payload["content_kind"] ?? "unknown",
            "evidence_event_ids": [cueEvent.id.uuidString, content.id.uuidString].joined(separator: ",")
        ]
        if let interpretation = cueEvent.payload["interpretation"] {
            payload["interpretation"] = interpretation
        }
        if let entityID {
            payload["entity_id"] = entityID
        }
        if let topic {
            payload["topic"] = topic
        }
        if let sentiment = content.payload["sentiment"] {
            payload["sentiment"] = sentiment
        }
        return payload
    }
}
