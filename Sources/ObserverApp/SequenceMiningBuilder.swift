import Foundation

struct SequencePattern: Equatable {
    let antecedentChain: [String]
    let outcome: String
    let support: Int
    let confidenceStat: Double
    let exampleEventIDs: [String]

    var payload: [String: String] {
        [
            "antecedent_chain": antecedentChain.joined(separator: " > "),
            "outcome": outcome,
            "support": "\(support)",
            "confidence_stat": String(format: "%.3f", confidenceStat),
            "example_event_ids": exampleEventIDs.joined(separator: ","),
            "validation_state": "shadow_unvalidated"
        ]
    }
}

struct SequenceMiningBuilder {
    let settings: ObserverSettings.CognitiveSettings

    func mine(events: [ObserverEvent]) -> [SequencePattern] {
        let segments = splitByObservationGaps(events)
        var counts: [String: (support: Int, examples: [String], outcome: String)] = [:]
        var targetCount = 0

        for segment in segments {
            let result = mineSegment(segment)
            targetCount += result.targetCount
            for (key, value) in result.counts {
                var current = counts[key] ?? (support: 0, examples: [], outcome: value.outcome)
                current.support += value.support
                current.examples.append(contentsOf: value.examples)
                counts[key] = current
            }
        }

        return counts.compactMap { key, value in
            guard value.support >= settings.sequenceMinimumSupport else {
                return nil
            }
            let parts = key.components(separatedBy: " => ")
            let chain = parts.first?.components(separatedBy: " > ") ?? []
            let confidence = min(0.95, Double(value.support) / Double(max(targetCount, 1)))
            guard confidence >= settings.sequenceMinimumConfidence else {
                return nil
            }
            return SequencePattern(
                antecedentChain: chain,
                outcome: value.outcome,
                support: value.support,
                confidenceStat: confidence,
                exampleEventIDs: Array(value.examples.prefix(5))
            )
        }
        .sorted { $0.support > $1.support }
    }

    private func mineSegment(_ events: [ObserverEvent]) -> (
        counts: [String: (support: Int, examples: [String], outcome: String)],
        targetCount: Int
    ) {
        let symbols = events.map(symbol)
        let targetIndexes = symbols.indices.filter { index in
            isTarget(symbols[index])
        }

        var counts: [String: (support: Int, examples: [String], outcome: String)] = [:]
        for targetIndex in targetIndexes {
            let outcome = symbols[targetIndex]
            let lower = max(0, targetIndex - 8)
            let preceding = Array(symbols[lower..<targetIndex])
            for length in 2...5 where preceding.count >= length {
                let chain = Array(preceding.suffix(length))
                let key = chain.joined(separator: " > ") + " => " + outcome
                var current = counts[key] ?? (support: 0, examples: [], outcome: outcome)
                current.support += 1
                current.examples.append(events[targetIndex].id.uuidString)
                counts[key] = current
            }
        }

        return (counts, targetIndexes.count)
    }

    private func splitByObservationGaps(_ events: [ObserverEvent]) -> [[ObserverEvent]] {
        var segments: [[ObserverEvent]] = []
        var current: [ObserverEvent] = []

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if event.type == .observationGap {
                if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                continue
            }
            current.append(event)
        }

        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    private func symbol(_ event: ObserverEvent) -> String {
        switch event.type {
        case .cognitiveState:
            return "state:\(event.payload["state"] ?? "unknown")"
        case .appFocus:
            return "focus:\(coarseApp(event.payload["app_name"] ?? event.appID ?? "unknown"))"
        case .contentContext:
            return "content:\(event.payload["content_kind"] ?? "unknown")"
        case .behaviorCue:
            return "cue:\(event.payload["cue"] ?? "unknown")"
        case .detectorFired:
            return "detector:\(event.payload["detector"] ?? "unknown")"
        case .inputActivity:
            let idle = Double(event.payload["seconds_since_any_input"] ?? "") ?? 0
            return idle > 120 ? "input:idle" : "input:active"
        default:
            return event.type.rawValue
        }
    }

    private func isTarget(_ symbol: String) -> Bool {
        symbol == "state:flow"
            || symbol == "state:avoidance"
            || symbol.contains("detector:stuck")
            || symbol == "input:idle"
    }

    private func coarseApp(_ app: String) -> String {
        let lower = app.lowercased()
        if lower.contains("figma") { return "design" }
        if lower.contains("xcode") || lower.contains("terminal") || lower.contains("cursor") { return "code" }
        if lower.contains("telegram") || lower.contains("whatsapp") || lower.contains("mail") { return "communication" }
        if lower.contains("chrome") || lower.contains("safari") { return "browser" }
        return "other"
    }
}
