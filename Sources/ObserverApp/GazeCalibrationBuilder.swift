import Foundation

struct GazeCalibrationSample: Equatable {
    let targetSource: String
    let targetDisplayRole: WorkspaceTopology.DisplayRole?
    let targetScreenIndex: Int?
    let confidence: Double
    let payload: [String: String]
}

struct GazeCalibrationBuilder {
    func build(
        attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        currentFocus: AppFocusSnapshot?,
        activityInsight: String?
    ) -> GazeCalibrationSample? {
        guard let attention, attention.facePresent else {
            return nil
        }
        guard let input else {
            return nil
        }

        if input.secondsSinceKeyboard <= 3,
           currentFocus?.displayRole != nil || currentFocus?.screenIndex != nil {
            return sample(
                targetSource: "typing_caret_proxy",
                targetDisplayRole: currentFocus?.displayRole,
                targetScreenIndex: currentFocus?.screenIndex,
                confidence: 0.68,
                attention: attention,
                input: input,
                currentFocus: currentFocus,
                activityInsight: activityInsight
            )
        }

        if input.secondsSinceClick <= 2,
           input.mouseDisplayRole != nil || input.mouseScreenIndex != nil {
            return sample(
                targetSource: "mouse_click_proxy",
                targetDisplayRole: input.mouseDisplayRole,
                targetScreenIndex: input.mouseScreenIndex,
                confidence: 0.72,
                attention: attention,
                input: input,
                currentFocus: currentFocus,
                activityInsight: activityInsight
            )
        }

        if input.secondsSinceMouseMove <= 2,
           input.mouseDisplayRole != nil || input.mouseScreenIndex != nil {
            return sample(
                targetSource: "mouse_motion_proxy",
                targetDisplayRole: input.mouseDisplayRole,
                targetScreenIndex: input.mouseScreenIndex,
                confidence: 0.52,
                attention: attention,
                input: input,
                currentFocus: currentFocus,
                activityInsight: activityInsight
            )
        }

        return nil
    }

    private func sample(
        targetSource: String,
        targetDisplayRole: WorkspaceTopology.DisplayRole?,
        targetScreenIndex: Int?,
        confidence: Double,
        attention: AttentionSnapshot,
        input: InputActivitySnapshot,
        currentFocus: AppFocusSnapshot?,
        activityInsight: String?
    ) -> GazeCalibrationSample {
        var payload: [String: String] = [
            "target_source": targetSource,
            "face_position": attention.facePosition.rawValue,
            "seconds_since_keyboard": String(format: "%.1f", input.secondsSinceKeyboard),
            "seconds_since_mouse_move": String(format: "%.1f", input.secondsSinceMouseMove),
            "seconds_since_click": String(format: "%.1f", input.secondsSinceClick)
        ]

        if let targetDisplayRole {
            payload["target_display_role"] = targetDisplayRole.rawValue
        }
        if let targetScreenIndex {
            payload["target_screen_index"] = "\(targetScreenIndex)"
        }
        if let yaw = attention.yaw {
            payload["head_yaw"] = String(format: "%.4f", yaw)
        }
        if let pitch = attention.pitch {
            payload["head_pitch"] = String(format: "%.4f", pitch)
        }
        if let roll = attention.roll {
            payload["head_roll"] = String(format: "%.4f", roll)
        }
        if let faceCenterX = attention.faceCenterX {
            payload["face_center_x"] = String(format: "%.3f", faceCenterX)
        }
        if let faceCenterY = attention.faceCenterY {
            payload["face_center_y"] = String(format: "%.3f", faceCenterY)
        }
        if let currentFocus {
            payload["app_name"] = currentFocus.appName
            if let appID = currentFocus.appID {
                payload["app_id"] = appID
            }
            if let focusDisplayRole = currentFocus.displayRole {
                payload["focus_display_role"] = focusDisplayRole.rawValue
            }
        }
        if let mouseDisplayRole = input.mouseDisplayRole {
            payload["mouse_display_role"] = mouseDisplayRole.rawValue
        }
        if let activityInsight {
            payload["activity_insight"] = activityInsight
        }

        return GazeCalibrationSample(
            targetSource: targetSource,
            targetDisplayRole: targetDisplayRole,
            targetScreenIndex: targetScreenIndex,
            confidence: confidence,
            payload: payload
        )
    }
}
