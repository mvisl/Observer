import Testing
@testable import ObserverApp

struct AttentionStateBuilderTests {
    @Test func describesCameraOff() {
        let text = AttentionStateBuilder().build(
            attention: nil,
            input: nil,
            settings: .defaults
        )
        #expect(text.contains("камера выключена"))
    }

    @Test func describesOffScreen() {
        let attention = AttentionSnapshot(
            facePresent: false,
            attentionZone: .offScreen,
            facePosition: .unknown,
            confidence: 0.8,
            faceCount: 0,
            faceCenterX: nil,
            faceCenterY: nil,
            faceArea: nil,
            yaw: nil,
            pitch: nil,
            roll: nil
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: nil,
            settings: .defaults
        )
        #expect(text.contains("не у экрана"))
    }

    @Test func doesNotCallActiveUserAwayWhenFaceIsMissing() {
        let attention = AttentionSnapshot(
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
        )
        let input = InputActivitySnapshot(
            secondsSinceKeyboard: 2,
            secondsSinceMouseMove: 1,
            secondsSinceClick: 9,
            secondsSinceAnyInput: 1
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: input,
            settings: .defaults
        )
        #expect(text.contains("камера ищет лицо"))
        #expect(!text.contains("не у экрана"))
    }

    @Test func describesThinking() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.5,
            faceCenterY: 0.5,
            faceArea: 0.2,
            yaw: nil,
            pitch: nil,
            roll: nil
        )
        let input = InputActivitySnapshot(
            secondsSinceKeyboard: 200,
            secondsSinceMouseMove: 200,
            secondsSinceClick: 200,
            secondsSinceAnyInput: 200
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: input,
            settings: .defaults
        )
        #expect(text.contains("Думает"))
    }

    @Test func describesSideMountedCameraWithoutCallingItAway() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .right,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.68,
            faceCenterY: 0.3,
            faceArea: 0.04,
            yaw: 0,
            pitch: nil,
            roll: nil
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: nil,
            settings: .defaults,
            topology: .defaultTwoDisplaySetup
        )
        #expect(text.contains("камера сбоку"))
    }

    @Test func combinesScreenInputAndCameraPresence() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .right,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.68,
            faceCenterY: 0.3,
            faceArea: 0.04,
            yaw: 0,
            pitch: nil,
            roll: nil
        )
        let input = InputActivitySnapshot(
            secondsSinceKeyboard: 4,
            secondsSinceMouseMove: 2,
            secondsSinceClick: 30,
            secondsSinceAnyInput: 2
        )

        let text = AttentionStateBuilder().build(
            attention: attention,
            input: input,
            settings: .defaults,
            topology: .defaultTwoDisplaySetup
        )
        #expect(text.contains("Активно работает"))
        #expect(text.contains("у экрана"))
    }

    @Test func includesEyeContactPayloadWhenAvailable() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.5,
            faceCenterY: 0.4,
            faceArea: 0.05,
            yaw: 0,
            pitch: 0,
            roll: 0,
            eyeContactScore: 0.82,
            eyeContactCandidate: true,
            eyeSignalSource: "pupil_landmarks",
            leftPupilX: 0.51,
            leftPupilY: 0.48,
            rightPupilX: 0.49,
            rightPupilY: 0.47
        )

        #expect(attention.eventPayload["eye_contact_candidate"] == "true")
        #expect(attention.eventPayload["eye_signal_source"] == "pupil_landmarks")
        #expect(attention.eventPayload["left_pupil_x"] == "0.510")
        #expect(attention.eventPayload["calibration_version"] == "camera-attention-v3")
        #expect(attention.eventPayload["validity_gate"] == "valid_face_track")
    }

    @Test func includesSmilePayloadWhenAvailable() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.5,
            faceCenterY: 0.4,
            faceArea: 0.05,
            yaw: 0,
            pitch: 0,
            roll: 0,
            smileScore: 0.78,
            smileCandidate: true,
            smileSignalSource: "outer_lips_aspect_ratio"
        )

        #expect(attention.eventPayload["smile_candidate"] == "true")
        #expect(attention.eventPayload["smile_score"] == "0.780")
        #expect(attention.eventPayload["smile_signal_source"] == "outer_lips_aspect_ratio")
    }

    @Test func includesYawnPayloadWhenAvailable() {
        let attention = AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: .center,
            confidence: 0.8,
            faceCount: 1,
            faceCenterX: 0.5,
            faceCenterY: 0.4,
            faceArea: 0.05,
            yaw: 0,
            pitch: 0,
            roll: 0,
            mouthOpenScore: 0.72,
            yawnCandidate: true,
            mouthSignalSource: "outer_lips_open_ratio"
        )

        #expect(attention.eventPayload["yawn_candidate"] == "true")
        #expect(attention.eventPayload["mouth_open_score"] == "0.720")
        #expect(attention.eventPayload["mouth_signal_source"] == "outer_lips_open_ratio")
    }
}
