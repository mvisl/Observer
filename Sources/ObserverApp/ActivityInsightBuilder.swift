import Foundation

struct ActivityInsightBuilder {
    func build(
        attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        topology: WorkspaceTopology,
        currentFocusStartedAt: Date?,
        focusChangesLastMinute: Int,
        now: Date = Date()
    ) -> String {
        let inputSignal = inputSignal(input)
        let cameraSignal = cameraSignal(attention, input: input, topology: topology)
        let focusSeconds = currentFocusStartedAt.map { max(0, now.timeIntervalSince($0)) }

        if focusChangesLastMinute >= 4 {
            return "Поиск: частые переключения · \(cameraSignal)"
        }

        if let attention, attention.isLookingAway {
            if input?.secondsSinceAnyInput ?? .greatestFiniteMagnitude < 20 {
                return "Фрикция: работа рывками · взгляд в сторону"
            }
            return "Пауза: взгляд в сторону · \(inputSignal)"
        }

        if let input, input.secondsSinceAnyInput >= 120 {
            if attention?.facePresent == true || attention?.isTemporarilyLostFace == true {
                return "Глубокое чтение: \(formatDuration(input.secondsSinceAnyInput)) без ввода"
            }
            return "Похоже, отошел · \(cameraSignal)"
        }

        if let input, input.secondsSinceAnyInput < 15 {
            if let focusSeconds, focusSeconds >= 180 {
                return "Фокус: устойчиво работает · \(cameraSignal)"
            }
            return "Разгон: активный ввод · \(cameraSignal)"
        }

        if let input, input.secondsSinceAnyInput < 75 {
            return "Микропауза: \(formatDuration(input.secondsSinceAnyInput)) · \(cameraSignal)"
        }

        if let focusSeconds, focusSeconds >= 300 {
            return "Фокус: долго в одном контексте · \(inputSignal)"
        }

        return "\(inputSignal) · \(cameraSignal)"
    }

    private func inputSignal(_ input: InputActivitySnapshot?) -> String {
        guard let input else {
            return "жду действий"
        }

        if input.secondsSinceAnyInput < 15 {
            return "идет работа"
        }
        if input.secondsSinceAnyInput < 75 {
            return "короткая пауза"
        }
        return "пауза \(formatDuration(input.secondsSinceAnyInput))"
    }

    private func cameraSignal(
        _ attention: AttentionSnapshot?,
        input: InputActivitySnapshot?,
        topology: WorkspaceTopology
    ) -> String {
        guard let attention else {
            return "камера ждет"
        }

        if attention.isTemporarilyLostFace {
            return "камера потеряла лицо"
        }

        guard attention.facePresent else {
            if let input, input.secondsSinceAnyInput < 60 {
                return "камера ищет лицо"
            }
            return "лица нет в кадре"
        }

        if attention.isLookingAway {
            return "взгляд в сторону"
        }

        if isSideMountedCamera(topology), attention.facePosition != .center {
            return "у экрана, камера сбоку"
        }

        return "лицо в кадре"
    }

    private func isSideMountedCamera(_ topology: WorkspaceTopology) -> Bool {
        guard let cameraDisplay = topology.cameraMountedDisplay else {
            return false
        }
        return cameraDisplay.position == .left || cameraDisplay.position == .right
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))с"
        }
        return "\(Int(seconds / 60))м"
    }
}

private extension AttentionSnapshot {
    var isLookingAway: Bool {
        guard let yaw else {
            return false
        }
        return abs(yaw) > 0.55
    }
}
