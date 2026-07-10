@preconcurrency import AVFoundation
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
    private var minimumEmitInterval: TimeInterval = 15

    var isActive: Bool {
        isRunning
    }

    func start(
        minimumEmitInterval: TimeInterval,
        handler: @escaping @MainActor (AttentionSnapshot) -> Void
    ) throws {
        self.handler = handler
        self.minimumEmitInterval = minimumEmitInterval

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

        let request = VNDetectFaceLandmarksRequest()
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try requestHandler.perform([request])
            let observations = request.results ?? []
            let snapshot = AttentionSnapshot.from(faceObservations: observations)
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

    static func from(faceObservations: [VNFaceObservation]) -> AttentionSnapshot {
        guard let largestFace = faceObservations.max(by: { lhs, rhs in
            lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
        }) else {
            return AttentionSnapshot(
                facePresent: false,
                attentionZone: .offScreen,
                facePosition: .unknown,
                confidence: 0.85,
                faceCount: 0,
                faceCenterX: nil,
                faceCenterY: nil,
                faceArea: nil,
                yaw: nil,
                pitch: nil,
                roll: nil
            )
        }

        let box = largestFace.boundingBox
        let centerX = Double(box.midX)
        let centerY = Double(box.midY)
        let area = Double(box.width * box.height)
        let facePosition: FacePosition
        if centerX < 0.38 {
            facePosition = .left
        } else if centerX > 0.62 {
            facePosition = .right
        } else {
            facePosition = .center
        }

        let confidence = min(0.95, max(0.35, area * 6.0))

        return AttentionSnapshot(
            facePresent: true,
            attentionZone: .nearCamera,
            facePosition: facePosition,
            confidence: confidence,
            faceCount: faceObservations.count,
            faceCenterX: centerX,
            faceCenterY: centerY,
            faceArea: area,
            yaw: largestFace.yaw?.doubleValue,
            pitch: largestFace.pitch?.doubleValue,
            roll: largestFace.roll?.doubleValue
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
            "face_count": "\(faceCount)"
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

        return payload
    }
}
