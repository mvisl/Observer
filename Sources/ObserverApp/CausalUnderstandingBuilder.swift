import Foundation

struct CausalUnderstandingResult {
    let evidence: [[String: String]]
    let transitions: [[String: String]]
    let antecedents: [[String: String]]
    let hypotheses: [[String: String]]
}

struct CausalUnderstandingBuilder {
    private let iso = ISO8601DateFormatter()

    func buildForClosedEpisode(
        episode: ObserverEvent,
        episodeEvents: [ObserverEvent],
        historicalEvents: [ObserverEvent] = [],
        now: Date = Date()
    ) -> CausalUnderstandingResult {
        let evidence = evidenceNodes(for: episode, events: episodeEvents, now: now)
        let transitions = stateTransitions(for: episode, events: episodeEvents, evidence: evidence, now: now)
        let antecedents = transitions.flatMap { transition in
            causalAntecedents(for: transition, episode: episode, events: episodeEvents, historicalEvents: historicalEvents)
        }
        let hypotheses = transitions.flatMap { transition in
            causalHypotheses(
                for: transition,
                episode: episode,
                antecedents: antecedents,
                evidence: evidence,
                historicalEvents: historicalEvents,
                now: now
            )
        }
        return .init(evidence: evidence, transitions: transitions, antecedents: antecedents, hypotheses: hypotheses)
    }

    func validationReport(events: [ObserverEvent], now: Date = Date()) -> (payload: [String: String], patterns: [[String: String]]) {
        let hypotheses = events.filter { $0.type == .causalHypothesis }
        let grouped = Dictionary(grouping: hypotheses) { event in
            event.payload["pattern_key"] ?? event.payload["claim"] ?? "unknown"
        }
        var patterns: [[String: String]] = []
        for (key, group) in grouped where group.count >= 3 {
            let episodeIDs = orderedUnique(group.compactMap { $0.payload["episode_id"] })
            let days = Set(group.map { Calendar.current.startOfDay(for: $0.timestamp) })
            guard episodeIDs.count >= 3, days.count >= 2 else {
                continue
            }
            let counterexamples = events.filter { event in
                event.type == .causalHypothesis
                    && event.payload["pattern_key"] != key
                    && event.payload["transition_type"] == group.first?.payload["transition_type"]
            }.prefix(5)
            let maturity = counterexamples.isEmpty ? "association" : "repeated_pattern"
            let confidence = counterexamples.isEmpty ? 0.52 : min(0.72, 0.50 + Double(group.count) * 0.04)
            patterns.append([
                "name": key,
                "description": group.first?.payload["claim"] ?? key,
                "mechanism": group.first?.payload["mechanism"] ?? "mechanism not stable yet",
                "supporting_episode_ids": episodeIDs.joined(separator: ","),
                "contradicting_episode_ids": counterexamples.compactMap { $0.payload["episode_id"] }.joined(separator: ","),
                "contexts_where_observed": orderedUnique(group.compactMap { $0.payload["episode_topic"] }).joined(separator: " | "),
                "contexts_where_not_observed": counterexamples.compactMap { $0.payload["episode_topic"] }.joined(separator: " | "),
                "maturity_level": maturity,
                "confidence": String(format: "%.2f", confidence),
                "first_observed_at": iso.string(from: group.map(\.timestamp).min() ?? now),
                "last_validated_at": iso.string(from: now),
                "pipeline_version": ObserverPipeline.version,
                "source_event_ids": group.map(\.id.uuidString).joined(separator: ",")
            ])
        }

        let weakened = hypotheses.filter { $0.payload["status"] == "weakened" }.count
        let rejected = hypotheses.filter { $0.payload["status"] == "rejected" }.count
        let payload: [String: String] = [
            "validated_hypotheses": "\(hypotheses.count)",
            "patterns_created": "\(patterns.count)",
            "weakened": "\(weakened)",
            "rejected": "\(rejected)",
            "counterexample_search": "enabled",
            "pipeline_version": ObserverPipeline.version,
            "source_event_ids": (hypotheses.isEmpty ? events.suffix(100) : hypotheses.suffix(100)).map(\.id.uuidString).joined(separator: ",")
        ]
        return (payload, patterns)
    }

    func report(events: [ObserverEvent], period: String = "all") -> String {
        let episodes = events.filter { $0.type == .episode }
        let transitions = events.filter { $0.type == .stateTransition }
        let hypotheses = events.filter { $0.type == .causalHypothesis }
        let patterns = events.filter { $0.type == .personalCausalPattern }
        let withMechanism = hypotheses.filter { $0.payload["mechanism"]?.isEmpty == false }.count
        let withAlternatives = hypotheses.filter { $0.payload["alternative_claims"]?.isEmpty == false }.count
        let withContradictions = hypotheses.filter { $0.payload["contradicting_evidence_ids"]?.isEmpty == false }.count
        let unsupported = hypotheses.filter { $0.payload["supporting_evidence_ids"]?.isEmpty != false }.count
        let unsupportedRate = hypotheses.isEmpty ? 0 : Double(unsupported) / Double(hypotheses.count)

        let episodeLines = episodes.suffix(12).map { episode in
            let goal = episode.payload["goal"] ?? episode.payload["dominant_context"] ?? "unknown"
            let topic = episode.payload["topic"] ?? episode.payload["dominant_context"] ?? "unknown"
            return "- \(goal): \(topic), \(episode.payload["status"] ?? "closed"), confidence \(episode.confidence.formatted(.number.precision(.fractionLength(2))))"
        }.joined(separator: "\n")

        let hypothesisLines = hypotheses.suffix(16).map { event in
            """
            - Change: \(event.payload["transition_type"] ?? "unknown")
              Cause candidate: \(event.payload["antecedent_description"] ?? "unknown")
              Role: \(event.payload["antecedent_role"] ?? "unknown")
              Mechanism: \(event.payload["mechanism"] ?? "none")
              Alternatives: \(event.payload["alternative_claims"] ?? "none")
              Maturity: \(event.payload["maturity_level"] ?? "sequence"), confidence \(event.payload["confidence"] ?? "?"), status \(event.payload["status"] ?? "candidate")
            """
        }.joined(separator: "\n")

        let patternLines = patterns.suffix(10).map { event in
            "- \(event.payload["name"] ?? "pattern"): \(event.payload["maturity_level"] ?? "association"), confidence \(event.payload["confidence"] ?? "?")"
        }.joined(separator: "\n")

        return """
        # Causal Understanding Report

        ## Summary

        - Period: \(period)
        - Episodes detected: \(episodes.count)
        - Transitions detected: \(transitions.count)
        - Causal hypotheses created: \(hypotheses.count)
        - Supported: \(hypotheses.filter { $0.payload["status"] == "supported" }.count)
        - Weakened: \(hypotheses.filter { $0.payload["status"] == "weakened" }.count)
        - Rejected: \(hypotheses.filter { $0.payload["status"] == "rejected" }.count)
        - Insufficient evidence: \(hypotheses.filter { $0.payload["status"] == "insufficient_evidence" }.count)

        ## Episodes

        \(episodeLines.isEmpty ? "- No episodes yet." : episodeLines)

        ## Causal Hypotheses

        \(hypothesisLines.isEmpty ? "- No causal hypotheses yet." : hypothesisLines)

        ## Repeated Patterns

        \(patternLines.isEmpty ? "- No repeated patterns validated yet." : patternLines)

        ## Quality Metrics

        - Episode coverage: \(episodes.isEmpty ? "0%" : "active")
        - Transition coverage: \(episodes.isEmpty ? "0%" : "\(Int((Double(transitions.count) / Double(max(1, episodes.count)) * 100).rounded()))%")
        - Hypotheses with mechanism: \(percent(withMechanism, of: hypotheses.count))
        - Hypotheses with alternatives: \(percent(withAlternatives, of: hypotheses.count))
        - Hypotheses with contradicting evidence: \(percent(withContradictions, of: hypotheses.count))
        - Unsupported causal claim rate: \(Int((unsupportedRate * 100).rounded()))%
        - Rejected hypotheses count: \(hypotheses.filter { $0.payload["status"] == "rejected" }.count)
        - Revised episode count: \(episodes.filter { $0.payload["status"] == "revised" }.count)
        """
    }

    private func evidenceNodes(for episode: ObserverEvent, events: [ObserverEvent], now: Date) -> [[String: String]] {
        events.compactMap { event -> [String: String]? in
            guard let channel = evidenceChannel(for: event) else {
                return nil
            }
            return [
                "episode_event_id": episode.id.uuidString,
                "channel": channel.channel,
                "independence_group": channel.group,
                "proposition": proposition(for: event),
                "polarity": polarity(for: event),
                "reliability": String(format: "%.2f", reliability(for: event)),
                "freshness_seconds": String(format: "%.1f", now.timeIntervalSince(event.timestamp)),
                "source_event_ids": event.id.uuidString,
                "abstraction_level": "L0"
            ]
        }
    }

    private func stateTransitions(
        for episode: ObserverEvent,
        events: [ObserverEvent],
        evidence: [[String: String]],
        now: Date
    ) -> [[String: String]] {
        var transitions: [[String: String]] = []
        if let correction = correctionLoopTransition(episode: episode, events: events, now: now) {
            transitions.append(correction)
        }
        if let friction = frictionTransition(episode: episode, events: events, now: now) {
            transitions.append(friction)
        }
        if let resume = resumeTransition(episode: episode, events: events, now: now) {
            transitions.append(resume)
        }
        return transitions
    }

    private func correctionLoopTransition(episode: ObserverEvent, events: [ObserverEvent], now: Date) -> [String: String]? {
        let correctionEvents = events.filter { event in
            let text = searchableText(event)
            return text.contains("санитар")
                || text.contains("поверхност")
                || text.contains("уров")
                || text.contains("не работает")
                || text.contains("ошиб")
                || text.contains("непонят")
                || text.contains("херн")
                || text.contains("фигн")
        }
        guard let first = correctionEvents.first else {
            return nil
        }
        return transitionPayload(
            episode: episode,
            startedAt: first.timestamp,
            detectedAt: now,
            from: "reviewing",
            to: correctionEvents.count >= 2 ? "correction_loop" : "correcting",
            type: correctionEvents.count >= 2 ? "correction_loop_repeated" : "correction_loop_started",
            observable: [
                "повторяются корректирующие формулировки",
                "после оценки результата появляется новая правка или уточнение требований"
            ],
            sourceIDs: correctionEvents.map(\.id.uuidString),
            confidence: correctionEvents.count >= 2 ? 0.72 : 0.58
        )
    }

    private func frictionTransition(episode: ObserverEvent, events: [ObserverEvent], now: Date) -> [String: String]? {
        let frictionEvents = events.filter { event in
            event.type == .fusionHypothesis || event.type == .behaviorCue
        }.filter { searchableText($0).contains("friction") || searchableText($0).contains("фрикц") || searchableText($0).contains("резк") }
        guard let first = frictionEvents.first else {
            return nil
        }
        return transitionPayload(
            episode: episode,
            startedAt: first.timestamp,
            detectedAt: now,
            from: "executing",
            to: "blocked",
            type: "friction_detected",
            observable: ["усилились признаки фрикции", "появились возвраты к тому же вопросу или резкие переключения"],
            sourceIDs: frictionEvents.map(\.id.uuidString),
            confidence: 0.55
        )
    }

    private func resumeTransition(episode: ObserverEvent, events: [ObserverEvent], now: Date) -> [String: String]? {
        let idle = events.first { event in
            event.type == .breakpoint && (event.payload["breakpoint_type"] == "coarse" || event.payload["reason"]?.contains("idle") == true)
        }
        let laterInput = events.first { event in
            guard let idle else { return false }
            return event.type == .inputActivity
                && event.timestamp > idle.timestamp
                && (Double(event.payload["seconds_since_any_input"] ?? "") ?? 99) < 10
        }
        guard let idle, let laterInput else {
            return nil
        }
        return transitionPayload(
            episode: episode,
            startedAt: laterInput.timestamp,
            detectedAt: now,
            from: "task_interrupted",
            to: "task_resumed",
            type: "task_resumed",
            observable: ["после паузы снова появился ввод", "возврат произошёл внутри того же эпизода"],
            sourceIDs: [idle.id.uuidString, laterInput.id.uuidString],
            confidence: 0.62
        )
    }

    private func causalAntecedents(
        for transition: [String: String],
        episode: ObserverEvent,
        events: [ObserverEvent],
        historicalEvents: [ObserverEvent]
    ) -> [[String: String]] {
        guard let transitionAt = iso.date(from: transition["started_at"] ?? "") else {
            return []
        }
        let transitionUpperBound = transitionAt.addingTimeInterval(1)
        let episodeLowerBound = (iso.date(from: episode.payload["start"] ?? "") ?? transitionAt).addingTimeInterval(-1)
        let candidates = events.filter { event in
            event.timestamp <= transitionUpperBound
                && event.timestamp >= episodeLowerBound
                && [.contentContext, .fusionHypothesis, .behaviorCue, .geminiInsight, .localInsight, .appFocus, .attentionSpan].contains(event.type)
        }
        var antecedents: [[String: String]] = []
        if let trigger = bestTrigger(from: candidates, transitionAt: transitionAt) {
            antecedents.append(antecedentPayload(
                transition: transition,
                episode: episode,
                event: trigger,
                role: "trigger",
                description: triggerDescription(for: trigger),
                transitionAt: transitionAt,
                semantic: semanticRelevance(trigger, transition: transition),
                recurrence: recurrenceScore(trigger, historicalEvents: historicalEvents)
            ))
        }
        if transition["transition_type"]?.contains("correction_loop") == true {
            antecedents.append([
                "transition_id": transition["transition_id"] ?? "",
                "episode_event_id": episode.id.uuidString,
                "description": "ожидания качества вывода ещё не сведены в проверяемые acceptance criteria",
                "role": "enabling_condition",
                "occurred_at": episode.payload["start"] ?? "",
                "temporal_distance_seconds": String(format: "%.1f", transitionAt.timeIntervalSince(iso.date(from: episode.payload["start"] ?? "") ?? transitionAt)),
                "source_event_ids": episode.payload["trace_event_ids"] ?? episode.id.uuidString,
                "semantic_relevance": "0.70",
                "temporal_relevance": "0.35",
                "recurrence_score": "0.50",
                "abstraction_level": "L2"
            ])
        }
        return antecedents
    }

    private func causalHypotheses(
        for transition: [String: String],
        episode: ObserverEvent,
        antecedents: [[String: String]],
        evidence: [[String: String]],
        historicalEvents: [ObserverEvent],
        now: Date
    ) -> [[String: String]] {
        let transitionID = transition["transition_id"] ?? ""
        let relatedAntecedents = antecedents.filter { $0["transition_id"] == transitionID }
        guard let primary = relatedAntecedents.first,
              primary["description"]?.isEmpty == false
        else {
            return []
        }
        let supporting = evidence.filter { item in
            item["polarity"] == "supports"
                && (item["independence_group"] == "content"
                    || item["independence_group"] == "app_sequence"
                    || item["independence_group"] == "input")
        }
        guard !supporting.isEmpty else {
            return []
        }
        let contradicting = evidence.filter { $0["polarity"] == "contradicts" }
        let alternatives = alternatives(for: transition, primary: primary, episode: episode)
        guard !alternatives.isEmpty else {
            return []
        }
        let mechanism = mechanism(for: transition, antecedent: primary)
        let supportIDs = supporting.compactMap { $0["source_event_ids"] }.joined(separator: ",")
        let contradictionIDs = contradicting.compactMap { $0["source_event_ids"] }.joined(separator: ",")
        let confidence = hypothesisConfidence(
            antecedent: primary,
            supportCount: supporting.count,
            contradictionCount: contradicting.count,
            alternativesCount: alternatives.count
        )
        let maturity = mechanism == "temporal association only" ? "sequence" : "plausible_mechanism"
        let status = confidence < 0.45 ? "insufficient_evidence" : "candidate"
        let patternKey = patternKey(for: transition, antecedent: primary)
        return [[
            "episode_event_id": episode.id.uuidString,
            "episode_topic": episode.payload["topic"] ?? episode.payload["dominant_context"] ?? "",
            "transition_id": transitionID,
            "transition_type": transition["transition_type"] ?? "",
            "antecedent_id": primary["antecedent_id"] ?? "",
            "antecedent_description": primary["description"] ?? "",
            "antecedent_role": primary["role"] ?? "",
            "claim": claim(for: transition, antecedent: primary),
            "mechanism": mechanism,
            "supporting_evidence_ids": supportIDs,
            "contradicting_evidence_ids": contradictionIDs,
            "alternative_claims": alternatives.joined(separator: " | "),
            "maturity_level": maturity,
            "status": status,
            "confidence": String(format: "%.2f", confidence),
            "pattern_key": patternKey,
            "model_name": "local_rule_causal_builder",
            "model_version": ObserverPipeline.version,
            "prompt_version": "none",
            "pipeline_version": ObserverPipeline.version,
            "created_at": iso.string(from: now),
            "updated_at": iso.string(from: now),
            "source_event_ids": ([transitionID, primary["source_event_ids"] ?? "", supportIDs].filter { !$0.isEmpty }).joined(separator: ","),
            "abstraction_level": "L3",
            "shadow_mode": "true",
            "not_user_visible": "true"
        ]]
    }

    private func transitionPayload(
        episode: ObserverEvent,
        startedAt: Date,
        detectedAt: Date,
        from: String,
        to: String,
        type: String,
        observable: [String],
        sourceIDs: [String],
        confidence: Double
    ) -> [String: String] {
        [
            "transition_id": UUID().uuidString,
            "episode_event_id": episode.id.uuidString,
            "started_at": iso.string(from: startedAt),
            "detected_at": iso.string(from: detectedAt),
            "from_state": from,
            "to_state": to,
            "transition_type": type,
            "observable_changes": observable.joined(separator: " | "),
            "source_event_ids": sourceIDs.joined(separator: ","),
            "confidence": String(format: "%.2f", confidence),
            "pipeline_version": ObserverPipeline.version,
            "abstraction_level": "L2"
        ]
    }

    private func antecedentPayload(
        transition: [String: String],
        episode: ObserverEvent,
        event: ObserverEvent,
        role: String,
        description: String,
        transitionAt: Date,
        semantic: Double,
        recurrence: Double
    ) -> [String: String] {
        let distance = max(0, transitionAt.timeIntervalSince(event.timestamp))
        let temporal = max(0.1, min(0.95, 1.0 - (distance / 900)))
        return [
            "antecedent_id": UUID().uuidString,
            "transition_id": transition["transition_id"] ?? "",
            "episode_event_id": episode.id.uuidString,
            "description": description,
            "role": role,
            "occurred_at": iso.string(from: event.timestamp),
            "temporal_distance_seconds": String(format: "%.1f", distance),
            "source_event_ids": event.id.uuidString,
            "semantic_relevance": String(format: "%.2f", semantic),
            "temporal_relevance": String(format: "%.2f", temporal),
            "recurrence_score": String(format: "%.2f", recurrence),
            "abstraction_level": "L2"
        ]
    }

    private func evidenceChannel(for event: ObserverEvent) -> (channel: String, group: String)? {
        switch event.type {
        case .contentContext, .writingContext:
            return ("content_semantics", "content")
        case .ocrContext, .screenContext:
            return ("screen_text", "content")
        case .appFocus, .appFocusInterval, .attentionSpan:
            return ("application_sequence", "app_sequence")
        case .inputActivity, .typingRhythm, .mouseDynamics:
            return ("input_dynamics", "input")
        case .behaviorCue, .fusionHypothesis:
            return ("behavior_inference", behaviorGroup(for: event))
        case .boundReaction:
            return ("subsequent_reaction", "reaction")
        case .userLabel, .userNote:
            return ("explicit_feedback", "user_feedback")
        default:
            return nil
        }
    }

    private func behaviorGroup(for event: ObserverEvent) -> String {
        let text = searchableText(event)
        if text.contains("smile") || text.contains("yawn") || text.contains("blink") || text.contains("camera") {
            return "camera"
        }
        if text.contains("text") || text.contains("tone") || text.contains("writing") {
            return "content"
        }
        return "behavior"
    }

    private func proposition(for event: ObserverEvent) -> String {
        event.payload["topic"]
            ?? event.payload["raw_fragment"]
            ?? event.payload["cue"]
            ?? event.payload["interpretation"]
            ?? event.payload["span_kind"]
            ?? event.payload["app_name"]
            ?? event.type.rawValue
    }

    private func polarity(for event: ObserverEvent) -> String {
        let text = searchableText(event)
        if text.contains("smile") || text.contains("positive_reaction") || text.contains("recharge") {
            return "contradicts"
        }
        return "supports"
    }

    private func reliability(for event: ObserverEvent) -> Double {
        switch event.type {
        case .contentContext, .writingContext:
            return 0.78
        case .userLabel, .userNote:
            return 0.92
        case .boundReaction:
            return 0.68
        case .inputActivity, .typingRhythm, .mouseDynamics, .attentionSpan:
            return 0.64
        case .behaviorCue, .fusionHypothesis:
            return 0.48
        default:
            return 0.50
        }
    }

    private func bestTrigger(from candidates: [ObserverEvent], transitionAt: Date) -> ObserverEvent? {
        candidates.max { lhs, rhs in
            candidateScore(lhs, transitionAt: transitionAt) < candidateScore(rhs, transitionAt: transitionAt)
        }
    }

    private func candidateScore(_ event: ObserverEvent, transitionAt: Date) -> Double {
        let semantic = semanticRelevance(event, transition: [:])
        let distance = max(0, transitionAt.timeIntervalSince(event.timestamp))
        let temporal = max(0.1, min(0.95, 1.0 - (distance / 900)))
        return semantic * 0.65 + temporal * 0.35
    }

    private func triggerDescription(for event: ObserverEvent) -> String {
        let text = searchableText(event)
        if text.contains("санитар") || text.contains("поверхност") || text.contains("л0") || text.contains("l0") {
            return "вывод Observer остался на поверхностном уровне вместо причинного объяснения"
        }
        if text.contains("ошиб") || text.contains("не работает") {
            return "появился сбой или неверная интерпретация результата"
        }
        return proposition(for: event)
    }

    private func semanticRelevance(_ event: ObserverEvent, transition: [String: String]) -> Double {
        let text = searchableText(event)
        if text.contains("observer") || text.contains("пилюл") || text.contains("санитар") || text.contains("поверхност") {
            return 0.86
        }
        if text.contains("ошиб") || text.contains("не работает") || text.contains("фрикц") {
            return 0.72
        }
        if event.type == .contentContext || event.type == .writingContext {
            return 0.58
        }
        return 0.35
    }

    private func recurrenceScore(_ event: ObserverEvent, historicalEvents: [ObserverEvent]) -> Double {
        let text = searchableText(event)
        guard !text.isEmpty else {
            return 0.1
        }
        let keywords = ["observer", "пилюл", "санитар", "поверхност", "ошиб", "фрикц"].filter { text.contains($0) }
        guard !keywords.isEmpty else {
            return 0.2
        }
        let matches = historicalEvents.filter { historical in
            let hay = searchableText(historical)
            return keywords.contains { hay.contains($0) }
        }.count
        return min(0.85, 0.25 + Double(matches) * 0.03)
    }

    private func mechanism(for transition: [String: String], antecedent: [String: String]) -> String {
        let transitionType = transition["transition_type"] ?? ""
        let description = antecedent["description"] ?? ""
        if transitionType.contains("correction_loop") && description.contains("поверхност") {
            return "результат не прошёл ожидаемый уровень абстракции, поэтому проверка превратилась в повторное уточнение критериев и новую итерацию правок"
        }
        if transitionType == "friction_detected" {
            return "наблюдаемое препятствие нарушило ход работы, поэтому пользователь вернулся к уточнению проблемы вместо продолжения выполнения"
        }
        if transitionType == "task_resumed" {
            return "после паузы сохранилась семантическая связность эпизода, поэтому ввод возобновился в той же задаче"
        }
        return "temporal association only"
    }

    private func claim(for transition: [String: String], antecedent: [String: String]) -> String {
        let description = antecedent["description"] ?? "предыдущий сигнал"
        switch transition["transition_type"] {
        case "correction_loop_started", "correction_loop_repeated":
            return "\(description) мог запустить переход проверки в цикл исправлений"
        case "friction_detected":
            return "\(description) мог усилить фрикцию текущего эпизода"
        case "task_resumed":
            return "\(description) мог помочь вернуться к задаче после паузы"
        default:
            return "\(description) мог предшествовать наблюдаемому изменению"
        }
    }

    private func alternatives(for transition: [String: String], primary: [String: String], episode: ObserverEvent) -> [String] {
        var values = [
            "пользователь заранее планировал ещё одну итерацию",
            "изменение вызвал технический баг, а не смысловая слабость вывода",
            "изменение произошло раньше предполагаемой причины",
            "неучтённый внешний фактор изменил ход работы"
        ]
        if transition["transition_type"] == "task_resumed" {
            values = [
                "возврат был естественным завершением паузы",
                "пользователь вернулся из-за внешнего напоминания",
                "семантическая связь эпизода переоценена"
            ]
        }
        return values
    }

    private func hypothesisConfidence(
        antecedent: [String: String],
        supportCount: Int,
        contradictionCount: Int,
        alternativesCount: Int
    ) -> Double {
        let semantic = Double(antecedent["semantic_relevance"] ?? "") ?? 0.4
        let temporal = Double(antecedent["temporal_relevance"] ?? "") ?? 0.4
        let recurrence = Double(antecedent["recurrence_score"] ?? "") ?? 0.2
        let support = min(0.16, Double(supportCount) * 0.04)
        let contradictionPenalty = Double(contradictionCount) * 0.08
        let alternativePenalty = Double(max(1, alternativesCount)) * 0.03
        return max(0.20, min(0.82, semantic * 0.42 + temporal * 0.25 + recurrence * 0.17 + support - contradictionPenalty - alternativePenalty))
    }

    private func patternKey(for transition: [String: String], antecedent: [String: String]) -> String {
        let role = antecedent["role"] ?? "unknown"
        let transitionType = transition["transition_type"] ?? "unknown"
        if antecedent["description"]?.contains("поверхност") == true {
            return "surface_level_output_to_correction_loop"
        }
        return "\(role)_to_\(transitionType)"
    }

    private func searchableText(_ event: ObserverEvent) -> String {
        event.payload.values.joined(separator: " ").lowercased()
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard !value.isEmpty, !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            return true
        }
    }

    private func percent(_ numerator: Int, of denominator: Int) -> String {
        guard denominator > 0 else {
            return "0%"
        }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }
}
