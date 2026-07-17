import Foundation

/// The durable event log is an evidence store, not a transcript store. Keep the
/// policy at the database boundary so every producer follows the same rules.
enum EventDataContract {
    static let rawContentKinds: Set<String> = ["prompt", "code", "doc"]

    static func sanitizedPayload(for event: ObserverEvent) -> [String: String] {
        var payload = event.payload.mapValues(PrivacyRedactor.redact)
        let kind = payload["content_kind"] ?? ""
        if event.type == .contentContext, !rawContentKinds.contains(kind) {
            payload.removeValue(forKey: "raw_fragment")
            payload.removeValue(forKey: "raw_text")
            payload.removeValue(forKey: "selected_text")
            payload.removeValue(forKey: "focused_element_value")
        }
        if event.type == .contentContext || event.type == .episode,
           (payload["source_event_ids"] ?? "").isEmpty {
            payload["source_event_ids"] = event.id.uuidString
            payload["lineage_status"] = "self_anchored"
        }
        return payload
    }

    static func missingEvidenceReason(for event: ObserverEvent, payload: [String: String]) -> String? {
        guard requiresEvidence(event.type) else { return nil }
        let ids = payload["evidence_event_ids"] ?? payload["source_event_ids"] ?? ""
        return ids.isEmpty ? "missing_evidence_event_ids" : nil
    }

    static func requiresEvidence(_ type: ObserverEventType) -> Bool {
        switch type {
        case .behaviorCue, .boundReaction, .causalAntecedent, .causalHypothesis,
             .comparisonLayoutCandidate, .detectorFired, .fusionHypothesis,
             .hintCandidate, .interventionCandidate, .localInsight, .mediaReaction,
             .routineCandidate:
            return true
        default:
            return false
        }
    }
}
