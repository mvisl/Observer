import Foundation

struct DashboardArtifactInspectorBuilder {
    func build(
        artifacts: [ObserverEvent],
        threads: [ObserverEvent],
        segments: [DashboardTimelineSegment],
        corrections: [ObserverEvent] = []
    ) -> [DashboardArtifactRelation] {
        let registry = ArtifactRegistry().entries(from: artifacts)
        let threadEvidence = Dictionary(uniqueKeysWithValues: threads.map { thread in
            let id = thread.payload["activity_thread_id"] ?? thread.id.uuidString
            return (id, Set(eventIDs(thread.payload["source_event_ids"]) + [thread.id.uuidString]))
        })
        return registry.flatMap { entry -> [DashboardArtifactRelation] in
            let entryEvidence = Set(entry.evidenceEventIds)
            let matchingSegments = segments.filter { !Set($0.sourceEventIds).isDisjoint(with: entryEvidence) }
            let linkedThreadIDs = threadEvidence.compactMap { id, evidence in
                !evidence.isDisjoint(with: Set(entry.evidenceEventIds)) ? id : nil
            }
            let taskIDs = linkedThreadIDs.isEmpty ? ["unassigned"] : linkedThreadIDs
            return taskIDs.compactMap { taskID in
                let relevantSegments = taskID == "unassigned"
                    ? matchingSegments
                    : matchingSegments.filter { $0.threadId == taskID }
                let relatedEpisodes = Set(relevantSegments.compactMap(\.episodeId)).count
                let relationID = "\(taskID):\(entry.canonicalKey)"
                let override = correction(for: relationID, corrections: corrections)
                guard override.isBound else { return nil }
                return DashboardArtifactRelation(
                    id: relationID,
                    taskId: taskID,
                    role: override.isPrimary ? .primaryArtifact : role(for: entry.kind),
                    artifactKind: entry.kind,
                    sourceIcon: sourceIcon(for: entry.kind),
                    title: override.title ?? entry.title,
                    roleSummary: roleSummary(for: entry.kind),
                    directLink: entry.directLink,
                    lastUsedAt: entry.lastUsedAt,
                    relatedEpisodeCount: relatedEpisodes,
                    confidence: entry.confidence,
                    aliases: entry.aliases,
                    evidenceEventIds: entry.evidenceEventIds
                )
            }
        }
        // Do not turn loosely observed material into a task artifact. The inspector
        // only shows relations that have a concrete activity-thread lineage.
        .filter { $0.taskId != "unassigned" }
        .sorted {
            if $0.taskId != $1.taskId { return $0.taskId < $1.taskId }
            if $0.role.sortOrder != $1.role.sortOrder { return $0.role.sortOrder < $1.role.sortOrder }
            return $0.lastUsedAt > $1.lastUsedAt
        }
    }

    private func correction(for relationID: String, corrections: [ObserverEvent]) -> ArtifactOverride {
        corrections
            .filter { $0.payload["artifact_id"] == relationID }
            .sorted { $0.timestamp < $1.timestamp }
            .reduce(into: ArtifactOverride()) { result, event in
                switch event.payload["command_type"] {
                case "artifact_unbind": result.isBound = false
                case "artifact_bind": result.isBound = true
                case "artifact_primary": result.isPrimary = true
                case "artifact_rename": result.title = nonEmpty(event.payload["title"])
                default: break
                }
            }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func role(for kind: String) -> DashboardArtifactRole {
        switch kind {
        case "jira_issue": .primaryArtifact
        case "figma_file", "figma_page", "figma_node": .currentResult
        case "chat_thread", "email_thread": .communication
        case "repository", "branch", "source_file", "terminal_session", "codex_session": .implementation
        case "document", "spreadsheet": .decisionInput
        case "browser_page", "web_application": .reference
        default: .reference
        }
    }

    private func sourceIcon(for kind: String) -> String {
        switch kind {
        case "jira_issue": "Jira"
        case "figma_file", "figma_page", "figma_node": "Figma"
        case "chat_thread", "email_thread": "Chat"
        case "repository", "branch", "source_file", "terminal_session", "codex_session": "Code"
        case "document", "spreadsheet": "Doc"
        default: "Web"
        }
    }

    private func roleSummary(for kind: String) -> String {
        switch role(for: kind) {
        case .primaryArtifact: "Главный рабочий якорь: задаёт предмет и границы этой работы."
        case .currentResult: "Текущий результат, в котором проверяются и применяются решения."
        case .decisionInput: "Материал, из которого извлекаются критерии и входные данные для решения."
        case .communication: "Обсуждение, из которого в задачу пришли требования или обратная связь."
        case .implementation: "Среда, в которой решение превращается в работающий результат."
        case .reference: "Справочный материал, к которому возвращались для проверки или сравнения."
        case .previousVersion: "Предыдущая версия, с которой сопоставляется текущий результат."
        }
    }

    private func eventIDs(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private struct ArtifactOverride {
        var isBound = true
        var isPrimary = false
        var title: String?
    }
}
