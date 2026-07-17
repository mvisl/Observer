import Foundation

enum WorkNodeType: String, Codable {
    case stream
    case project
    case workstream
    case deliverable
    case objective
    case intention
    case attempt
    case step
}

enum WorkNodeStatus: String, Codable {
    case open
    case active
    case waiting
    case blocked
    case done
    case abandoned
    case archived
    case paused
    case completed
    case unknown
}

struct WorkNode: Codable, Identifiable {
    let id: UUID
    let nodeType: WorkNodeType
    let parentId: UUID?
    let generatedName: String
    let userName: String?
    let status: WorkNodeStatus
    let goal: String?
    let expectedOutcome: String?
    let doneCriterion: String?
    let completionEvidence: [UUID]
    let artifactIds: [UUID]
    let entityIds: [UUID]
    let topicIds: [UUID]
    let firstSeenAt: Date
    let lastSeenAt: Date
    let confidence: Double
    let userLocked: Bool
    let source: String
    let pipelineVersion: String
    let createdAt: Date
    let updatedAt: Date
}

enum AssignmentSource: String, Codable {
    case localHeuristic
    case localModel
    case user
    case imported
}

struct EpisodeWorkAssignment: Codable, Identifiable {
    let id: UUID
    let episodeId: UUID
    let projectId: UUID?
    let workstreamId: UUID?
    let intentionId: UUID?
    let attemptId: UUID?
    let confidence: Double
    let assignedBy: AssignmentSource
    let reasonCodes: [String]
    let evidenceIds: [UUID]
    let alternativeAssignmentIds: [UUID]
    let version: Int
    let supersedesId: UUID?
    let isCurrent: Bool
    let userLocked: Bool
    let createdAt: Date
    let pipelineVersion: String
}

struct WorkHierarchyBuilder {
    struct Report {
        let projectMarkdown: String
        let timelineMarkdown: String
        let diagnostics: [String: String]
    }

    private struct Path: Hashable {
        var project: String?
        var workstream: String?
        var intention: String?
        var attempt: String?
    }

    private struct Assignment {
        var path: Path
        var confidences: [WorkNodeType: Double]
        var reasonCodes: Set<String>
    }

    private struct Leaf {
        var path: Path
        var seconds: Double = 0
        var agentSeconds: Double = 0
        var intervals: [String] = []
        var apps: Set<String> = []
        var activityKinds: Set<String> = []
        var episodeTopics: Set<String> = []
        var reasonCodes: Set<String> = []
        var confidences: [WorkNodeType: Double] = [:]
        var resources: Set<Resource> = []
        var engagementModes: Set<String> = []
        var actors: Set<String> = []
    }

    private struct Resource: Hashable {
        let kind: String
        let label: String
        let url: String?
    }

    private let iso = ISO8601DateFormatter()

    func build(
        threads: [ObserverEvent],
        slices: [ObserverEvent],
        episodes: [ObserverEvent],
        actionItems: [ObserverEvent],
        artifacts: [ObserverEvent] = []
    ) -> Report {
        let threadsByID = Dictionary(threads.compactMap { event -> (String, ObserverEvent)? in
            guard let id = event.payload["activity_thread_id"], !id.isEmpty else {
                return nil
            }
            return (id, event)
        }, uniquingKeysWith: { _, newer in newer })
        let episodesByID = Dictionary(episodes.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, newer in newer })
        var leaves: [Path: Leaf] = [:]
        var timelineRows: [(start: Date, end: Date, path: Path, apps: [String])] = []
        var globalUnassignedSeconds: Double = 0

        for slice in slices {
            let agency = AgencyAttributionBuilder().applyFallback(to: slice)
            let seconds = agency.userAttributableSeconds
            let agentSeconds = agency.agentExecutionSeconds
            guard seconds > 0 else {
                if agentSeconds <= 0 {
                    continue
                }
                globalUnassignedSeconds += 0
                continue
            }
            let thread = slice.payload["activity_thread_id"].flatMap { threadsByID[$0] }
            let episode = slice.payload["episode_event_id"].flatMap { episodesByID[$0] }
            let relatedArtifacts = relatedArtifacts(for: slice, episode: episode, allArtifacts: artifacts)
            let assignment = assign(slice: slice, thread: thread, episode: episode, artifacts: relatedArtifacts)

            guard assignment.path.project != nil else {
                globalUnassignedSeconds += seconds
                continue
            }

            var leaf = leaves[assignment.path] ?? Leaf(path: assignment.path)
            leaf.seconds += seconds
            leaf.agentSeconds += agentSeconds
            leaf.engagementModes.insert(agency.engagementMode.rawValue)
            leaf.actors.insert(agency.primaryActor.rawValue)
            leaf.intervals.append(timeRange(slice))
            leaf.apps.formUnion(apps(from: episode))
            leaf.apps.formUnion(apps(from: thread))
            if let kind = slice.payload["activity_kind"], !kind.isEmpty {
                leaf.activityKinds.insert(kind)
            }
            if let topic = episode?.payload["topic"] ?? episode?.payload["dominant_context"], !topic.isEmpty {
                leaf.episodeTopics.insert(safeReportText(topic))
            }
            leaf.reasonCodes.formUnion(assignment.reasonCodes)
            leaf.resources.formUnion(relatedArtifacts.compactMap(resource(from:)))
            for (level, confidence) in assignment.confidences {
                leaf.confidences[level] = max(leaf.confidences[level] ?? 0, confidence)
            }
            leaves[assignment.path] = leaf

            if let start = date(from: slice.payload["started_at"] ?? iso.string(from: slice.timestamp)),
               let end = date(from: slice.payload["ended_at"] ?? iso.string(from: slice.timestamp)) {
                timelineRows.append((start, end, assignment.path, Array(leaf.apps).sorted()))
            }
        }

        let projectMarkdown = renderProjects(leaves: Array(leaves.values), globalUnassignedSeconds: globalUnassignedSeconds)
        let timelineMarkdown = renderTimeline(rows: timelineRows)
        return Report(
            projectMarkdown: projectMarkdown,
            timelineMarkdown: timelineMarkdown,
            diagnostics: [
                "work_hierarchy_leaf_nodes": "\(leaves.count)",
                "work_hierarchy_global_unassigned_seconds": String(format: "%.1f", globalUnassignedSeconds)
            ]
        )
    }

    private func assign(
        slice: ObserverEvent,
        thread: ObserverEvent?,
        episode: ObserverEvent?,
        artifacts: [ObserverEvent]
    ) -> Assignment {
        let text = combinedContext(slice: slice, thread: thread, episode: episode)
            + " "
            + artifacts.compactMap { artifact in
                [artifact.payload["display_name"], artifact.payload["resource_domain"]]
                    .compactMap { $0 }
                    .joined(separator: " ")
            }.joined(separator: " ")
        let lower = text.lowercased()
        var reasons = Set<String>()
        var confidences: [WorkNodeType: Double] = [:]

        let jiraArtifact = artifacts.first { $0.payload["kind"] == "jira_issue" }

        let project: String?
        if jiraArtifact != nil {
            project = "Work"
            confidences[.project] = 0.96
            reasons.insert("project_from_jira_anchor")
        } else if lower.contains("oboard") || lower.contains("obord") || lower.contains("onboard") || lower.contains("dashboard") || lower.contains("дашбор") || lower.contains("дешбор") {
            project = "Oboard"
            confidences[.project] = lower.contains("oboard") || lower.contains("obord") ? 0.94 : 0.72
            reasons.insert("project_from_artifact_or_topic")
        } else if lower.contains("observer") || lower.contains("пилюл") || lower.contains("инсайт") || lower.contains("daily activity report") {
            project = "Observer"
            confidences[.project] = 0.92
            reasons.insert("project_from_product_terms")
        } else if lower.contains("libertex") || lower.contains("trading robot") || lower.contains("робот") {
            project = "Libertex / trading robot"
            confidences[.project] = 0.86
            reasons.insert("project_from_product_terms")
        } else if let generated = thread?.payload["generated_name"], !generated.isEmpty {
            project = safeReportText(generated)
            confidences[.project] = 0.52
            reasons.insert("project_from_existing_thread")
        } else {
            project = nil
        }

        guard let project else {
            return Assignment(path: Path(), confidences: confidences, reasonCodes: reasons)
        }

        let workstream = inferWorkstream(project: project, lower: lower, jiraArtifact: jiraArtifact)
        if workstream != nil {
            confidences[.workstream] = 0.78
            reasons.insert("workstream_from_artifact_or_content")
        }

        let intention = inferIntention(
            project: project,
            workstream: workstream,
            lower: lower,
            episode: episode,
            jiraArtifact: jiraArtifact
        )
        if intention != nil {
            confidences[.intention] = 0.70
            reasons.insert("intention_from_expected_result")
        }

        let attempt = inferAttempt(project: project, intention: intention, lower: lower, slice: slice, episode: episode)
        if attempt != nil {
            confidences[.attempt] = 0.76
            reasons.insert("attempt_from_method_or_tool_transfer")
        }

        return Assignment(
            path: Path(
                project: project,
                workstream: workstream,
                intention: intention ?? "Намерение пока не определено",
                attempt: attempt
            ),
            confidences: confidences,
            reasonCodes: reasons
        )
    }

    private func inferWorkstream(project: String, lower: String, jiraArtifact: ObserverEvent? = nil) -> String? {
        if project == "Work", jiraArtifact != nil {
            if lower.contains("libertex") || lower.contains("fxclub") || lower.contains("what to buy") || lower.contains("whattobuy") {
                return "Libertex"
            }
            return "Рабочая задача"
        }
        if lower.contains("dashboard") || lower.contains("дашбор") || lower.contains("дешбор") {
            return "Dashboard"
        }
        if project == "Oboard"
            && (
                lower.contains("prototype")
                || lower.contains("прототип")
                || lower.contains("figma")
                || lower.contains("codex")
            ) {
            return "Dashboard"
        }
        if project == "Observer" {
            if lower.contains("daily activity report") || lower.contains("отчёт") || lower.contains("report") {
                return "Daily Activity Report"
            }
            if lower.contains("пилюл") || lower.contains("widget") {
                return "Пилюля"
            }
            if lower.contains("camera") || lower.contains("камера") || lower.contains("gaze") || lower.contains("взгляд") {
                return "Камера и внимание"
            }
            return "Brain / insights"
        }
        return nil
    }

    private func inferIntention(
        project: String,
        workstream: String?,
        lower: String,
        episode: ObserverEvent?,
        jiraArtifact: ObserverEvent? = nil
    ) -> String? {
        if let jiraArtifact {
            let key = jiraArtifact.payload["canonical_key"]?.replacingOccurrences(of: "jira:", with: "") ?? "Jira"
            let title = jiraArtifact.payload["display_name"] ?? "Рабочая задача"
            let cleaned = title
                .replacingOccurrences(of: key, with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? key : "\(key) — \(cleaned)"
        }
        if project == "Oboard" && workstream == "Dashboard" {
            if lower.contains("вит") || lower.contains("call") || lower.contains("созвон") {
                return "Уточнить требования к Dashboard"
            }
            return "Улучшение Dashboard"
        }
        if project == "Observer" {
            if workstream == "Daily Activity Report" {
                return "Перестроить отчёт вокруг задач"
            }
            if lower.contains("санитар") || lower.contains("инсайт") || lower.contains("пилюл") {
                return "Повысить качество инсайтов пилюли"
            }
            if lower.contains("камера") || lower.contains("camera") || lower.contains("взгляд") {
                return "Улучшить распознавание внимания"
            }
        }
        if episode?.payload["episode_kind"] == "call" || episode?.payload["episode_kind"] == "meeting" {
            return "Согласовать рабочий вопрос"
        }
        return nil
    }

    private func inferAttempt(project: String, intention: String?, lower: String, slice: ObserverEvent, episode: ObserverEvent?) -> String? {
        let kind = (episode?.payload["episode_kind"] ?? slice.payload["activity_kind"] ?? "").lowercased()
        if lower.contains("codex") && lower.contains("figma") {
            return "Попытка подключить Codex к Figma"
        }
        if kind.contains("call") || kind.contains("meeting") || lower.contains("созвон") || lower.contains("вит") {
            return "Обсуждение текущего решения"
        }
        if lower.contains("prototype") || lower.contains("прототип") {
            return lower.contains("chatgpt") || lower.contains("claude") || lower.contains("ai")
                ? "Генерация прототипа через AI"
                : "Обновление прототипа"
        }
        if lower.contains("chatgpt") || lower.contains("claude") || lower.contains("gemini") || kind.contains("ai") {
            return project == "Oboard" ? "Генерация варианта через AI" : "ИИ-итерация и проверка формулировок"
        }
        if lower.contains("figma") {
            return "Ручная проверка в Figma"
        }
        if lower.contains("github") || lower.contains("xcode") || lower.contains("code") || lower.contains("terminal") {
            return "Код / интеграция"
        }
        if intention != nil && (lower.contains("telegram") || lower.contains("viber") || lower.contains("whatsapp")) {
            return "Коммуникация по задаче"
        }
        return nil
    }

    private func combinedContext(slice: ObserverEvent, thread: ObserverEvent?, episode: ObserverEvent?) -> String {
        [
            thread?.payload["generated_name"],
            thread?.payload["dominant_context"],
            slice.payload["activity_kind"],
            episode?.payload["episode_kind"],
            episode?.payload["dominant_context"],
            episode?.payload["topic"],
            episode?.payload["apps"]
        ].compactMap { $0 }.joined(separator: " ")
    }

    private func relatedArtifacts(
        for slice: ObserverEvent,
        episode: ObserverEvent?,
        allArtifacts: [ObserverEvent]
    ) -> [ObserverEvent] {
        let sourceIDs = Set(
            eventIDs(in: slice.payload["source_event_ids"])
                + eventIDs(in: episode?.payload["source_event_ids"])
                + eventIDs(in: episode?.payload["trace_event_ids"])
        )
        let linked = allArtifacts.filter { artifact in
            !sourceIDs.isDisjoint(with: Set(eventIDs(in: artifact.payload["source_event_ids"])))
        }
        if !linked.isEmpty {
            return linked
        }
        // Fabric artifacts can be materialized moments after a slice closes. A
        // narrow temporal fallback preserves the link without merging a whole day.
        return allArtifacts.filter { abs($0.timestamp.timeIntervalSince(slice.timestamp)) <= 20 * 60 }
    }

    private func eventIDs(in value: String?) -> [String] {
        (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resource(from artifact: ObserverEvent) -> Resource? {
        guard let kind = artifact.payload["kind"],
              let rawLabel = artifact.payload["display_name"],
              !rawLabel.isEmpty
        else {
            return nil
        }
        return Resource(
            kind: kind,
            label: safeReportText(rawLabel),
            url: artifact.payload["resource_url"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func renderProjects(leaves: [Leaf], globalUnassignedSeconds: Double) -> String {
        guard !leaves.isEmpty else {
            if globalUnassignedSeconds > 0 {
                return "- Глобально не назначено — \(formatDuration(globalUnassignedSeconds))"
            }
            return "- Нет контекстных срезов для иерархии задач."
        }

        let byProject = Dictionary(grouping: leaves) { $0.path.project ?? "Глобально не назначено" }
        var sections: [String] = []
        for project in byProject.keys.sorted() {
            let projectLeaves = byProject[project] ?? []
            let projectSeconds = projectLeaves.map(\.seconds).reduce(0, +)
            sections.append("### \(safeReportText(project)) — \(formatDuration(projectSeconds))")
            let byWorkstream = Dictionary(grouping: projectLeaves) { $0.path.workstream ?? "Неуточнённая работа" }
            for workstream in byWorkstream.keys.sorted() {
                let workstreamLeaves = byWorkstream[workstream] ?? []
                let workstreamSeconds = workstreamLeaves.map(\.seconds).reduce(0, +)
                sections.append("#### \(safeReportText(workstream)) — \(formatDuration(workstreamSeconds))")
                let byIntention = Dictionary(grouping: workstreamLeaves) { $0.path.intention ?? "Намерение пока не определено" }
                for intention in byIntention.keys.sorted() {
                    let intentionLeaves = byIntention[intention] ?? []
                    let intentionSeconds = intentionLeaves.map(\.seconds).reduce(0, +)
                    sections.append("##### \(safeReportText(intention)) — \(formatDuration(intentionSeconds))")
                    for leaf in intentionLeaves.sorted(by: { ($0.path.attempt ?? "") < ($1.path.attempt ?? "") }) {
                        let attempt = leaf.path.attempt ?? "Неуточнённый шаг"
                        sections.append("""
                        - \(safeReportText(attempt)) — \(formatDuration(leaf.seconds))
                          Агентское выполнение/ожидание: \(formatDuration(leaf.agentSeconds))
                          Интервалы: \(leaf.intervals.prefix(5).joined(separator: ", "))
                          Приложения: \(safeReportText(leaf.apps.sorted().joined(separator: " → ")))
                          Роли: \(leaf.actors.sorted().joined(separator: ", ")) / \(leaf.engagementModes.sorted().joined(separator: ", "))
                          ActivityKind: \(leaf.activityKinds.sorted().joined(separator: ", "))
                          Ресурсы: \(resourceLine(leaf.resources))
                          Confidence: \(confidenceLine(leaf.confidences))
                          Причины связи: \(leaf.reasonCodes.sorted().joined(separator: ", "))
                        """)
                    }
                }
            }
        }
        if globalUnassignedSeconds > 0 {
            sections.append("### Глобально не назначено — \(formatDuration(globalUnassignedSeconds))")
        }
        return sections.joined(separator: "\n")
    }

    private func renderTimeline(rows: [(start: Date, end: Date, path: Path, apps: [String])]) -> String {
        guard !rows.isEmpty else {
            return "- Нет хронологии по задачам."
        }
        return rows.sorted { $0.start < $1.start }.map { row in
            """
            - \(shortTime(row.start))-\(shortTime(row.end))
              \(pathLine(row.path))
              Инструменты: \(safeReportText(row.apps.isEmpty ? "unknown" : row.apps.joined(separator: " → ")))
            """
        }.joined(separator: "\n")
    }

    private func pathLine(_ path: Path) -> String {
        [path.project, path.workstream, path.intention, path.attempt]
            .compactMap { $0 }
            .map(safeReportText)
            .joined(separator: " → ")
    }

    private func confidenceLine(_ confidences: [WorkNodeType: Double]) -> String {
        let order: [WorkNodeType] = [.project, .workstream, .intention, .attempt]
        let parts = order.compactMap { level -> String? in
            guard let confidence = confidences[level] else {
                return nil
            }
            return "\(level.rawValue) \(String(format: "%.2f", confidence))"
        }
        return parts.isEmpty ? "unknown" : parts.joined(separator: "; ")
    }

    private func resourceLine(_ resources: Set<Resource>) -> String {
        guard !resources.isEmpty else {
            return "не найдены"
        }
        return resources
            .sorted { $0.label < $1.label }
            .prefix(6)
            .map { resource in
                let label = "\(resourceKindLabel(resource.kind)): \(resource.label)"
                guard let url = resource.url else { return label }
                return "[\(label)](\(url))"
            }
            .joined(separator: "; ")
    }

    private func resourceKindLabel(_ kind: String) -> String {
        switch kind {
        case "jira_issue": return "Jira"
        case "figma_file": return "Figma"
        case "document": return "Документ"
        default: return "Ссылка"
        }
    }

    private func apps(from event: ObserverEvent?) -> [String] {
        guard let apps = event?.payload["apps"], !apps.isEmpty else {
            return []
        }
        return apps
            .components(separatedBy: CharacterSet(charactersIn: "|,"))
            .flatMap { $0.components(separatedBy: " -> ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func timeRange(_ event: ObserverEvent) -> String {
        let start = event.payload["started_at"] ?? iso.string(from: event.timestamp)
        let end = event.payload["ended_at"] ?? start
        return "\(shortTime(start))-\(shortTime(end))"
    }

    private func shortTime(_ isoString: String) -> String {
        guard let date = date(from: isoString) else {
            return "??:??"
        }
        return shortTime(date)
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func date(from isoString: String) -> Date? {
        iso.date(from: isoString)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes) мин"
        }
        return "\(minutes / 60) ч \(minutes % 60) мин"
    }

    private func safeReportText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\[secret:[^\]]+\]"#, with: "[secret]", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "[url]", options: .regularExpression)
            .replacingOccurrences(of: #"chatgpt\.com/c/\S+"#, with: "ChatGPT thread", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpassword\b(\s+\S+){0,5}"#, with: "[sensitive topic]", options: .regularExpression)
    }
}
