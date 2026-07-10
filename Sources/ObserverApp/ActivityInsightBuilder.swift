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
        let presence = presenceSignal(attention, input: input)
        let focusSeconds = currentFocusStartedAt.map { max(0, now.timeIntervalSince($0)) }

        if focusChangesLastMinute >= 4 {
            return "Поиск: частые переключения"
        }

        if let attention, attention.isLookingAway {
            if input?.secondsSinceAnyInput ?? .greatestFiniteMagnitude < 20 {
                return "Фрикция: работа рывками"
            }
            return "Пауза: внимание ушло в сторону"
        }

        if let input, input.secondsSinceAnyInput >= 120 {
            if attention?.facePresent == true || attention?.isTemporarilyLostFace == true {
                return "Глубокое чтение: \(formatDuration(input.secondsSinceAnyInput)) без ввода"
            }
            return presence == .away
                ? "Похоже, отошел"
                : "Долгая пауза: возможно думает"
        }

        if let input, input.secondsSinceAnyInput < 15 {
            if let focusSeconds, focusSeconds >= 180 {
                return "Фокус: устойчиво работает"
            }
            return "Активная работа"
        }

        if let input, input.secondsSinceAnyInput < 75 {
            return "Микропауза: \(formatDuration(input.secondsSinceAnyInput))"
        }

        if let focusSeconds, focusSeconds >= 300 {
            return "Фокус: долго в одном контексте"
        }

        return "Пауза: возможно читает"
    }

    private enum PresenceSignal {
        case present
        case uncertain
        case away
    }

    private func presenceSignal(
        _ attention: AttentionSnapshot?,
        input: InputActivitySnapshot?
    ) -> PresenceSignal {
        guard let attention else {
            return .uncertain
        }

        if attention.isTemporarilyLostFace {
            return .present
        }

        guard attention.facePresent else {
            if let input, input.secondsSinceAnyInput < 60 {
                return .uncertain
            }
            return .away
        }

        return .present
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
