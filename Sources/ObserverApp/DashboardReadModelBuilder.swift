import Foundation

struct DashboardReadModelBuilder {
    var calendar: Calendar = .current

    func buildDaySnapshot(
        events: [ObserverEvent],
        date: Date,
        timezone: TimeZone = .current,
        diagnostics: Bool = false,
        settings: ObserverSettings = .defaults
    ) -> DayDashboardSnapshot {
        var localCalendar = calendar
        localCalendar.timeZone = timezone
        let start = localCalendar.startOfDay(for: date)
        let end = localCalendar.date(byAdding: .day, value: 1, to: start) ?? date
        let dayEvents = events.filter { $0.timestamp >= start && $0.timestamp < end }
        let slices = dayEvents.filter { $0.type == .contextSlice }
        let episodes = dayEvents.filter { $0.type == .episode }
        let threads = dayEvents.filter { $0.type == .activityThread }

        let threadNames = dictionary(from: threads, idKey: "activity_thread_id", nameKey: "generated_name")
        let timelineSegments = timelineSegments(from: slices, episodes: episodes, threadNames: threadNames)
        let observedSeconds = observedTime(from: dayEvents, fallbackEnd: end)
        let activeSeconds = timelineSegments.reduce(0) { $0 + $1.activeSeconds }
        let assignedSeconds = timelineSegments.filter { $0.state == "assigned" }.reduce(0) { $0 + $1.activeSeconds }
        let unassignedSeconds = max(0, activeSeconds - assignedSeconds)
        let sensorGapSeconds = sensorGapEvents(dayEvents).reduce(0) { $0 + duration($1, key: "duration_seconds") }
        let idleSeconds = max(0, observedSeconds - activeSeconds - sensorGapSeconds)
        let totals = DashboardTotals(
            observedSeconds: observedSeconds,
            activeSeconds: activeSeconds,
            attributableSeconds: activeSeconds,
            assignedSeconds: assignedSeconds,
            unassignedSeconds: unassignedSeconds,
            idleSeconds: idleSeconds,
            sensorGapSeconds: sensorGapSeconds,
            coverage: observedSeconds > 0 ? min(1, activeSeconds / observedSeconds) : 0
        )
        let invariantErrors = invariantErrors(totals: totals, segments: timelineSegments)
        let confidence = DashboardConfidenceDistribution(
            high: timelineSegments.filter { $0.confidence >= 0.75 }.count,
            medium: timelineSegments.filter { $0.confidence >= 0.45 && $0.confidence < 0.75 }.count,
            low: timelineSegments.filter { $0.confidence < 0.45 }.count
        )
        let threadSummaries = threadSummaries(
            threads: threads,
            segments: timelineSegments,
            episodes: episodes
        )
        let review = reviewSummary(segments: timelineSegments, sensorGaps: sensorGapEvents(dayEvents))
        let sensorSummary = sensorSummary(events: dayEvents, observedSeconds: observedSeconds, now: Date())
        let causalSummary = causalSummary(events: dayEvents)
        let readiness = ReadinessReportBuilder(settings: settings.readinessSettings)
            .readinessReport(events: events, now: date)
        let outsideGateAttributedSeconds = dayEvents
            .filter { $0.type == .contextSlice && $0.payload["outside_default_schedule"] == "true" }
            .reduce(0) { $0 + duration($1, key: "active_seconds") }
        var readinessMetrics = readiness.payload
        readinessMetrics["outside_gate_attribution_seconds"] = String(format: "%.0f", outsideGateAttributedSeconds)
        var readinessBlockers = (readiness.payload["blockers"] ?? "")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if outsideGateAttributedSeconds > 0 {
            readinessBlockers.append("attribution exists outside the configured observation window")
        }
        let readinessSummary = DashboardReadinessSummary(
            status: readiness.payload["status"] ?? "not_ready",
            blockers: readinessBlockers,
            metrics: readinessMetrics
        )

        return DayDashboardSnapshot(
            schemaVersion: DashboardContract.schemaVersion,
            snapshotId: UUID().uuidString,
            generatedAt: Date(),
            date: dateString(start, timezone: timezone),
            timezone: timezone.identifier,
            pipelineVersion: ObserverPipeline.version,
            dataRevision: dataRevision(events: dayEvents),
            valid: invariantErrors.isEmpty,
            invariantErrors: invariantErrors,
            totals: totals,
            confidenceDistribution: confidence,
            timelineSegments: timelineSegments,
            threadSummaries: threadSummaries,
            reviewSummary: review,
            sensorSummary: sensorSummary,
            causalSummary: causalSummary,
            readinessSummary: readinessSummary
        )
    }

    private func timelineSegments(
        from slices: [ObserverEvent],
        episodes: [ObserverEvent],
        threadNames: [String: String]
    ) -> [DashboardTimelineSegment] {
        let episodeByID = Dictionary(episodes.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, newer in newer })
        return slices.sorted { $0.timestamp < $1.timestamp }.map { slice in
            let episodeId = slice.payload["episode_event_id"]
            let episode = episodeId.flatMap { episodeByID[$0] }
            let threadId = optionalPayload(slice, "activity_thread_id")
            let assigned = threadId != nil && slice.payload["assignment_state"] == "assigned"
            let apps = parseList(episode?.payload["apps"] ?? slice.payload["apps"])
            let start = dateValue(slice.payload["started_at"]) ?? slice.timestamp
            let end = dateValue(slice.payload["ended_at"])
                ?? dateValue(episode?.payload["ended_at"])
                ?? start.addingTimeInterval(duration(slice, key: "active_seconds"))
            return DashboardTimelineSegment(
                id: slice.id.uuidString,
                start: start,
                end: max(end, start),
                activeSeconds: duration(slice, key: "active_seconds"),
                threadId: threadId,
                threadName: assigned ? (threadId.flatMap { threadNames[$0] } ?? "Linked context") : "Unassigned",
                episodeId: episodeId,
                summary: safeSummary(slice.payload["summary"] ?? episode?.payload["summary"] ?? episode?.payload["goal"] ?? slice.payload["activity_kind"] ?? "Context segment"),
                applications: apps.isEmpty ? parseList(slice.payload["dominant_app"]) : apps,
                artifact: optionalPayload(slice, "artifact") ?? optionalPayload(episode, "artifact"),
                activityKind: slice.payload["activity_kind"] ?? episode?.payload["episode_kind"] ?? "unknown",
                confidence: Double(slice.payload["confidence"] ?? "") ?? slice.confidence,
                evidenceChannels: evidenceChannels(slice: slice, episode: episode),
                state: assigned ? "assigned" : "unassigned",
                sourceEventIds: sourceIDs(slice, episode: episode)
            )
        }
    }

    private func threadSummaries(
        threads: [ObserverEvent],
        segments: [DashboardTimelineSegment],
        episodes: [ObserverEvent]
    ) -> [DashboardThreadSummary] {
        let episodeByID = Dictionary(episodes.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { _, newer in newer })
        return threads.compactMap { thread in
            let id = thread.payload["activity_thread_id"] ?? thread.id.uuidString
            let threadSegments = segments.filter { $0.threadId == id }
            guard !threadSegments.isEmpty else { return nil }
            let episodeIds = Set(threadSegments.compactMap(\.episodeId))
            let threadEpisodes = episodeIds.compactMap { episodeByID[$0] }
            let apps = Array(Set(threadSegments.flatMap(\.applications))).sorted()
            let artifacts = Array(Set(threadSegments.compactMap(\.artifact))).sorted()
            return DashboardThreadSummary(
                id: id,
                name: safeSummary(thread.payload["display_name"] ?? thread.payload["generated_name"] ?? "Activity thread"),
                status: thread.payload["status"] ?? "active",
                activeSeconds: threadSegments.reduce(0) { $0 + $1.activeSeconds },
                firstSeen: threadSegments.map(\.start).min(),
                lastSeen: threadSegments.map(\.end).max(),
                episodes: threadEpisodes.count,
                artifacts: artifacts,
                applications: apps,
                confidence: Double(thread.payload["confidence"] ?? "") ?? thread.confidence,
                hasConflicts: thread.payload["has_conflicts"] == "true",
                sourceEventIds: [thread.id.uuidString] + threadSegments.flatMap(\.sourceEventIds)
            )
        }.sorted { $0.activeSeconds > $1.activeSeconds }
    }

    private func reviewSummary(
        segments: [DashboardTimelineSegment],
        sensorGaps: [ObserverEvent]
    ) -> DashboardReviewSummary {
        var items: [DashboardReviewItem] = []
        for segment in segments where segment.state == "unassigned" {
            items.append(DashboardReviewItem(
                id: "review-\(segment.id)",
                type: "unassigned",
                segmentId: segment.id,
                title: "\(segment.threadName): \(segment.summary)",
                affectedSeconds: segment.activeSeconds,
                confidence: segment.confidence,
                supportingEvidence: segment.evidenceChannels,
                contradictingEvidence: ["no confident activity thread"],
                alternatives: ["Assign to existing", "Leave unassigned"],
                sourceEventIds: segment.sourceEventIds
            ))
        }
        for segment in segments where segment.confidence < 0.45 {
            items.append(DashboardReviewItem(
                id: "low-\(segment.id)",
                type: "low_confidence",
                segmentId: segment.id,
                title: "Low confidence: \(segment.summary)",
                affectedSeconds: segment.activeSeconds,
                confidence: segment.confidence,
                supportingEvidence: segment.evidenceChannels,
                contradictingEvidence: ["weak assignment confidence"],
                alternatives: ["Same context", "Different context", "Leave unassigned"],
                sourceEventIds: segment.sourceEventIds
            ))
        }
        for gap in sensorGaps.prefix(12) {
            items.append(DashboardReviewItem(
                id: "gap-\(gap.id.uuidString)",
                type: "sensor_gap",
                segmentId: nil,
                title: gap.payload["channel"] ?? "Sensor gap",
                affectedSeconds: duration(gap, key: "duration_seconds"),
                confidence: gap.confidence,
                supportingEvidence: [gap.type.rawValue],
                contradictingEvidence: [],
                alternatives: ["Inspect sensor"],
                sourceEventIds: [gap.id.uuidString]
            ))
        }
        return DashboardReviewSummary(
            total: items.count,
            unassigned: items.filter { $0.type == "unassigned" }.count,
            lowConfidence: items.filter { $0.type == "low_confidence" }.count,
            conflictingEvidence: items.filter { $0.type == "conflicting_evidence" }.count,
            sensorGaps: sensorGaps.count,
            items: Array(items.prefix(80))
        )
    }

    private func sensorSummary(events: [ObserverEvent], observedSeconds: Double, now: Date) -> DashboardSensorSummary {
        let channelMap: [(id: String, name: String, types: Set<ObserverEventType>)] = [
            ("camera", "Camera", [.attention, .cameraEvidence, .objectPresence, .cameraCueTrajectory, .cameraTier2Sample]),
            ("input", "Input", [.inputActivity, .typingRhythm, .mouseDynamics]),
            ("content", "Content", [.contentContext, .screenContext, .ocrContext, .writingContext]),
            ("app_focus", "App focus", [.appFocus, .appFocusInterval]),
            ("clipboard", "Clipboard", [.clipboardRoute]),
            ("media", "Media", [.mediaPlayback, .mediaReaction]),
            ("causal", "Causal", [.causalHypothesis, .causalAntecedent, .causalUnderstandingReport]),
            ("readiness", "Readiness", [.readinessReport, .funnelReport, .fusionAudit])
        ]
        return DashboardSensorSummary(channels: channelMap.map { channel in
            let matches = events.filter { channel.types.contains($0.type) }
            let last = matches.map(\.timestamp).max()
            let coverage = observedSeconds > 0 ? min(1, Double(matches.count) / max(1, observedSeconds / 60)) : 0
            return DashboardSensorChannel(
                id: channel.id,
                name: channel.name,
                status: matches.isEmpty ? "no_data" : (last.map { now.timeIntervalSince($0) < 300 } == true ? "active" : "stale"),
                coverage: coverage,
                freshnessSeconds: last.map { max(0, now.timeIntervalSince($0)) },
                events: matches.count,
                lastEventAt: last
            )
        })
    }

    private func causalSummary(events: [ObserverEvent]) -> DashboardCausalSummary {
        let hypotheses = events
            .filter { $0.type == .causalHypothesis }
            .suffix(40)
            .map { event in
                DashboardCausalHypothesis(
                    id: event.id.uuidString,
                    transition: safeSummary(event.payload["transition"] ?? event.payload["outcome"] ?? "transition candidate"),
                    mechanism: safeSummary(event.payload["mechanism"] ?? event.payload["hypothesis"] ?? "mechanism under review"),
                    maturity: event.payload["maturity"] ?? "candidate",
                    confidence: event.confidence,
                    evidenceEventIds: parseList(event.payload["evidence_event_ids"] ?? event.payload["source_event_ids"])
                )
            }
        let chains = events
            .filter { $0.type == .chainLink }
            .suffix(80)
            .compactMap { event -> DashboardEpisodeChain? in
                guard let from = event.payload["from_episode_event_id"],
                      let to = event.payload["to_episode_event_id"]
                else { return nil }
                return DashboardEpisodeChain(
                    id: event.id.uuidString,
                    fromEpisodeId: from,
                    toEpisodeId: to,
                    kind: event.payload["kind"] ?? "episode_link",
                    confidence: Double(event.payload["confidence"] ?? "") ?? event.confidence,
                    evidenceEventIds: parseList(event.payload["source_event_ids"])
                )
            }
        return DashboardCausalSummary(hypotheses: hypotheses, episodeChains: chains)
    }

    private func invariantErrors(totals: DashboardTotals, segments: [DashboardTimelineSegment]) -> [String] {
        var errors: [String] = []
        if abs((totals.assignedSeconds + totals.unassignedSeconds) - totals.attributableSeconds) > 1 {
            errors.append("assigned + unassigned != attributable")
        }
        if totals.activeSeconds - totals.observedSeconds > 1 {
            errors.append("active > observed")
        }
        if totals.attributableSeconds - totals.activeSeconds > 1 {
            errors.append("attributable > active")
        }
        let segmentTotal = segments.reduce(0) { $0 + $1.activeSeconds }
        if abs(segmentTotal - totals.attributableSeconds) > 1 {
            errors.append("timeline total != attributable")
        }
        return errors
    }

    private func observedTime(from events: [ObserverEvent], fallbackEnd: Date) -> Double {
        guard let first = events.first?.timestamp, let last = events.last?.timestamp else {
            return 0
        }
        let wallClockSeconds = max(0, min(fallbackEnd, last).timeIntervalSince(first))
        // Absence is a discontinuity in observation, not quiet work. Keep it
        // visible in the review stream, but never let it inflate coverage.
        let awaySeconds = events
            .filter { $0.type == .observationGap && $0.payload["reason"] == "away" }
            .reduce(0) { $0 + duration($1, key: "duration_seconds") }
        return max(0, wallClockSeconds - awaySeconds)
    }

    private func sensorGapEvents(_ events: [ObserverEvent]) -> [ObserverEvent] {
        events.filter {
            $0.type == .observationGap
                || ($0.type == .breakpoint && ($0.payload["breakpoint_type"] ?? "").contains("gap"))
                || ($0.payload["sensor_gap"] == "true")
        }
    }

    private func dictionary(from events: [ObserverEvent], idKey: String, nameKey: String) -> [String: String] {
        var result: [String: String] = [:]
        for event in events {
            guard let id = event.payload[idKey], !id.isEmpty else { continue }
            result[id] = event.payload[nameKey] ?? event.payload["display_name"] ?? id
        }
        return result
    }

    private func evidenceChannels(slice: ObserverEvent, episode: ObserverEvent?) -> [String] {
        var channels = Set<String>()
        for raw in parseList(slice.payload["evidence_channels"] ?? slice.payload["source_channels"]) {
            channels.insert(raw)
        }
        for id in sourceIDs(slice, episode: episode) {
            if id.isEmpty == false { channels.insert("lineage") }
        }
        if episode?.payload["apps"]?.isEmpty == false { channels.insert("app") }
        if slice.payload["activity_kind"]?.isEmpty == false { channels.insert("context") }
        return channels.sorted()
    }

    private func sourceIDs(_ slice: ObserverEvent, episode: ObserverEvent?) -> [String] {
        var ids = [slice.id.uuidString]
        ids += parseList(slice.payload["source_event_ids"])
        if let episode { ids.append(episode.id.uuidString) }
        return Array(Set(ids)).sorted()
    }

    private func dataRevision(events: [ObserverEvent]) -> String {
        let base = "\(events.count):\(events.last?.id.uuidString ?? "empty"):\(events.last?.timestamp.timeIntervalSince1970 ?? 0)"
        return String(base.hashValue)
    }

    private func dateString(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private func duration(_ event: ObserverEvent, key: String) -> Double {
    Double(event.payload[key] ?? "") ?? 0
}

private func dateValue(_ value: String?) -> Date? {
    guard let value else { return nil }
    return ISO8601DateFormatter().date(from: value)
}

private func optionalPayload(_ event: ObserverEvent?, _ key: String) -> String? {
    guard let value = event?.payload[key], !value.isEmpty else { return nil }
    return value
}

private func parseList(_ value: String?) -> [String] {
    guard let value, !value.isEmpty else { return [] }
    if value.contains("->") {
        return value
            .components(separatedBy: "->")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    if value.contains(",") {
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    if value.contains("|") {
        return value
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    return [value]
}

private func safeSummary(_ value: String) -> String {
    value
        .replacingOccurrences(of: #"\[secret:[^\]]+\]"#, with: "[secret]", options: .regularExpression)
        .replacingOccurrences(of: #"https?://\S+"#, with: "[url]", options: .regularExpression)
        .replacingOccurrences(of: #"chatgpt\.com/c/\S+"#, with: "ChatGPT thread", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
