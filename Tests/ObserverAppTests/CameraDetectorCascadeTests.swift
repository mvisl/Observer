import Foundation
import Testing
@testable import ObserverApp

struct CameraDetectorCascadeTests {
    @Test func parsesOpenFaceSidecarResponse() {
        let now = Date()
        let line = #"{"confidence":0.92,"aus":{"AU06":1.1,"au12":1.4,"au04":0.2},"gaze_yaw":-0.13,"gaze_pitch":0.08}"#

        let sample = OpenFaceSidecarResponseParser().parse(line: line, receivedAt: now)

        #expect(sample?.confidence == 0.92)
        #expect(sample?.aus["au06"] == 1.1)
        #expect(sample?.aus["au12"] == 1.4)
        #expect(sample?.gazeYaw == -0.13)
        #expect(sample?.payload["raw_frame_storage"] == "forbidden")
        #expect(sample?.payload["shadow_mode"] == "true")
    }

    @Test func normalizesAUsAgainstPersonalBaseline() {
        let normalizer = CameraAUNormalizer()
        let baselineEvents = [
            event(.cameraTier2Sample, payload: ["au12": "0.20", "calibration_version": "v1"]),
            event(.cameraTier2Sample, payload: ["au12": "0.25", "calibration_version": "v1"]),
            event(.cameraTier2Sample, payload: ["au12": "0.30", "calibration_version": "v1"]),
            event(.cameraTier2Sample, payload: ["au12": "1.80", "active_camera_cue": "true", "calibration_version": "v1"])
        ]
        let baselines = normalizer.baselines(from: baselineEvents, calibrationVersion: "v1")
        let sample = OpenFaceTier2Sample(
            timestamp: Date(),
            aus: ["au12": 0.55],
            gazeYaw: nil,
            gazePitch: nil,
            confidence: 0.9,
            calibrationVersion: "v1"
        )

        let payload = normalizer.normalizedPayload(sample: sample, baselines: baselines)

        #expect(payload["au12_baseline_n"] == "3")
        #expect(Double(payload["au12_z"] ?? "") ?? 0 > 3)
        #expect(payload["normalization"] == "personal_hourly_au_zscore")
    }

    @Test func emitsTemporalTrajectoryOnlyAfterDurationAndHysteresis() {
        let start = Date()
        let samples = [
            CameraCueTemporalModel.Sample(timestamp: start, value: 1.4, eventID: "a"),
            CameraCueTemporalModel.Sample(timestamp: start.addingTimeInterval(0.4), value: 1.2, eventID: "b"),
            CameraCueTemporalModel.Sample(timestamp: start.addingTimeInterval(0.8), value: 0.8, eventID: "c"),
            CameraCueTemporalModel.Sample(timestamp: start.addingTimeInterval(1.2), value: 0.2, eventID: "d")
        ]
        let config = CameraCueTemporalModel.Config(
            cue: "smile_duchenne_candidate",
            primaryMetric: "au06_au12_z",
            onsetMinimumSeconds: 0.3,
            minimumDurationSeconds: 0.5,
            maximumDurationSeconds: 4,
            enterThreshold: 1.0,
            exitThreshold: 0.6,
            integration: "peak"
        )

        let payload = CameraCueTemporalModel().completedTrajectory(samples: samples, config: config)

        #expect(payload?["cue"] == "smile_duchenne_candidate")
        #expect(payload?["cascade_stage"] == "temporal_trajectory")
        #expect(payload?["evidence_event_ids"] == "a,b,c")
        #expect(payload?["display_eligible"] == "false")
    }

    private func event(_ type: ObserverEventType, payload: [String: String]) -> ObserverEvent {
        ObserverEvent(
            id: UUID(),
            timestamp: Date(),
            type: type,
            source: "test",
            platform: "macOS",
            displayRole: nil,
            appID: nil,
            confidence: 0.8,
            payload: payload,
            workspaceTopologyVersion: 1
        )
    }
}
