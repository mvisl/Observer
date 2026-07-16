@preconcurrency import AVFoundation
@preconcurrency import CoreImage
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import Vision

final class CameraAttentionService: NSObject {
    private let session = AVCaptureSession()
    private let processingQueue = DispatchQueue(label: "local.observer.camera-attention")
    private var output: AVCaptureVideoDataOutput?
    private var handler: (@MainActor (AttentionSnapshot) -> Void)?
    private var isConfigured = false
    private var isRunning = false
    private var lastEmittedAt = Date.distantPast
    private var lastSceneClassificationAt = Date.distantPast
    private var minimumEmitInterval: TimeInterval = 15
    private var smileCandidateThreshold: Double = 0.62
    private var mouthOpenCandidateThreshold: Double = 0.62
    // General scene classification is materially heavier than face and hand
    // landmarks. It is a slow, shadow-only source, not a per-sample sensor.
    private let sceneClassificationInterval: TimeInterval = 30

    var isActive: Bool {
        isRunning
    }

    func start(
        minimumEmitInterval: TimeInterval,
        smileCandidateThreshold: Double = 0.62,
        mouthOpenCandidateThreshold: Double = 0.62,
        handler: @escaping @MainActor (AttentionSnapshot) -> Void
    ) throws {
        self.handler = handler
        self.minimumEmitInterval = minimumEmitInterval
        self.smileCandidateThreshold = smileCandidateThreshold
        self.mouthOpenCandidateThreshold = mouthOpenCandidateThreshold

        if !isConfigured {
            try configure()
        }

        guard !isRunning else {
            return
        }

        isRunning = true
        let session = self.session
        processingQueue.async {
            session.startRunning()
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        isRunning = false
        handler = nil
        let session = self.session
        processingQueue.async {
            session.stopRunning()
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraAttentionError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.setSampleBufferDelegate(self, queue: processingQueue)

        session.beginConfiguration()
        session.sessionPreset = .low

        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraAttentionError.configurationFailed
        }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        self.output = output
        isConfigured = true
    }

    private func process(_ sampleBuffer: CMSampleBuffer) {
        let now = Date()
        guard now.timeIntervalSince(lastEmittedAt) >= minimumEmitInterval else {
            return
        }
        lastEmittedAt = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let frameQuality = CameraFrameQuality.measure(pixelBuffer: pixelBuffer)

        let faceRequest = VNDetectFaceLandmarksRequest()
        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 2
        let shouldClassifyScene = now.timeIntervalSince(lastSceneClassificationAt) >= sceneClassificationInterval
        let classifyRequest = shouldClassifyScene ? VNClassifyImageRequest() : nil
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            var requests: [VNRequest] = [faceRequest, handRequest]
            if let classifyRequest {
                requests.append(classifyRequest)
                lastSceneClassificationAt = now
            }
            try requestHandler.perform(requests)
            let observations = faceRequest.results ?? []
            let handObservations = (handRequest.results ?? []).compactMap(HandPoseSample.init).map {
                AttentionSnapshot.HandPoseObservation(
                    wristX: $0.wristX,
                    wristY: $0.wristY,
                    confidence: $0.confidence
                )
            }
            let visualObjects = (classifyRequest?.results ?? [])
                .filter { $0.confidence >= 0.20 }
                .prefix(8)
                .map { AttentionSnapshot.CameraObjectObservation(label: $0.identifier, confidence: Double($0.confidence)) }
            let snapshot = AttentionSnapshot.from(
                faceObservations: observations,
                handObservations: handObservations,
                visualObjects: visualObjects,
                jpegData: observations.isEmpty ? nil : CameraFrameEncoder.jpegData(from: pixelBuffer),
                smileCandidateThreshold: smileCandidateThreshold,
                mouthOpenCandidateThreshold: mouthOpenCandidateThreshold,
                frameBrightness: frameQuality.brightness,
                frameSharpness: frameQuality.sharpness
            )
            let handler = self.handler
            Task { @MainActor in
                handler?(snapshot)
            }
        } catch {
            let snapshot = AttentionSnapshot(
                facePresent: false,
                attentionZone: .unknown,
                facePosition: .unknown,
                confidence: 0.1,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            )
            let handler = self.handler
            Task { @MainActor in
                handler?(snapshot)
            }
        }
    }
}

extension CameraAttentionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        process(sampleBuffer)
    }
}

enum CameraAttentionError: Error {
    case noCamera
    case configurationFailed
}

struct AttentionSnapshot: Sendable {
    enum AttentionZone: String, Sendable {
        case nearCamera = "near_camera"
        case offScreen = "off_screen"
        case unknown
    }

    enum FacePosition: String, Sendable {
        case left
        case center
        case right
        case unknown
    }

    struct CameraObjectObservation: Sendable, Equatable {
        let label: String
        let confidence: Double
    }

    struct HandPoseObservation: Sendable, Equatable {
        let wristX: Double
        let wristY: Double
        let confidence: Double
    }

    let facePresent: Bool
    let attentionZone: AttentionZone
    let facePosition: FacePosition
    let confidence: Double
    let faceCount: Int
    let faceCenterX: Double?
    let faceCenterY: Double?
    let faceArea: Double?
    let yaw: Double?
    let pitch: Double?
    let roll: Double?
    let eyeContactScore: Double?
    let eyeContactCandidate: Bool?
    let eyeSignalSource: String?
    let leftPupilX: Double?
    let leftPupilY: Double?
    let rightPupilX: Double?
    let rightPupilY: Double?
    let eyeVisibility: String?
    let smileScore: Double?
    let smileCandidate: Bool?
    let smileSignalSource: String?
    let mouthOpenScore: Double?
    let yawnCandidate: Bool?
    let mouthSignalSource: String?
    let frameBrightness: Double?
    let frameSharpness: Double?
    let visualObjects: [CameraObjectObservation]
    let handCount: Int
    let handNearFace: Bool
    let raisedHand: Bool
    let jpegData: Data?
    let isTemporarilyLostFace: Bool

    init(
        facePresent: Bool,
        attentionZone: AttentionZone,
        facePosition: FacePosition,
        confidence: Double,
        faceCount: Int,
        faceCenterX: Double?,
        faceCenterY: Double?,
        faceArea: Double?,
        yaw: Double?,
        pitch: Double?,
        roll: Double?,
        eyeContactScore: Double? = nil,
        eyeContactCandidate: Bool? = nil,
        eyeSignalSource: String? = nil,
        leftPupilX: Double? = nil,
        leftPupilY: Double? = nil,
        rightPupilX: Double? = nil,
        rightPupilY: Double? = nil,
        eyeVisibility: String? = nil,
        smileScore: Double? = nil,
        smileCandidate: Bool? = nil,
        smileSignalSource: String? = nil,
        mouthOpenScore: Double? = nil,
        yawnCandidate: Bool? = nil,
        mouthSignalSource: String? = nil,
        frameBrightness: Double? = nil,
        frameSharpness: Double? = nil,
        visualObjects: [CameraObjectObservation] = [],
        handCount: Int = 0,
        handNearFace: Bool = false,
        raisedHand: Bool = false,
        jpegData: Data? = nil,
        isTemporarilyLostFace: Bool = false
    ) {
        self.facePresent = facePresent
        self.attentionZone = attentionZone
        self.facePosition = facePosition
        self.confidence = confidence
        self.faceCount = faceCount
        self.faceCenterX = faceCenterX
        self.faceCenterY = faceCenterY
        self.faceArea = faceArea
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.eyeContactScore = eyeContactScore
        self.eyeContactCandidate = eyeContactCandidate
        self.eyeSignalSource = eyeSignalSource
        self.leftPupilX = leftPupilX
        self.leftPupilY = leftPupilY
        self.rightPupilX = rightPupilX
        self.rightPupilY = rightPupilY
        self.eyeVisibility = eyeVisibility
        self.smileScore = smileScore
        self.smileCandidate = smileCandidate
        self.smileSignalSource = smileSignalSource
        self.mouthOpenScore = mouthOpenScore
        self.yawnCandidate = yawnCandidate
        self.mouthSignalSource = mouthSignalSource
        self.frameBrightness = frameBrightness
        self.frameSharpness = frameSharpness
        self.visualObjects = visualObjects
        self.handCount = handCount
        self.handNearFace = handNearFace
        self.raisedHand = raisedHand
        self.jpegData = jpegData
        self.isTemporarilyLostFace = isTemporarilyLostFace
    }

    static func from(
        faceObservations: [VNFaceObservation],
        handObservations: [HandPoseObservation] = [],
        visualObjects: [CameraObjectObservation] = [],
        jpegData: Data? = nil,
        smileCandidateThreshold: Double = 0.62,
        mouthOpenCandidateThreshold: Double = 0.62,
        frameBrightness: Double? = nil,
        frameSharpness: Double? = nil
    ) -> AttentionSnapshot {
        guard let largestFace = faceObservations.max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else {
            return AttentionSnapshot(
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
                roll: nil,
                visualObjects: visualObjects,
                handCount: handObservations.count
            )
        }

        let box = largestFace.boundingBox
        let centerX = Double(box.midX)
        let centerY = Double(box.midY)
        let area = Double(box.width * box.height)
        let yaw = largestFace.yaw?.doubleValue
        let pitch = largestFace.pitch?.doubleValue
        let roll = largestFace.roll?.doubleValue
        let eyeContact = EyeContactEstimator().estimate(
            landmarks: largestFace.landmarks,
            yaw: yaw,
            pitch: pitch,
            roll: roll
        )
        let smile = SmileEstimator(candidateThreshold: smileCandidateThreshold).estimate(landmarks: largestFace.landmarks)
        let mouth = MouthOpenEstimator(candidateThreshold: mouthOpenCandidateThreshold).estimate(landmarks: largestFace.landmarks)
        let facePosition: FacePosition
        if centerX < 0.38 {
            facePosition = .left
        } else if centerX > 0.62 {
            facePosition = .right
        } else {
            facePosition = .center
        }

        let confidence = min(0.95, max(0.35, area * 6.0))
        let expandedFace = CGRect(
            x: max(0, box.minX - 0.18),
            y: max(0, box.minY - 0.20),
            width: min(1, box.width + 0.36),
            height: min(1, box.height + 0.40)
        )
        let handNearFace = handObservations.contains {
            expandedFace.contains(CGPoint(x: $0.wristX, y: $0.wristY))
        }
        let raisedHand = handObservations.contains {
            $0.wristY >= Double(box.midY - box.height * 0.35)
        }

        return AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: facePosition,
            confidence: confidence,
            faceCount: faceObservations.count,
            faceCenterX: centerX,
            faceCenterY: centerY,
            faceArea: area,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            eyeContactScore: eyeContact.score,
            eyeContactCandidate: eyeContact.isCandidate,
            eyeSignalSource: eyeContact.source,
            leftPupilX: eyeContact.leftPupilX,
            leftPupilY: eyeContact.leftPupilY,
            rightPupilX: eyeContact.rightPupilX,
            rightPupilY: eyeContact.rightPupilY,
            eyeVisibility: eyeContact.eyeVisibility,
            smileScore: smile.score,
            smileCandidate: smile.isCandidate,
            smileSignalSource: smile.source,
            mouthOpenScore: mouth.score,
            yawnCandidate: mouth.isYawnCandidate,
            mouthSignalSource: mouth.source,
            frameBrightness: frameBrightness,
            frameSharpness: frameSharpness,
            visualObjects: visualObjects,
            handCount: handObservations.count,
            handNearFace: handNearFace,
            raisedHand: raisedHand,
            jpegData: jpegData
        )
    }

    func asTemporarilyLostFace() -> AttentionSnapshot {
        AttentionSnapshot(
            facePresent: facePresent,
            attentionZone: attentionZone,
            facePosition: facePosition,
            confidence: min(confidence, 0.45),
            faceCount: faceCount,
            faceCenterX: faceCenterX,
            faceCenterY: faceCenterY,
            faceArea: faceArea,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            eyeContactScore: eyeContactScore,
            eyeContactCandidate: eyeContactCandidate,
            eyeSignalSource: eyeSignalSource,
            leftPupilX: leftPupilX,
            leftPupilY: leftPupilY,
            rightPupilX: rightPupilX,
            rightPupilY: rightPupilY,
            eyeVisibility: eyeVisibility,
            smileScore: smileScore,
            smileCandidate: smileCandidate,
            smileSignalSource: smileSignalSource,
            mouthOpenScore: mouthOpenScore,
            yawnCandidate: yawnCandidate,
            mouthSignalSource: mouthSignalSource,
            frameBrightness: frameBrightness,
            frameSharpness: frameSharpness,
            visualObjects: visualObjects,
            handCount: handCount,
            handNearFace: handNearFace,
            raisedHand: raisedHand,
            jpegData: jpegData,
            isTemporarilyLostFace: true
        )
    }

    var displayText: String {
        if facePresent {
            return "Attention: face \(facePosition.rawValue)"
        }
        return "Attention: off screen"
    }

    var eventPayload: [String: String] {
        var payload: [String: String] = [
            "face_present": facePresent ? "true" : "false",
            "attention_zone": attentionZone.rawValue,
            "face_position": facePosition.rawValue,
            "face_count": "\(faceCount)",
            "calibration_version": "camera-attention-v3",
            "validity_gate": facePresent ? "valid_face_track" : "no_face_track"
        ]

        if let faceCenterX {
            payload["face_center_x"] = String(format: "%.3f", faceCenterX)
        }
        if let faceCenterY {
            payload["face_center_y"] = String(format: "%.3f", faceCenterY)
        }
        if let faceArea {
            payload["face_area"] = String(format: "%.4f", faceArea)
        }
        if let yaw {
            payload["head_yaw"] = String(format: "%.4f", yaw)
        }
        if let pitch {
            payload["head_pitch"] = String(format: "%.4f", pitch)
        }
        if let roll {
            payload["head_roll"] = String(format: "%.4f", roll)
        }
        if let eyeContactScore {
            payload["eye_contact_score"] = String(format: "%.3f", eyeContactScore)
        }
        if let eyeContactCandidate {
            payload["eye_contact_candidate"] = eyeContactCandidate ? "true" : "false"
        }
        if let eyeSignalSource {
            payload["eye_signal_source"] = eyeSignalSource
        }
        if let leftPupilX {
            payload["left_pupil_x"] = String(format: "%.3f", leftPupilX)
        }
        if let leftPupilY {
            payload["left_pupil_y"] = String(format: "%.3f", leftPupilY)
        }
        if let rightPupilX {
            payload["right_pupil_x"] = String(format: "%.3f", rightPupilX)
        }
        if let rightPupilY {
            payload["right_pupil_y"] = String(format: "%.3f", rightPupilY)
        }
        if let eyeVisibility {
            payload["eye_visibility"] = eyeVisibility
        }
        if let smileScore {
            payload["smile_score"] = String(format: "%.3f", smileScore)
        }
        if let smileCandidate {
            payload["smile_candidate"] = smileCandidate ? "true" : "false"
        }
        if let smileSignalSource {
            payload["smile_signal_source"] = smileSignalSource
        }
        if let mouthOpenScore {
            payload["mouth_open_score"] = String(format: "%.3f", mouthOpenScore)
        }
        if let yawnCandidate {
            payload["yawn_candidate"] = yawnCandidate ? "true" : "false"
        }
        if let mouthSignalSource {
            payload["mouth_signal_source"] = mouthSignalSource
        }
        if let frameBrightness {
            payload["frame_brightness"] = String(format: "%.3f", frameBrightness)
        }
        if let frameSharpness {
            payload["frame_sharpness"] = String(format: "%.4f", frameSharpness)
        }
        if !visualObjects.isEmpty {
            payload["visual_object_candidates"] = visualObjects
                .map { "\($0.label):\(String(format: "%.2f", $0.confidence))" }
                .joined(separator: ",")
            payload["visual_object_candidate_count"] = "\(visualObjects.count)"
            payload["visual_object_policy"] = "shadow_only_destroy_frame_after_inference"
        }
        if handCount > 0 {
            payload["hand_count"] = "\(handCount)"
            payload["hand_near_face"] = handNearFace ? "true" : "false"
            payload["raised_hand"] = raisedHand ? "true" : "false"
            payload["hand_pose_policy"] = "frame_local_shadow_signal"
        }
        if isTemporarilyLostFace {
            payload["temporarily_lost_face"] = "true"
        }

        return payload
    }
}

private struct HandPoseSample {
    let wristX: Double
    let wristY: Double
    let confidence: Double

    init?(_ observation: VNHumanHandPoseObservation) {
        guard let wrist = try? observation.recognizedPoint(.wrist), wrist.confidence >= 0.35 else {
            return nil
        }
        wristX = Double(wrist.location.x)
        wristY = Double(wrist.location.y)
        confidence = Double(wrist.confidence)
    }
}

private struct CameraFrameQuality {
    let brightness: Double?
    let sharpness: Double?

    static func measure(pixelBuffer: CVPixelBuffer) -> CameraFrameQuality {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
              let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        else {
            return CameraFrameQuality(brightness: nil, sharpness: nil)
        }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 1, height > 1 else {
            return CameraFrameQuality(brightness: nil, sharpness: nil)
        }

        let stride = max(1, min(width, height) / 72)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)
        var luminanceTotal = 0.0
        var gradientTotal = 0.0
        var samples = 0
        for y in Swift.stride(from: stride, to: height - stride, by: stride) {
            for x in Swift.stride(from: stride, to: width - stride, by: stride) {
                let value = Double(pixels[y * rowBytes + x])
                let left = Double(pixels[y * rowBytes + x - stride])
                let above = Double(pixels[(y - stride) * rowBytes + x])
                luminanceTotal += value
                gradientTotal += abs(value - left) + abs(value - above)
                samples += 1
            }
        }
        guard samples > 0 else {
            return CameraFrameQuality(brightness: nil, sharpness: nil)
        }
        return CameraFrameQuality(
            brightness: luminanceTotal / Double(samples) / 255,
            sharpness: gradientTotal / Double(samples) / 510
        )
    }
}

private struct SmileEstimate {
    let score: Double?
    let isCandidate: Bool?
    let source: String?
}

private struct SmileEstimator {
    let candidateThreshold: Double

    func estimate(landmarks: VNFaceLandmarks2D?) -> SmileEstimate {
        guard let mouth = landmarks?.outerLips, !mouth.normalizedPoints.isEmpty else {
            return SmileEstimate(score: nil, isCandidate: nil, source: nil)
        }

        let points = mouth.normalizedPoints
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = Double(maxX - minX)
        let height = Double(maxY - minY)
        guard width > 0, height > 0 else {
            return SmileEstimate(score: nil, isCandidate: nil, source: nil)
        }

        // A weak local proxy: smiling usually widens the mouth relative to its height.
        let ratio = width / max(height, 0.001)
        let score = min(1, max(0, (ratio - 2.2) / 1.4))
        return SmileEstimate(
            score: score,
            isCandidate: score >= candidateThreshold,
            source: "outer_lips_aspect_ratio"
        )
    }
}

private struct MouthOpenEstimate {
    let score: Double?
    let isYawnCandidate: Bool?
    let source: String?
}

private struct MouthOpenEstimator {
    let candidateThreshold: Double

    func estimate(landmarks: VNFaceLandmarks2D?) -> MouthOpenEstimate {
        guard let mouth = landmarks?.outerLips, !mouth.normalizedPoints.isEmpty else {
            return MouthOpenEstimate(score: nil, isYawnCandidate: nil, source: nil)
        }

        let points = mouth.normalizedPoints
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let width = Double(maxX - minX)
        let height = Double(maxY - minY)
        guard width > 0, height > 0 else {
            return MouthOpenEstimate(score: nil, isYawnCandidate: nil, source: nil)
        }

        let openness = height / max(width, 0.001)
        let score = min(1, max(0, (openness - 0.28) / 0.34))
        return MouthOpenEstimate(
            score: score,
            isYawnCandidate: score >= candidateThreshold,
            source: "outer_lips_open_ratio"
        )
    }
}

private enum CameraFrameEncoder {
    private static let context = CIContext()

    static func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return context.jpegRepresentation(
            of: image,
            colorSpace: colorSpace,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.72]
        )
    }
}

private struct EyeContactEstimate {
    let score: Double?
    let isCandidate: Bool?
    let source: String?
    let leftPupilX: Double?
    let leftPupilY: Double?
    let rightPupilX: Double?
    let rightPupilY: Double?
    let eyeVisibility: String?
}

private struct EyeContactEstimator {
    func estimate(
        landmarks: VNFaceLandmarks2D?,
        yaw: Double?,
        pitch: Double?,
        roll: Double?
    ) -> EyeContactEstimate {
        let headScore = frontalHeadScore(yaw: yaw, pitch: pitch, roll: roll)
        let left = pupilPosition(eye: landmarks?.leftEye, pupil: landmarks?.leftPupil)
        let right = pupilPosition(eye: landmarks?.rightEye, pupil: landmarks?.rightPupil)

        if let left, let right {
            let leftScore = centeredPupilScore(left)
            let rightScore = centeredPupilScore(right)
            let pupilScore = (leftScore + rightScore) / 2
            let score = min(1, max(0, pupilScore * 0.65 + headScore * 0.35))
            return EyeContactEstimate(
                score: score,
                isCandidate: score >= 0.58,
                source: "pupil_landmarks",
                leftPupilX: left.x,
                leftPupilY: left.y,
                rightPupilX: right.x,
                rightPupilY: right.y,
                eyeVisibility: "pupil_landmarks"
            )
        }

        let eyeLandmarksVisible = landmarks?.leftEye?.normalizedPoints.isEmpty == false
            && landmarks?.rightEye?.normalizedPoints.isEmpty == false

        return EyeContactEstimate(
            score: headScore,
            isCandidate: headScore >= 0.72,
            source: "head_pose_only",
            leftPupilX: nil,
            leftPupilY: nil,
            rightPupilX: nil,
            rightPupilY: nil,
            eyeVisibility: eyeLandmarksVisible ? "eye_contours_only" : "occluded_or_unavailable"
        )
    }

    private func pupilPosition(
        eye: VNFaceLandmarkRegion2D?,
        pupil: VNFaceLandmarkRegion2D?
    ) -> CGPoint? {
        guard
            let eye,
            let pupil,
            !eye.normalizedPoints.isEmpty,
            !pupil.normalizedPoints.isEmpty
        else {
            return nil
        }

        let eyePoints = eye.normalizedPoints
        let minX = eyePoints.map(\.x).min() ?? 0
        let maxX = eyePoints.map(\.x).max() ?? 0
        let minY = eyePoints.map(\.y).min() ?? 0
        let maxY = eyePoints.map(\.y).max() ?? 0
        let width = maxX - minX
        let height = maxY - minY
        guard width > 0, height > 0 else {
            return nil
        }

        let pupilPoints = pupil.normalizedPoints
        let pupilX = pupilPoints.map(\.x).reduce(0, +) / CGFloat(pupilPoints.count)
        let pupilY = pupilPoints.map(\.y).reduce(0, +) / CGFloat(pupilPoints.count)
        return CGPoint(
            x: min(1, max(0, (pupilX - minX) / width)),
            y: min(1, max(0, (pupilY - minY) / height))
        )
    }

    private func centeredPupilScore(_ point: CGPoint) -> Double {
        let dx = Double(point.x - 0.5)
        let dy = Double(point.y - 0.5)
        let distance = sqrt(dx * dx + dy * dy)
        return min(1, max(0, 1 - distance / 0.35))
    }

    private func frontalHeadScore(yaw: Double?, pitch: Double?, roll: Double?) -> Double {
        let yawPenalty = min(abs(yaw ?? 0) / 0.42, 1)
        let pitchPenalty = min(abs(pitch ?? 0) / 0.35, 1)
        let rollPenalty = min(abs(roll ?? 0) / 0.45, 1)
        return min(1, max(0, 1 - (yawPenalty * 0.5 + pitchPenalty * 0.3 + rollPenalty * 0.2)))
    }
}
