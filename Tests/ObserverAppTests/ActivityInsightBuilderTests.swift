import Foundation
import Testing
@testable import ObserverApp

struct ActivityInsightBuilderTests {
    @Test func describesActiveFocusBeyondPresence() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 2,
                secondsSinceMouseMove: 4,
                secondsSinceClick: 20,
                secondsSinceAnyInput: 2
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocusStartedAt: Date().addingTimeInterval(-240),
            focusChangesLastMinute: 0
        )

        #expect(text.contains("Фокус"))
        #expect(text.contains("устойчиво"))
    }

    @Test func describesSearchWhenSwitchingOften() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 1,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 5
        )

        #expect(text.contains("Поиск"))
    }

    @Test func doesNotTreatActiveMissingFaceAsAway() {
        let text = ActivityInsightBuilder().build(
            attention: AttentionSnapshot(
                facePresent: false,
                attentionZone: .offScreen,
                facePosition: .unknown,
                confidence: 0.25,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            ),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 2,
                secondsSinceMouseMove: 2,
                secondsSinceClick: 6,
                secondsSinceAnyInput: 2
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text.contains("Активная работа"))
        #expect(!text.contains("отошел"))
        #expect(!text.contains("камера"))
    }

    @Test func avoidsTechnicalCameraDetails() {
        let text = ActivityInsightBuilder().build(
            attention: face(yaw: 0, position: .right),
            input: InputActivitySnapshot(
                secondsSinceKeyboard: 1,
                secondsSinceMouseMove: 1,
                secondsSinceClick: 3,
                secondsSinceAnyInput: 1
            ),
            topology: .defaultTwoDisplaySetup,
            currentFocusStartedAt: Date(),
            focusChangesLastMinute: 0
        )

        #expect(text == "Активная работа")
        #expect(!text.contains("камера"))
        #expect(!text.contains("экран"))
    }

    private func face(
        yaw: Double,
        position: AttentionSnapshot.FacePosition
    ) -> AttentionSnapshot {
        AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: position,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.68,
            faceCenterY: 0.28,
            faceArea: 0.04,
            yaw: yaw,
            pitch: nil,
            roll: nil
        )
    }
}
