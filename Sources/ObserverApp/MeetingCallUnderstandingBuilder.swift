import Foundation

struct MeetingCallUnderstandingBuilder {
    func meetingContextPayload(
        title: String?,
        participants: [String],
        speaker: String?,
        topic: String,
        captionsAvailable: Bool,
        screenShareTitle: String?,
        evidenceEventIDs: [String] = []
    ) -> [String: String] {
        var payload = baseContentPayload(kind: captionsAvailable ? "meeting_captions" : "meeting", topic: topic)
        payload["meeting_title"] = safe(title)
        payload["participants"] = safeList(participants)
        payload["speaker"] = safe(speaker)
        payload["captions_available"] = captionsAvailable ? "true" : "false"
        payload["screen_share_title"] = safe(screenShareTitle)
        payload["task_binding_weight"] = screenShareTitle?.isEmpty == false ? "high" : "medium"
        payload["raw_audio_retained"] = "false"
        payload["raw_transcript_retained"] = "false"
        payload["source_event_ids"] = evidenceEventIDs.joined(separator: ",")
        return payload
    }

    func callDistilledPayload(
        entityDisplayName: String?,
        topic: String,
        taskCandidates: [String],
        entitiesMentioned: [String],
        actionItemCount: Int,
        lexicalTone: String,
        whisperConfidence: Double?,
        evidenceEventIDs: [String] = []
    ) -> [String: String] {
        var payload = baseContentPayload(kind: "call_distilled", topic: topic)
        payload["source_entity_display_name"] = safe(entityDisplayName)
        payload["task_candidates"] = safeList(taskCandidates)
        payload["entities_mentioned"] = safeList(entitiesMentioned)
        payload["action_item_count"] = "\(max(0, actionItemCount))"
        payload["tone_source"] = "lexical_only"
        payload["tone"] = allowedTone(lexicalTone)
        payload["whisper_confidence"] = whisperConfidence.map { String(format: "%.2f", $0) } ?? ""
        payload["raw_audio_retained"] = "false"
        payload["raw_transcript_retained"] = "false"
        payload["transcript_path"] = ""
        payload["audio_path"] = ""
        payload["source_event_ids"] = evidenceEventIDs.joined(separator: ",")
        return payload
    }

    func audioCaptureStatePayload(
        episodeKind: String,
        systemAudioEnabled: Bool,
        microphoneEnabled: Bool,
        captionsAvailable: Bool,
        visibleIndicator: Bool = true
    ) -> [String: String] {
        [
            "episode_kind": ["meeting", "call"].contains(episodeKind) ? episodeKind : "unknown",
            "microphone_capture": microphoneEnabled ? "on" : "off",
            "system_audio_capture": systemAudioEnabled ? "on" : "off",
            "captions_available": captionsAvailable ? "true" : "false",
            "visible_indicator": visibleIndicator ? "true" : "false",
            "chunk_seconds": episodeKind == "call" ? "30-90" : "30-60",
            "raw_audio_retained": "false",
            "raw_transcript_retained": "false",
            "debug_raw_storage": "forbidden"
        ]
    }

    func actionItemPayload(
        text: String,
        requesterEntity: String?,
        addressee: String,
        dueHint: String?,
        evidenceEventIDs: [String]
    ) -> [String: String] {
        [
            "text": safeParaphrase(text),
            "requester_entity": safe(requesterEntity),
            "addressee": addressee == "other" ? "other" : "me",
            "due_hint": safe(dueHint),
            "evidence_event_ids": evidenceEventIDs.joined(separator: ","),
            "quote_policy": "paraphrase_no_raw_call_transcript",
            "raw_audio_retained": "false",
            "raw_transcript_retained": "false"
        ]
    }

    private func baseContentPayload(kind: String, topic: String) -> [String: String] {
        [
            "content_kind": kind,
            "topic": safeParaphrase(topic),
            "sentiment": "neutral",
            "language": topic.range(of: "\\p{Cyrillic}", options: .regularExpression) == nil ? "en" : "ru",
            "is_incoming": "false",
            "semantic_only": "true",
            "storage_policy": "read_all_store_semantics_no_raw_call_transcript"
        ]
    }

    private func allowedTone(_ value: String) -> String {
        let tone = value.lowercased()
        return ["calm", "tense", "friendly"].contains(tone) ? tone : "calm"
    }

    private func safe(_ value: String?) -> String {
        safeParaphrase(value ?? "")
    }

    private func safeList(_ values: [String]) -> String {
        values
            .map(safeParaphrase)
            .filter { !$0.isEmpty }
            .prefix(12)
            .joined(separator: ",")
    }

    private func safeParaphrase(_ value: String) -> String {
        let redacted = PrivacyRedactor.redact(value)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(redacted.prefix(220))
    }
}

struct ObjectPresenceBuilder {
    func normalizedClass(from classifierLabel: String) -> String? {
        let label = classifierLabel.lowercased()
        if ["headphone", "headset", "earphone", "airpod"].contains(where: label.contains) {
            return "headphones"
        }
        if ["cell phone", "cellular telephone", "mobile phone", "smartphone", "telephone"].contains(where: label.contains) {
            return "cell phone"
        }
        if label.contains("wine glass") { return "wine glass" }
        if label.contains("bottle") { return "bottle" }
        if label.contains("cup") || label.contains("mug") { return "cup" }
        if label.contains("fork") { return "fork" }
        if label.contains("spoon") { return "spoon" }
        if label.contains("bowl") { return "bowl" }
        if label.contains("sandwich") { return "sandwich" }
        if label.contains("banana") { return "banana" }
        if label.contains("apple") { return "apple" }
        if label.contains("orange") { return "orange" }
        if label.contains("broccoli") { return "broccoli" }
        if label.contains("carrot") { return "carrot" }
        if label.contains("hot dog") { return "hot dog" }
        if label.contains("pizza") { return "pizza" }
        if label.contains("donut") { return "donut" }
        if label.contains("cake") { return "cake" }
        return nil
    }

    func payload(
        objectClass: String,
        inHand: Bool,
        durationSeconds: TimeInterval,
        confidence: Double
    ) -> [String: String]? {
        let normalized = objectClass.lowercased().replacingOccurrences(of: "_", with: " ")
        guard supportedClasses.contains(normalized) else {
            return nil
        }

        var payload: [String: String] = [
            "object_class": normalized,
            "in_hand": inHand ? "true" : "false",
            "duration_seconds": String(format: "%.1f", max(0, durationSeconds)),
            "confidence": String(format: "%.2f", max(0, min(1, confidence))),
            "shadow_mode": "true",
            "display_eligible": "false",
            "frame_retained": "false",
            "inference_policy": "destroy_frame_after_inference",
            "fusion_channel": "object"
        ]

        if normalized == "cell phone" && inHand {
            payload["evidence_role"] = "screen_break_or_wandering_disambiguation"
        } else if ["headphones", "earphones", "airpods"].contains(normalized) {
            payload["evidence_role"] = "media_pause_resume_evidence"
            payload["display_eligible"] = "false"
        } else if ["cup", "bottle", "wine glass", "fork", "spoon", "bowl", "sandwich", "banana", "apple", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake"].contains(normalized) {
            payload["evidence_role"] = "refuel_break_candidate"
        } else {
            payload["evidence_role"] = "contextual_object_presence"
        }
        return payload
    }

    private var supportedClasses: Set<String> {
        [
            "cell phone",
            "cup",
            "bottle",
            "wine glass",
            "fork",
            "spoon",
            "bowl",
            "sandwich",
            "banana",
            "apple",
            "orange",
            "broccoli",
            "carrot",
            "hot dog",
            "pizza",
            "donut",
            "cake",
            "headphones",
            "earphones",
            "airpods"
        ]
    }
}
