import Testing
@testable import ObserverApp

struct AwayPresenceIncidentBuilderTests {
    @Test func detectsPersonSeenAfterAwayIdlePeriod() throws {
        let incident = try #require(AwayPresenceIncidentBuilder().build(
            currentAttention: facePresent(),
            missingFaceSamplesBeforeCurrent: 4,
            input: input(secondsSinceAnyInput: 180),
            currentFocus: focus(),
            activityInsight: "Похоже, отошел"
        ))

        #expect(incident.payload["cue"] == "presence_detected_after_away")
        #expect(incident.payload["owner_identity"] == "unverified")
        #expect(incident.payload["capture_policy"] == "no_hidden_screenshot_no_audio")
        #expect(incident.payload["microphone_capture"] == "disabled")
    }

    @Test func ignoresNormalPresentUser() {
        let incident = AwayPresenceIncidentBuilder().build(
            currentAttention: facePresent(),
            missingFaceSamplesBeforeCurrent: 0,
            input: input(secondsSinceAnyInput: 5),
            currentFocus: focus(),
            activityInsight: "Диалог с ИИ: основной экран"
        )

        #expect(incident == nil)
    }

    private func facePresent() -> AttentionSnapshot {
        AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.75,
            faceCount: 1,
            faceCenterX: 0.5,
            faceCenterY: 0.5,
            faceArea: 0.04,
            yaw: nil,
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

    private func focus() -> AppFocusSnapshot {
        AppFocusSnapshot(
            appID: "com.google.Chrome",
            appName: "Google Chrome",
            processID: 1,
            windowTitle: "Inbox",
            screenIndex: 0,
            displayRole: .productivity,
            contentAllowed: true
        )
    }
}
