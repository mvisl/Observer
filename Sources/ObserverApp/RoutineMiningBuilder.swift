import Foundation

/// A repeated, observable tool chain. It is deliberately not an automation:
/// the collector only records evidence that a next step repeatedly follows a
/// preceding one. Promotion to a suggestion and any execution require their
/// own explicit user-confirmed stages.
struct RoutineCandidate: Equatable {
    let routineKey: String
    let triggerAction: String
    let nextAction: String
    let completionCount: Int
    let medianTransitionSeconds: Double
    let confidence: Double
    let evidenceEventIDs: [UUID]
    let state: String

    var payload: [String: String] {
        [
            "routine_key": routineKey,
            "trigger_action": triggerAction,
            "next_action": nextAction,
            "completion_count": "\(completionCount)",
            "median_transition_seconds": String(format: "%.1f", medianTransitionSeconds),
            "confidence": String(format: "%.2f", confidence),
            "candidate_state": state,
            "proposal_state": "not_proposed",
            "execution_state": "disabled",
            "automation_policy": "observe_only",
            "source_event_ids": evidenceEventIDs.map(\.uuidString).joined(separator: ","),
            "pipeline_version": ArchitectureV2.pipelineVersion
        ]
    }
}

struct RoutineMiningBuilder {
    let settings: ObserverSettings.RoutineMiningSettings

    func build(events: [ObserverEvent]) -> [RoutineCandidate] {
        guard settings.enabled else { return [] }

        let actions = deduplicatedActions(from: events)
        var matches: [String: [RoutineMatch]] = [:]

        for index in actions.indices {
            let trigger = actions[index]
            guard trigger.kind == .giphyCapture else { continue }
            guard index + 1 < actions.count else { continue }
            guard let next = actions[(index + 1)...].first(where: {
                $0.timestamp.timeIntervalSince(trigger.timestamp) <= settings.maximumTransitionSeconds
                    && $0.kind == .resizeTool
            }) else {
                continue
            }
            let key = "\(trigger.kind.rawValue)>\(next.kind.rawValue)"
            matches[key, default: []].append(.init(trigger: trigger, next: next))
        }

        return matches.compactMap { key, occurrences in
            let independent = deduplicateOccurrences(occurrences)
            guard independent.count >= settings.minimumCompletions else { return nil }
            let latencies = independent.map { $0.next.timestamp.timeIntervalSince($0.trigger.timestamp) }.sorted()
            let median = latencies[latencies.count / 2]
            let confidence = min(0.95, 0.50 + Double(independent.count) * 0.10)
            return RoutineCandidate(
                routineKey: key,
                triggerAction: RoutineActionKind.giphyCapture.rawValue,
                nextAction: RoutineActionKind.resizeTool.rawValue,
                completionCount: independent.count,
                medianTransitionSeconds: median,
                confidence: confidence,
                evidenceEventIDs: independent.flatMap { [$0.trigger.eventID, $0.next.eventID] },
                state: "shadow_qualified"
            )
        }
        .sorted { $0.completionCount > $1.completionCount }
    }

    private func deduplicatedActions(from events: [ObserverEvent]) -> [RoutineAction] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var result: [RoutineAction] = []
        for event in sorted {
            guard let kind = actionKind(for: event) else { continue }
            if let last = result.last,
               last.kind == kind,
               event.timestamp.timeIntervalSince(last.timestamp) < 90 {
                continue
            }
            result.append(.init(kind: kind, timestamp: event.timestamp, eventID: event.id))
        }
        return result
    }

    private func deduplicateOccurrences(_ occurrences: [RoutineMatch]) -> [RoutineMatch] {
        var unique: [RoutineMatch] = []
        var seenTriggerIDs = Set<UUID>()
        for occurrence in occurrences.sorted(by: { $0.trigger.timestamp < $1.trigger.timestamp }) {
            guard seenTriggerIDs.insert(occurrence.trigger.eventID).inserted else { continue }
            unique.append(occurrence)
        }
        return unique
    }

    private func actionKind(for event: ObserverEvent) -> RoutineActionKind? {
        guard [.appFocus, .appLaunch, .contentContext, .screenContext, .ocrContext, .artifactIdentity].contains(event.type) else {
            return nil
        }
        let searchable = [
            event.appID,
            event.payload["app_name"],
            event.payload["window_title"],
            event.payload["resource_domain"],
            event.payload["url_host"],
            event.payload["resource_url"],
            event.payload["canonical_key"],
            event.payload["display_name"]
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if searchable.contains("giphy") {
            return .giphyCapture
        }
        let resizeMarkers = ["resize", "resiz", "compress", "reduceimages", "ezgif", "tinypng", "iloveimg"]
        if resizeMarkers.contains(where: searchable.contains) {
            return .resizeTool
        }
        return nil
    }
}

private enum RoutineActionKind: String {
    case giphyCapture = "capture:giphy"
    case resizeTool = "transform:resize"
}

private struct RoutineAction {
    let kind: RoutineActionKind
    let timestamp: Date
    let eventID: UUID
}

private struct RoutineMatch {
    let trigger: RoutineAction
    let next: RoutineAction
}
