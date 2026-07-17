import Foundation

struct IntentionAttributionResult {
    let anchors: [[String: String]]
    let spanAssignments: [[String: String]]
    let chainLinks: [[String: String]]
}

/// Prompts are an explicit declaration of work intent. This builder keeps that
/// declaration local, then carries it through adjacent, related attention spans.
struct IntentionAttributionBuilder {
    var anchorWindowSeconds: TimeInterval = 20 * 60
    var propagationDecay: Double = 0.7
    var chainWindowSeconds: TimeInterval = 30 * 60
    var propagationGapSeconds: TimeInterval = 20 * 60
    var calendar: Calendar = .current

    private let iso = ISO8601DateFormatter()

    func build(events: [ObserverEvent]) -> IntentionAttributionResult {
        let existingAnchorSources = Set(events
            .filter { $0.type == .intentionAnchor }
            .compactMap { $0.payload["source_event_id"] })
        let existingAssignmentKeys = Set(events
            .filter { $0.type == .spanIntentionAssignment }
            .compactMap { $0.payload["assignment_key"] })
        let existingChainKeys = Set(events
            .filter { $0.type == .chainLink }
            .compactMap { $0.payload["chain_key"] })

        let anchors = events
            .filter { $0.type == .contentContext && $0.payload["content_kind"] == "prompt" }
            .compactMap(anchorPayload(for:))
        let newAnchors = anchors.filter { existingAnchorSources.contains($0["source_event_id"] ?? "") == false }
        let spans = descriptors(for: events)
        let assignments = assignments(
            anchors: anchors,
            spans: spans,
            events: events,
            existingKeys: existingAssignmentKeys
        )
        let links = chainLinks(for: events, existingKeys: existingChainKeys)

        return .init(anchors: newAnchors, spanAssignments: assignments, chainLinks: links)
    }

    func anchorPayload(for event: ObserverEvent) -> [String: String]? {
        let raw = PrivacyRedactor.redact(event.payload["raw_fragment"] ?? event.payload["topic"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.isEmpty == false else {
            return nil
        }
        let phrase = intentPhrase(from: raw)
        guard phrase.isEmpty == false else {
            return nil
        }
        let references = taskReferences(in: [raw, event.payload["topic"] ?? ""].joined(separator: " "))
        let anchorID = StableContextID.uuidString(for: "intention-anchor:\(event.id.uuidString)")
        return [
            "intention_anchor_id": anchorID,
            "source_event_id": event.id.uuidString,
            "intent_phrase": phrase,
            "topic": event.payload["topic"] ?? phrase,
            "task_refs": references.joined(separator: ","),
            "anchor_window_seconds": String(format: "%.0f", anchorWindowSeconds),
            "source_model": "local_semantic_anchor_v0",
            "shadow_mode": "true",
            "source_event_ids": event.id.uuidString,
            "pipeline_version": ObserverPipeline.version
        ]
    }

    private func assignments(
        anchors: [[String: String]],
        spans: [Span],
        events: [ObserverEvent],
        existingKeys: Set<String>
    ) -> [[String: String]] {
        guard anchors.isEmpty == false, spans.isEmpty == false else {
            return []
        }
        let anchorModels = anchors.compactMap { payload -> Anchor? in
            guard let sourceID = payload["source_event_id"],
                  let event = events.first(where: { $0.id.uuidString == sourceID }),
                  let id = payload["intention_anchor_id"]
            else {
                return nil
            }
            return Anchor(id: id, sourceID: sourceID, timestamp: event.timestamp, phrase: payload["intent_phrase"] ?? "", references: tokenSet(payload["task_refs"] ?? ""))
        }
        guard anchorModels.isEmpty == false else {
            return []
        }

        var assigned: [Int: (anchor: Anchor, confidence: Double, assignedBy: String, sourceAssignment: String?)] = [:]
        for (index, span) in spans.enumerated() {
            guard let anchor = anchorModels
                .filter({ sameLocalDay($0.timestamp, span.midpoint) })
                .filter({ abs($0.timestamp.timeIntervalSince(span.midpoint)) <= anchorWindowSeconds })
                .max(by: { directScore(anchor: $0, span: span) < directScore(anchor: $1, span: span) })
            else {
                continue
            }
            let score = directScore(anchor: anchor, span: span)
            guard score >= 0.68 else {
                continue
            }
            assigned[index] = (anchor, score, "prompt_anchor", nil)
        }

        for index in spans.indices {
            guard assigned[index] == nil else { continue }
            let candidates = [index - 1, index + 1].compactMap { neighbor -> (Int, (anchor: Anchor, confidence: Double, assignedBy: String, sourceAssignment: String?))? in
                guard spans.indices.contains(neighbor),
                      let source = assigned[neighbor],
                      mayPropagate(from: spans[neighbor], to: spans[index], events: events)
                else { return nil }
                return (neighbor, source)
            }
            guard let inherited = candidates.max(by: { relatedness(spans[index], spans[$0.0]) < relatedness(spans[index], spans[$1.0]) }) else {
                continue
            }
            let relation = relatedness(spans[index], spans[inherited.0])
            let confidence = inherited.1.confidence * propagationDecay * relation
            guard relation >= 0.55, confidence >= 0.25 else { continue }
            assigned[index] = (
                inherited.1.anchor,
                confidence,
                "propagation",
                assignmentKey(span: spans[inherited.0], anchor: inherited.1.anchor, assignedBy: inherited.1.assignedBy)
            )
        }

        return assigned.compactMap { index, value in
            let span = spans[index]
            let key = assignmentKey(span: span, anchor: value.anchor, assignedBy: value.assignedBy)
            guard existingKeys.contains(key) == false else { return nil }
            var payload: [String: String] = [
                "assignment_key": key,
                "attention_span_id": span.id,
                "intention_anchor_id": value.anchor.id,
                "intent_phrase": value.anchor.phrase,
                "assigned_by": value.assignedBy,
                "confidence": String(format: "%.2f", value.confidence),
                "source_event_ids": [span.id, value.anchor.sourceID].joined(separator: ","),
                "pipeline_version": ObserverPipeline.version
            ]
            if let sourceAssignment = value.sourceAssignment {
                payload["propagated_from_assignment_key"] = sourceAssignment
            }
            return payload
        }
    }

    private func chainLinks(for events: [ObserverEvent], existingKeys: Set<String>) -> [[String: String]] {
        let episodes = events.filter { $0.type == .episode }.sorted { $0.timestamp < $1.timestamp }
        guard episodes.count >= 2 else { return [] }
        var output: [[String: String]] = []
        for pair in zip(episodes, episodes.dropFirst()) {
            let first = pair.0
            let second = pair.1
            guard second.timestamp.timeIntervalSince(first.timestamp) <= chainWindowSeconds,
                  let kind = chainKind(from: first, to: second)
            else { continue }
            let key = "\(first.id.uuidString):\(second.id.uuidString):\(kind)"
            guard existingKeys.contains(key) == false else { continue }
            output.append([
                "chain_key": key,
                "from_episode_event_id": first.id.uuidString,
                "to_episode_event_id": second.id.uuidString,
                "kind": kind,
                "confidence": "0.70",
                "source_event_ids": [first.id.uuidString, second.id.uuidString].joined(separator: ","),
                "pipeline_version": ObserverPipeline.version
            ])
        }
        return output
    }

    private func chainKind(from first: ObserverEvent, to second: ObserverEvent) -> String? {
        let firstText = episodeText(first)
        let secondText = episodeText(second)
        let firstCommunication = firstText.contains("telegram") || firstText.contains("whatsapp") || firstText.contains("viber") || firstText.contains("message")
        let firstPrompt = firstText.contains("chatgpt") || firstText.contains("claude") || firstText.contains("gemini") || firstText.contains("codex")
        let secondArtifact = secondText.contains("figma") || secondText.contains("jira") || secondText.contains("design") || secondText.contains("code")
        let overlap = tokenSet(firstText).intersection(tokenSet(secondText)).count
        guard overlap > 0 || (firstCommunication && secondArtifact) || (firstPrompt && secondArtifact) else { return nil }
        if firstCommunication && secondArtifact { return "communication_to_decision" }
        if firstPrompt && secondArtifact { return "prompt_to_artifact_edit" }
        if secondArtifact { return "decision_to_artifact_edit" }
        return nil
    }

    private func descriptors(for events: [ObserverEvent]) -> [Span] {
        events.filter { $0.type == .attentionSpan }.compactMap { event in
            guard let start = iso.date(from: event.payload["start"] ?? ""),
                  let end = iso.date(from: event.payload["end"] ?? ""), end >= start
            else { return nil }
            return Span(
                id: event.id.uuidString,
                start: start,
                end: end,
                apps: tokenSet(event.payload["apps"] ?? ""),
                context: tokenSet(event.payload["context_refs"] ?? "")
            )
        }.sorted { $0.start < $1.start }
    }

    /// A task may be revived tomorrow only by fresh evidence. Adjacent spans alone
    /// must never carry a label across a calendar boundary or an observation gap.
    private func mayPropagate(from source: Span, to target: Span, events: [ObserverEvent]) -> Bool {
        guard sameLocalDay(source.midpoint, target.midpoint) else {
            return false
        }
        let gap = target.start.timeIntervalSince(source.end)
        guard gap >= 0, gap <= propagationGapSeconds else {
            return false
        }
        return events.contains { event in
            event.type == .observationGap
                && event.timestamp >= source.end
                && event.timestamp <= target.start
        } == false
    }

    private func sameLocalDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private func directScore(anchor: Anchor, span: Span) -> Double {
        let temporal = max(0, 1 - abs(anchor.timestamp.timeIntervalSince(span.midpoint)) / anchorWindowSeconds)
        let overlap = Double(anchor.references.intersection(span.apps.union(span.context)).count)
        return min(0.94, 0.68 + temporal * 0.16 + min(0.10, overlap * 0.05))
    }

    private func relatedness(_ lhs: Span, _ rhs: Span) -> Double {
        let overlap = lhs.apps.union(lhs.context).intersection(rhs.apps.union(rhs.context)).count
        let temporal = max(0, 1 - abs(lhs.midpoint.timeIntervalSince(rhs.midpoint)) / (15 * 60))
        return min(1, 0.35 + min(0.45, Double(overlap) * 0.15) + temporal * 0.20)
    }

    private func assignmentKey(span: Span, anchor: Anchor, assignedBy: String) -> String {
        "\(span.id):\(anchor.id):\(assignedBy)"
    }

    private func intentPhrase(from text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .replacingOccurrences(of: #"[^\\p{L}\\p{N}\\- ]"#, with: " ", options: .regularExpression)
            .components(separatedBy: " ")
            .filter { $0.count > 1 }
            .prefix(10)
            .joined(separator: " ")
        return String(normalized.prefix(120))
    }

    private func taskReferences(in text: String) -> [String] {
        let source = text.lowercased()
        var refs = [String]()
        if let regex = try? NSRegularExpression(pattern: #"\\b[A-Z]{2,10}-\\d{2,6}\\b"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            refs.append(contentsOf: regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
        }
        let names = ["observer", "whattobuy", "oboard", "libertex", "nebius", "figma", "dashboard", "пилюл", "дашбор", "дивиденд", "карточ"]
        refs.append(contentsOf: names.filter { source.contains($0) })
        return Array(Set(refs)).sorted()
    }

    private func episodeText(_ event: ObserverEvent) -> String {
        [event.payload["topic"], event.payload["goal"], event.payload["apps"], event.payload["episode_kind"]]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private func tokenSet(_ value: String) -> Set<String> {
        let stop: Set<String> = ["что", "это", "как", "для", "или", "the", "and", "with", "from", "page", "google", "chrome", "chatgpt"]
        return Set(value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && stop.contains($0) == false })
    }

    private struct Anchor {
        let id: String
        let sourceID: String
        let timestamp: Date
        let phrase: String
        let references: Set<String>
    }

    private struct Span {
        let id: String
        let start: Date
        let end: Date
        let apps: Set<String>
        let context: Set<String>

        var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }
}
