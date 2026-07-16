import Foundation

struct DailyActivityReportBuilder {
    private let iso = ISO8601DateFormatter()

    func build(events: [ObserverEvent], day: Date = Date()) -> (markdown: String, diagnostics: [String: String]) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? day
        let dayEvents = events.filter { $0.timestamp >= startOfDay && $0.timestamp < endOfDay }
        let observations = ContextFabricBuilder().observations(from: dayEvents, now: day)
        let slices = dayEvents.filter { $0.type == .contextSlice }
        let assignments = dayEvents.filter { $0.type == .episodeThreadAssignment }
        let threads = dayEvents.filter { $0.type == .activityThread }
        let episodes = dayEvents.filter { $0.type == .episode }
        let artifacts = dayEvents.filter { $0.type == .artifactIdentity }
        let meetingEpisodes = episodes.filter { $0.payload["episode_kind"] == "meeting" }
        let callEpisodes = episodes.filter { $0.payload["episode_kind"] == "call" }
        let actionItems = dayEvents.filter { $0.type == .actionItem }
        let objectPresenceEvents = dayEvents.filter { $0.type == .objectPresence }

        let observedSeconds = observedTime(from: dayEvents)
        let activeSeconds = sum(slices, key: "active_seconds")
        let assignedSeconds = slices
            .filter { $0.payload["assignment_state"] == "assigned" && $0.payload["activity_thread_id"]?.isEmpty == false }
            .compactMap { Double($0.payload["active_seconds"] ?? "") }
            .reduce(0, +)
        let unassignedSeconds = max(0, activeSeconds - assignedSeconds)
        let coverage = observedSeconds > 0 ? min(1, activeSeconds / observedSeconds) : 0

        let confidenceBuckets = confidenceDistribution(assignments)
        let workHierarchy = WorkHierarchyBuilder().build(
            threads: threads,
            slices: slices,
            episodes: episodes,
            actionItems: actionItems,
            artifacts: artifacts
        )
        let threadSections = activityThreadSections(threads: threads, slices: slices, episodes: episodes)
        let timeline = timelineLines(slices: slices)
        let unassigned = unassignedLines(slices: slices)
        var diagnostics: [String: String] = [
            "date": dateString(startOfDay),
            "observations": "\(observations.count)",
            "camera_evidence": "\(dayEvents.filter { $0.type == .cameraEvidence }.count)",
            "object_presence": "\(objectPresenceEvents.count)",
            "episodes": "\(episodes.count)",
            "meeting_episodes": "\(meetingEpisodes.count)",
            "call_episodes": "\(callEpisodes.count)",
            "action_items": "\(actionItems.count)",
            "activity_threads": "\(threads.count)",
            "assigned_intervals": "\(slices.filter { $0.payload["assignment_state"] == "assigned" }.count)",
            "unassigned_intervals": "\(slices.filter { $0.payload["assignment_state"] != "assigned" }.count)",
            "observed_seconds": String(format: "%.1f", observedSeconds),
            "active_seconds": String(format: "%.1f", activeSeconds),
            "assigned_active_seconds": String(format: "%.1f", assignedSeconds),
            "unassigned_active_seconds": String(format: "%.1f", unassignedSeconds),
            "coverage": String(format: "%.2f", coverage),
            "confidence_high": "\(confidenceBuckets.high)",
            "confidence_medium": "\(confidenceBuckets.medium)",
            "confidence_low": "\(confidenceBuckets.low)",
            "tracker_actions_enabled": "false",
            "tracker_external_sending_enabled": "false",
            "predictor_activation": "blocked_by_readiness_gate",
            "source_event_ids": dayEvents.suffix(300).map(\.id.uuidString).joined(separator: ","),
            "pipeline_version": ObserverPipeline.version
        ]
        diagnostics.merge(workHierarchy.diagnostics) { _, new in new }

        let markdown = """
        # Daily Activity Report

        ## Summary

        - Date: \(dateString(startOfDay))
        - Observed time: \(formatDuration(observedSeconds))
        - Active time: \(formatDuration(activeSeconds))
        - Attributable active time: \(formatDuration(activeSeconds))
        - Assigned active time: \(formatDuration(assignedSeconds))
        - Unassigned active time: \(formatDuration(unassignedSeconds))
        - Coverage: \(Int((coverage * 100).rounded()))%
        - Activity threads: \(threads.count)
        - Meetings: \(meetingEpisodes.count); calls: \(callEpisodes.count); action items: \(actionItems.count)
        - Confidence: high \(confidenceBuckets.high), medium \(confidenceBuckets.medium), low \(confidenceBuckets.low)

        ## Проекты и задачи

        \(workHierarchy.projectMarkdown)

        ## Хронология по задачам

        \(workHierarchy.timelineMarkdown)

        ## Activity Threads

        \(threadSections.isEmpty ? "- No assigned activity threads yet." : threadSections)

        ## Technical Timeline

        \(timeline.isEmpty ? "- No context slices yet." : timeline)

        ## Meetings And Calls

        \(meetingCallLines(episodes: meetingEpisodes + callEpisodes, actionItems: actionItems))

        ## Unassigned

        \(unassigned.isEmpty ? "- No unassigned active time in current slices." : unassigned)

        ## Diagnostics

        - Observations: \(observations.count)
        - Camera evidence: \(dayEvents.filter { $0.type == .cameraEvidence }.count)
        - Object presence evidence: \(objectPresenceEvents.count)
        - Episodes: \(episodes.count)
        - Assignments: \(assignments.count)
        - Double-count guard: context slices are episode-bounded and non-overlapping.
        - Tracker sends nothing outside the machine and creates no actions.
        - Predictor remains gated by readiness.
        """

        return (markdown, diagnostics)
    }

    private func activityThreadSections(threads: [ObserverEvent], slices: [ObserverEvent], episodes: [ObserverEvent]) -> String {
        threads.compactMap { thread in
            let threadID = thread.payload["activity_thread_id"] ?? ""
            let threadSlices = slices.filter { $0.payload["activity_thread_id"] == threadID }
            let seconds = sum(threadSlices, key: "active_seconds")
            guard seconds > 0 else {
                return nil
            }
            let kinds = Dictionary(grouping: threadSlices, by: { $0.payload["activity_kind"] ?? "unknown" })
                .map { "\($0.key): \(formatDuration(sum($0.value, key: "active_seconds")))" }
                .sorted()
                .joined(separator: "; ")
            let apps = episodes
                .filter { episode in threadSlices.contains { $0.payload["episode_event_id"] == episode.id.uuidString } }
                .compactMap { $0.payload["apps"] }
                .joined(separator: " | ")
            return """
            - \(safeReportText(thread.payload["generated_name"] ?? "Unnamed thread"))
              Active: \(formatDuration(seconds)); episodes: \(threadSlices.count); confidence \(thread.payload["confidence"] ?? "?")
              Kinds: \(kinds.isEmpty ? "unknown" : kinds)
              Apps: \(safeReportText(apps.isEmpty ? "unknown" : apps))
            """
        }.joined(separator: "\n")
    }

    private func timelineLines(slices: [ObserverEvent]) -> String {
        slices.sorted { $0.timestamp < $1.timestamp }.map { slice in
            let state = slice.payload["assignment_state"] == "assigned" ? "assigned" : "unassigned"
            return "- \(timeRange(slice)): \(state), \(slice.payload["activity_kind"] ?? "unknown"), \(formatDuration(Double(slice.payload["active_seconds"] ?? "") ?? 0))"
        }.joined(separator: "\n")
    }

    private func meetingCallLines(episodes: [ObserverEvent], actionItems: [ObserverEvent]) -> String {
        guard !episodes.isEmpty || !actionItems.isEmpty else {
            return "- No meeting or call episodes yet."
        }
        let episodeLines = episodes.sorted { $0.timestamp < $1.timestamp }.map { episode in
            let kind = episode.payload["episode_kind"] ?? "communication"
            let topic = safeReportText(episode.payload["topic"] ?? episode.payload["dominant_context"] ?? "unknown")
            let duration = formatDuration(Double(episode.payload["duration_seconds"] ?? "") ?? 0)
            return "- \(kind): \(topic), \(duration)"
        }
        let itemLines = actionItems.prefix(8).map { item in
            "- action: \(safeReportText(item.payload["text"] ?? "follow up")), addressee \(item.payload["addressee"] ?? "?")"
        }
        return (episodeLines + itemLines).joined(separator: "\n")
    }

    private func unassignedLines(slices: [ObserverEvent]) -> String {
        slices
            .filter { $0.payload["assignment_state"] != "assigned" || $0.payload["activity_thread_id"]?.isEmpty != false }
            .map { slice in
                "- \(timeRange(slice)): \(formatDuration(Double(slice.payload["active_seconds"] ?? "") ?? 0)) — insufficient content or conflicting thread candidates."
            }
            .joined(separator: "\n")
    }

    private func observedTime(from events: [ObserverEvent]) -> Double {
        let boundaries = events.filter { $0.type == .observingStarted || $0.type == .observingPaused || $0.type == .sessionBoundary }
        guard let first = boundaries.first?.timestamp ?? events.first?.timestamp,
              let last = events.last?.timestamp,
              last > first
        else {
            return 0
        }
        return last.timeIntervalSince(first)
    }

    private func confidenceDistribution(_ events: [ObserverEvent]) -> (high: Int, medium: Int, low: Int) {
        let values = events.map(\.confidence)
        return (
            values.filter { $0 >= 0.75 }.count,
            values.filter { $0 >= 0.45 && $0 < 0.75 }.count,
            values.filter { $0 < 0.45 }.count
        )
    }

    private func timeRange(_ event: ObserverEvent) -> String {
        let start = event.payload["started_at"] ?? iso.string(from: event.timestamp)
        let end = event.payload["ended_at"] ?? start
        return "\(shortTime(start))-\(shortTime(end))"
    }

    private func shortTime(_ isoString: String) -> String {
        guard let date = iso.date(from: isoString) else {
            return "??:??"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func sum(_ events: [ObserverEvent], key: String) -> Double {
        events.compactMap { Double($0.payload[key] ?? "") }.reduce(0, +)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func safeReportText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\[secret:[^\]]+\]"#, with: "[secret]", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "[url]", options: .regularExpression)
            .replacingOccurrences(of: #"chatgpt\.com/c/\S+"#, with: "ChatGPT thread", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bpassword\b(\s+\S+){0,5}"#, with: "[sensitive topic]", options: .regularExpression)
    }
}
