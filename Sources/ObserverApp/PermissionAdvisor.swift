import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

enum PermissionAdvisor {
    struct Status {
        let accessibility: Bool
        let camera: String
        let screenRecording: Bool
    }

    static func currentStatus() -> Status {
        let cameraStatus: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraStatus = "authorized"
        case .notDetermined:
            cameraStatus = "not_determined"
        case .denied:
            cameraStatus = "denied"
        case .restricted:
            cameraStatus = "restricted"
        @unknown default:
            cameraStatus = "unknown"
        }

        return Status(
            accessibility: AXIsProcessTrusted(),
            camera: cameraStatus,
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    static func requestAccessibilityAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    static func requestCameraAccess(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            Task { @MainActor in
                completion(true)
            }

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    completion(granted)
                }
            }

        case .denied, .restricted:
            Task { @MainActor in
                completion(false)
            }

        @unknown default:
            Task { @MainActor in
                completion(false)
            }
        }
    }
}
