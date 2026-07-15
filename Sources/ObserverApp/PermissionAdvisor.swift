import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

enum PermissionAdvisor {
    private enum PromptMemory {
        static let accessibilityKey = "observer.permissionPrompt.accessibility"
        static let screenRecordingKey = "observer.permissionPrompt.screenRecording"
        static let cameraKey = "observer.permissionPrompt.camera"

        static func wasAsked(_ key: String) -> Bool {
            UserDefaults.standard.bool(forKey: key)
        }

        static func markAsked(_ key: String) {
            UserDefaults.standard.set(true, forKey: key)
        }

        static func clear(_ key: String) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

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
        if AXIsProcessTrusted() {
            PromptMemory.clear(PromptMemory.accessibilityKey)
            return true
        }
        if PromptMemory.wasAsked(PromptMemory.accessibilityKey) {
            return false
        }
        PromptMemory.markAsked(PromptMemory.accessibilityKey)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            PromptMemory.clear(PromptMemory.screenRecordingKey)
            return true
        }
        if PromptMemory.wasAsked(PromptMemory.screenRecordingKey) {
            return false
        }
        PromptMemory.markAsked(PromptMemory.screenRecordingKey)
        return CGRequestScreenCaptureAccess()
    }

    static func requestCameraAccess(completion: @escaping @MainActor (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            PromptMemory.clear(PromptMemory.cameraKey)
            Task { @MainActor in
                completion(true)
            }

        case .notDetermined:
            if PromptMemory.wasAsked(PromptMemory.cameraKey) {
                Task { @MainActor in
                    completion(false)
                }
                return
            }
            PromptMemory.markAsked(PromptMemory.cameraKey)
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
