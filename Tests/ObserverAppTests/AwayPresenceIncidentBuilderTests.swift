import Testing
@testable import ObserverApp

struct AwayPresenceIncidentBuilderTests {
    @Test func detectsPersonSeenAfterAwayIdlePeriod() throws {
        let incident = try #require(AwayPresenceIncidentBuilder().build(
            currentAttention: facePresent(),
            missingFaceSamplesBeforeCurrent: 12,
            input: input(secondsSinceAnyInput: 300),
            currentFocus: focus(),
            activityInsight: "Защита: экран заблокирован"
        ))

        #expect(incident.payload["cue"] == "presence_detected_after_away")
        #expect(incident.payload["owner_identity"] == "unverified")
        #expect(incident.payload["capture_policy"] == "local_security_snapshot_only")
        #expect(incident.payload["microphone_capture"] == "disabled")
    }

    @Test func detectsShortProtectiveAbsenceWhenFaceReappearsAfterIdle() throws {
        let incident = try #require(AwayPresenceIncidentBuilder().build(
            currentAttention: facePresent(),
            missingFaceSamplesBeforeCurrent: 6,
            input: input(secondsSinceAnyInput: 45),
            currentFocus: focus(),
            activityInsight: nil
        ))

        #expect(incident.payload["cue"] == "presence_detected_after_away")
        #expect(incident.payload["seconds_since_any_input"] == "45.0")
    }

    @Test func confirmedAwayDoesNotRequireLongMissingFaceWindow() throws {
        let incident = try #require(AwayPresenceIncidentBuilder().build(
            currentAttention: facePresent(),
            missingFaceSamplesBeforeCurrent: 1,
            confirmedAwayBeforeCurrent: true,
            input: input(secondsSinceAnyInput: 10),
            currentFocus: focus(),
            activityInsight: nil
        ))

        #expect(incident.payload["cue"] == "presence_detected_after_away")
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

    @Test func ignoresShortSideCameraFaceLossWhileUserMayStillBePresent() {
        let incident = AwayPresenceIncidentBuilder().build(
            currentAttention: facePresent(),
            missingFaceSamplesBeforeCurrent: 4,
            input: input(secondsSinceAnyInput: 180),
            currentFocus: focus(),
            activityInsight: "Дизайн: долгая пауза"
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
