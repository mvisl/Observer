import Foundation
import Testing
@testable import ObserverApp

struct BehaviorCueBuilderTests {
    @Test func detectsFrictionFromRapidSwitching() throws {
        let cue = try #require(BehaviorCueBuilder().build(
            previousAttention: nil,
            currentAttention: face(x: 0.5, y: 0.5),
            secondsSincePreviousAttention: nil,
            input: input(secondsSinceAnyInput: 2),
            currentFocus: focus(appName: "Google Chrome"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 6,
            activityInsight: "Поиск / сравнение: много переключений"
        ))

        #expect(cue.name == "friction_candidate")
        #expect(cue.payload["interpretation"] == "rapid_context_switching")
    }

    @Test func detectsStrongPostureReaction() throws {
        let cue = try #require(BehaviorCueBuilder().build(
            previousAttention: face(x: 0.4, y: 0.4, area: 0.03, yaw: 0),
            currentAttention: face(x: 0.72, y: 0.58, area: 0.08, yaw: 0.35),
            secondsSincePreviousAttention: 5,
            input: input(secondsSinceAnyInput: 4),
            currentFocus: focus(appName: "Music"),
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0,
            activityInsight: "Музыка: слушает"
        ))

        #expect(cue.name == "strong_reaction_candidate")
        #expect(cue.payload["interpretation"] == "sudden_posture_change")
    }

    @Test func detectsSteadyFocus() throws {
        let cue = try #require(BehaviorCueBuilder().build(
            previousAttention: nil,
            currentAttention: face(x: 0.5, y: 0.5),
            secondsSincePreviousAttention: nil,
            input: input(secondsSinceAnyInput: 12),
            currentFocus: focus(appName: "Figma"),
            currentFocusStartedAt: Date().addingTimeInterval(-420),
            focusChangesLastMinute: 0,
            activityInsight: "Дизайн: устойчиво в задаче"
        ))

        #expect(cue.name == "steady_focus")
        #expect(cue.payload["interpretation"] == "sustained_single_context")
    }

    private func face(
        x: Double,
        y: Double,
        area: Double = 0.04,
        yaw: Double? = nil
    ) -> AttentionSnapshot {
        AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.75,
            faceCount: 1,
            faceCenterX: x,
            faceCenterY: y,
            faceArea: area,
            yaw: yaw,
            pitch: nil,
            roll: nil
        )
    }

    private func input(secondsSinceAnyInput: Double) -> InputActivitySnapshot {
        InputActivitySnapshot(
            secondsSinceKeyboard: secondsSinceAnyInput,
            secondsSinceMouseMove: secondsSinceAnyInput,
            secondsSinceClick: secondsSinceAnyInput,
            secondsSinceAnyInput: secondsSinceAnyInput
        )
    }

    private func focus(appName: String) -> AppFocusSnapshot {
        AppFocusSnapshot(
            appID: nil,
            appName: appName,
            processID: 1,
            windowTitle: nil,
            screenIndex: nil,
            displayRole: nil,
            contentAllowed: false
        )
    }
}
