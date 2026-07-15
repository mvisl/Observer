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
        let mediaLower = cueEvent.timestamp.addingTimeInterval(-60)
        let mediaUpper = cueEvent.timestamp.addingTimeInterval(60)
        if let media = recentEvents
            .filter({ $0.type == .mediaPlayback && $0.timestamp >= mediaLower && $0.timestamp <= mediaUpper })
            .last(where: { $0.payload["state"] == "playing" || $0.payload["audio_active"] == "true" }) {
            payload["competing_evidence"] = "media_playback"
            payload["attribution"] = "ambiguous_content_vs_media"
            payload["media_state"] = "audio_active"
            payload["media_event_id"] = media.id.uuidString
            payload["media_source"] = media.payload["source"]
            payload["media_title"] = media.payload["title"]
            payload["media_artist"] = media.payload["artist"]
            if media.payload["track_identified"] != "true" && (media.payload["title"] ?? "").isEmpty {
                payload["media_blind"] = "true"
                payload["confidence_cap"] = "0.50"
            }
            payload["evidence_event_ids"] = [cueEvent.id.uuidString, content.id.uuidString, media.id.uuidString].joined(separator: ",")
        }
        return payload
    }
}
