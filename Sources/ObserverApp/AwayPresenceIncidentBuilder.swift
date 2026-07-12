import Foundation

struct AwayPresenceIncident: Equatable {
    let confidence: Double
    let payload: [String: String]
}

struct AwayPresenceIncidentBuilder {
    func build(
        currentAttention: AttentionSnapshot,
        missingFaceSamplesBeforeCurrent: Int,
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?,
        activityInsight: String?
    ) -> AwayPresenceIncident? {
        guard currentAttention.facePresent else {
            return nil
        }
        guard missingFaceSamplesBeforeCurrent >= 12 else {
            return nil
        }
        guard let input, input.secondsSinceAnyInput >= 300 else {
            return nil
        }

        var payload: [String: String] = [
            "cue": "presence_detected_after_away",
            "interpretation": "person_seen_after_idle_absence",
            "owner_identity": "unverified",
            "capture_policy": "local_security_snapshot_only",
            "microphone_capture": "disabled",
            "screen_image_capture": "local_on_incident",
            "visible_notice_required": "true",
            "seconds_since_any_input": String(format: "%.1f", input.secondsSinceAnyInput),
            "missing_face_samples_before_current": "\(missingFaceSamplesBeforeCurrent)"
        ]

        if let activityInsight {
            payload["activity_insight"] = activityInsight
        }
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
            if let displayRole = currentFocus.displayRole {
                payload["display_role"] = displayRole.rawValue
            }
            if currentFocus.contentAllowed, let windowTitle = currentFocus.windowTitle {
                payload["window_title"] = windowTitle
            }
        }

        return AwayPresenceIncident(confidence: 0.64, payload: payload)
    }
}
