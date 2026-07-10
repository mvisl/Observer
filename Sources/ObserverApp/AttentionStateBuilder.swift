import Foundation

struct AttentionStateBuilder {
    func build(
        attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        settings: ObserverSettings,
        topology: WorkspaceTopology? = nil
    ) -> String {
        "\(buildInputState(input, settings: settings)) · \(buildCameraState(attention, input: input, topology: topology))"
    }

    private func buildInputState(
        _ input: InputActivitySnapshot?,
        settings: ObserverSettings
    ) -> String {
        guard let input else {
            return "Жду активности"
        }

        if input.secondsSinceAnyInput < 15 {
            return "Активно работает"
        }

        if input.secondsSinceAnyInput >= settings.readingPauseSecondsForDisplay {
            return "Думает / читает"
        }

        if input.secondsSinceAnyInput < 75 {
            return "Короткая пауза"
        }

        return "Читает / пауза"
    }

    private func buildCameraState(
        _ attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        topology: WorkspaceTopology?
    ) -> String {
        guard let attention else {
            return "камера выключена"
        }

        if attention.isTemporarilyLostFace {
            return "у экрана (камера потеряла лицо)"
        }

        guard attention.facePresent else {
            if let input, input.secondsSinceAnyInput < 60 {
                return "камера ищет лицо"
            }
            return "не у экрана"
        }

        if let yaw = attention.yaw {
            if yaw > 0.45 {
                return "смотрит в сторону"
            }
            if yaw < -0.45 {
                return "смотрит в сторону"
            }
        }

        if isSideMountedCamera(topology), attention.facePosition != .center {
            return "у экрана (камера сбоку)"
        }

        return "смотрит на экран"
    }

    private func isSideMountedCamera(_ topology: WorkspaceTopology?) -> Bool {
        guard let cameraDisplay = topology?.cameraMountedDisplay else {
            return false
        }
        return cameraDisplay.position == .left || cameraDisplay.position == .right
    }
}

private extension ObserverSettings {
    var readingPauseSecondsForDisplay: Double {
        min(detectorSettings.readingPauseSeconds, 180)
    }
}
