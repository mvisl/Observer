import Foundation

struct BehaviorCue: Equatable {
    let name: String
    let insight: String
    let confidence: Double
    let payload: [String: String]
}

struct BehaviorCueBuilder {
    func build(
        previousAttention: AttentionSnapshot?,
        currentAttention: AttentionSnapshot?,
        secondsSincePreviousAttention: TimeInterval?,
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?,
        currentFocusStartedAt: Date?,
        focusChangesLastMinute: Int,
        activityInsight: String?,
        now: Date = Date()
    ) -> BehaviorCue? {
        if let cue = frictionCue(
            input: input,
            currentFocus: currentFocus,
            focusChangesLastMinute: focusChangesLastMinute,
            activityInsight: activityInsight
        ) {
            return cue
        }

        if let cue = postureCue(
            previous: previousAttention,
            current: currentAttention,
            secondsSincePrevious: secondsSincePreviousAttention,
            input: input,
            currentFocus: currentFocus,
            activityInsight: activityInsight
        ) {
            return cue
        }

        return focusCue(
            currentAttention: currentAttention,
            input: input,
            currentFocus: currentFocus,
            currentFocusStartedAt: currentFocusStartedAt,
            focusChangesLastMinute: focusChangesLastMinute,
            activityInsight: activityInsight,
            now: now
        )
    }

    private func frictionCue(
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?,
        focusChangesLastMinute: Int,
        activityInsight: String?
    ) -> BehaviorCue? {
        guard focusChangesLastMinute >= 5 else {
            return nil
        }
        guard input?.secondsSinceAnyInput ?? .greatestFiniteMagnitude < 20 else {
            return nil
        }

        var payload = basePayload(
            cue: "friction_candidate",
            interpretation: "rapid_context_switching",
            currentFocus: currentFocus,
            activityInsight: activityInsight
        )
        payload["focus_changes_last_minute"] = "\(focusChangesLastMinute)"
        return BehaviorCue(
            name: "friction_candidate",
            insight: "Фрикция: резкие переключения контекста",
            confidence: 0.62,
            payload: payload
        )
    }

    private func postureCue(
        previous: AttentionSnapshot?,
        current: AttentionSnapshot?,
        secondsSincePrevious: TimeInterval?,
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?,
        activityInsight: String?
    ) -> BehaviorCue? {
        guard let previous, let current else {
            return nil
        }
        guard previous.facePresent, current.facePresent else {
            return nil
        }

        let seconds = secondsSincePrevious ?? 0
        guard seconds > 0, seconds <= 12 else {
            return nil
        }

        let centerShift = distance(
            previousX: previous.faceCenterX,
            previousY: previous.faceCenterY,
            currentX: current.faceCenterX,
            currentY: current.faceCenterY
        )
        let yawDelta = abs((current.yaw ?? 0) - (previous.yaw ?? 0))
        let pitchDelta = abs((current.pitch ?? 0) - (previous.pitch ?? 0))
        let rollDelta = abs((current.roll ?? 0) - (previous.roll ?? 0))
        let areaRatio = areaRatio(previous: previous.faceArea, current: current.faceArea)
        let motionScore = centerShift + yawDelta + pitchDelta + rollDelta

        if motionScore >= 0.55 || areaRatio >= 1.7 {
            var payload = basePayload(
                cue: "strong_reaction_candidate",
                interpretation: "sudden_posture_change",
                currentFocus: currentFocus,
                activityInsight: activityInsight
            )
            payload["motion_score"] = String(format: "%.3f", motionScore)
            payload["face_area_ratio"] = String(format: "%.2f", areaRatio)
            payload["seconds_since_previous_attention"] = String(format: "%.1f", seconds)
            if let idle = input?.secondsSinceAnyInput {
                payload["seconds_since_any_input"] = String(format: "%.1f", idle)
            }
            return BehaviorCue(
                name: "strong_reaction_candidate",
                insight: "Реакция: заметный резкий сдвиг",
                confidence: 0.48,
                payload: payload
            )
        }

        return nil
    }

    private func focusCue(
        currentAttention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?,
        currentFocusStartedAt: Date?,
        focusChangesLastMinute: Int,
        activityInsight: String?,
        now: Date
    ) -> BehaviorCue? {
        guard focusChangesLastMinute <= 1 else {
            return nil
        }
        guard currentAttention?.facePresent == true || currentAttention?.isTemporarilyLostFace == true else {
            return nil
        }
        guard let currentFocusStartedAt else {
            return nil
        }

        let focusSeconds = now.timeIntervalSince(currentFocusStartedAt)
        guard focusSeconds >= 300 else {
            return nil
        }
        guard input?.secondsSinceAnyInput ?? .greatestFiniteMagnitude < 90 else {
            return nil
        }

        var payload = basePayload(
            cue: "steady_focus",
            interpretation: "sustained_single_context",
            currentFocus: currentFocus,
            activityInsight: activityInsight
        )
        payload["focus_seconds"] = String(format: "%.1f", focusSeconds)
        payload["focus_changes_last_minute"] = "\(focusChangesLastMinute)"
        return BehaviorCue(
            name: "steady_focus",
            insight: "Фокус: держит один контекст",
            confidence: 0.7,
            payload: payload
        )
    }

    private func basePayload(
        cue: String,
        interpretation: String,
        currentFocus: AppFocusSnapshot?,
        activityInsight: String?
    ) -> [String: String] {
        var payload = [
            "cue": cue,
            "interpretation": interpretation
        ]

        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
            if let displayRole = currentFocus.displayRole {
                payload["display_role"] = displayRole.rawValue
            }
        }
        if let activityInsight {
            payload["activity_insight"] = activityInsight
        }

        return payload
    }

    private func distance(
        previousX: Double?,
        previousY: Double?,
        currentX: Double?,
        currentY: Double?
    ) -> Double {
        guard
            let previousX,
            let previousY,
            let currentX,
            let currentY
        else {
            return 0
        }

        let x = currentX - previousX
        let y = currentY - previousY
        return sqrt(x * x + y * y)
    }

    private func areaRatio(previous: Double?, current: Double?) -> Double {
        guard let previous, let current, previous > 0 else {
            return 1
        }
        return max(current / previous, previous / current)
    }
}
