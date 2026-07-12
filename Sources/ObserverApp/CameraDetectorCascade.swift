import Foundation

struct OpenFaceTier2Sample: Equatable {
    let timestamp: Date
    let aus: [String: Double]
    let gazeYaw: Double?
    let gazePitch: Double?
    let confidence: Double
    let calibrationVersion: String

    var payload: [String: String] {
        var payload: [String: String] = [
            "tier": "openface3_sidecar",
            "model": "OpenFace-3.0",
            "confidence": String(format: "%.3f", confidence),
            "calibration_version": calibrationVersion,
            "raw_frame_retained": "false",
            "raw_frame_storage": "forbidden",
            "transport": "local_unix_socket_or_memory",
            "shadow_mode": "true"
        ]
        for au in Self.supportedAUs {
            if let value = aus[au] {
                payload[au] = String(format: "%.4f", value)
            }
        }
        if let gazeYaw {
            payload["gaze_yaw"] = String(format: "%.4f", gazeYaw)
        }
        if let gazePitch {
            payload["gaze_pitch"] = String(format: "%.4f", gazePitch)
        }
        return payload
    }

    static let supportedAUs = ["au01", "au04", "au06", "au12", "au23", "au24", "au43", "au45"]
}

struct OpenFaceSidecarResponseParser {
    func parse(line: String, receivedAt: Date = Date(), calibrationVersion: String = "camera-attention-v3") -> OpenFaceTier2Sample? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let confidence = object["confidence"] as? Double ?? object["face_confidence"] as? Double ?? 0
        guard confidence > 0 else {
            return nil
        }

        var aus: [String: Double] = [:]
        if let rawAUs = object["aus"] as? [String: Any] {
            for au in OpenFaceTier2Sample.supportedAUs {
                if let value = rawAUs[au] as? Double ?? rawAUs[au.uppercased()] as? Double {
                    aus[au] = value
                }
            }
        }
        for au in OpenFaceTier2Sample.supportedAUs where aus[au] == nil {
            if let value = object[au] as? Double ?? object[au.uppercased()] as? Double {
                aus[au] = value
            }
        }
        guard !aus.isEmpty else {
            return nil
        }

        return OpenFaceTier2Sample(
            timestamp: receivedAt,
            aus: aus,
            gazeYaw: object["gaze_yaw"] as? Double,
            gazePitch: object["gaze_pitch"] as? Double,
            confidence: confidence,
            calibrationVersion: calibrationVersion
        )
    }
}

struct CameraAUNormalizer {
    struct Baseline: Equatable {
        let median: Double
        let scale: Double
        let sampleCount: Int
    }

    func baselines(from events: [ObserverEvent], calibrationVersion: String? = nil) -> [String: Baseline] {
        var valuesByAU: [String: [Double]] = [:]
        for event in events where event.type == .cameraTier2Sample {
            if let calibrationVersion,
               event.payload["calibration_version"] != calibrationVersion {
                continue
            }
            if event.payload["active_camera_cue"] == "true" {
                continue
            }
            for au in OpenFaceTier2Sample.supportedAUs {
                if let value = Double(event.payload[au] ?? "") {
                    valuesByAU[au, default: []].append(value)
                }
            }
        }
        return valuesByAU.mapValues { values in
            let median = percentile(values, 0.5)
            let deviations = values.map { abs($0 - median) }
            let mad = percentile(deviations, 0.5)
            return Baseline(median: median, scale: max(mad * 1.4826, 0.05), sampleCount: values.count)
        }
    }

    func normalizedPayload(sample: OpenFaceTier2Sample, baselines: [String: Baseline]) -> [String: String] {
        var payload = sample.payload
        for au in OpenFaceTier2Sample.supportedAUs {
            guard let value = sample.aus[au],
                  let baseline = baselines[au]
            else {
                continue
            }
            let z = (value - baseline.median) / baseline.scale
            payload["\(au)_z"] = String(format: "%.3f", z)
            payload["\(au)_baseline_median"] = String(format: "%.4f", baseline.median)
            payload["\(au)_baseline_n"] = "\(baseline.sampleCount)"
        }
        payload["normalization"] = "personal_hourly_au_zscore"
        return payload
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[index]
    }
}

struct CameraCueTemporalModel {
    struct Config: Equatable {
        let cue: String
        let primaryMetric: String
        let onsetMinimumSeconds: Double
        let minimumDurationSeconds: Double
        let maximumDurationSeconds: Double
        let enterThreshold: Double
        let exitThreshold: Double
        let integration: String
    }

    struct Sample: Equatable {
        let timestamp: Date
        let value: Double
        let eventID: String?
    }

    func completedTrajectory(samples: [Sample], config: Config, now: Date = Date()) -> [String: String]? {
        let ordered = samples.sorted { $0.timestamp < $1.timestamp }
        var active: [Sample] = []

        for sample in ordered {
            if sample.value >= config.enterThreshold || (!active.isEmpty && sample.value >= config.exitThreshold) {
                active.append(sample)
            } else if !active.isEmpty {
                break
            }
        }

        guard let first = active.first, let last = active.last else {
            return nil
        }
        let duration = max(0, last.timestamp.timeIntervalSince(first.timestamp))
        guard duration >= config.minimumDurationSeconds,
              duration <= config.maximumDurationSeconds,
              duration >= config.onsetMinimumSeconds
        else {
            return nil
        }

        let peak = active.map(\.value).max() ?? 0
        let area = active.map(\.value).reduce(0, +) / Double(max(active.count, 1))
        let integrated = config.integration == "area" ? area : peak

        return [
            "cue": config.cue,
            "primary_metric": config.primaryMetric,
            "integration": config.integration,
            "integrated_value": String(format: "%.3f", integrated),
            "peak_value": String(format: "%.3f", peak),
            "duration_seconds": String(format: "%.2f", duration),
            "started_at": ISO8601DateFormatter().string(from: first.timestamp),
            "ended_at": ISO8601DateFormatter().string(from: last.timestamp),
            "evidence_event_ids": active.compactMap(\.eventID).joined(separator: ","),
            "cascade_stage": "temporal_trajectory",
            "shadow_mode": "true",
            "display_eligible": "false"
        ]
    }
}

struct CameraDetectorABReportBuilder {
    func build(events: [ObserverEvent]) -> [String: String] {
        let labels = events.filter { $0.type == .userLabel }
        let old = metrics(events: events, detector: "tier1")
        let cascade = metrics(events: events, detector: "cascade")
        return [
            "report_kind": "camera_detector_ab",
            "validation_window_days": "14",
            "labels_n": "\(labels.count)",
            "tier1_precision": String(format: "%.3f", old.precision),
            "tier1_recall_proxy": String(format: "%.3f", old.recallProxy),
            "cascade_precision": String(format: "%.3f", cascade.precision),
            "cascade_recall_proxy": String(format: "%.3f", cascade.recallProxy),
            "recommendation": cascade.precision > old.precision && cascade.recallProxy >= old.recallProxy ? "switch_after_full_window" : "keep_shadow",
            "shadow_mode": "true"
        ]
    }

    private func metrics(events: [ObserverEvent], detector: String) -> (precision: Double, recallProxy: Double) {
        let cues = events.filter { event in
            event.type == .behaviorCue
                && (event.payload["detector_tier"] == detector || event.payload["cascade_detector"] == detector)
        }
        let labeledIDs = Set(events
            .filter { $0.type == .userLabel && $0.payload["label"] == "true" }
            .compactMap { $0.payload["target_event_id"] })
        let truePositive = cues.filter { labeledIDs.contains($0.id.uuidString) }.count
        let precision = cues.isEmpty ? 0 : Double(truePositive) / Double(cues.count)
        let recallProxy = labeledIDs.isEmpty ? 0 : Double(truePositive) / Double(labeledIDs.count)
        return (precision, recallProxy)
    }
}
