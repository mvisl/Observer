import Foundation

/// Keeps expensive feature-print generation off the application's main actor.
/// The profile stays in memory only and is destroyed with the process.
final class HeadphoneAppearanceService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.observer.headphone-appearance", qos: .utility)
    private let stateLock = NSLock()
    private var profile = HeadphoneAppearanceProfile()
    private var isProcessing = false

    func observe(
        jpegData: Data?,
        facePresent: Bool,
        faceCenterX: Double?,
        faceCenterY: Double?,
        faceArea: Double?,
        genericHeadphoneConfidence: Double?,
        audioOutputIndicatesHeadphones: Bool,
        confirmedWearing: Bool,
        completion: @escaping @MainActor (HeadphoneVisualState) -> Void
    ) {
        stateLock.lock()
        guard !isProcessing else {
            stateLock.unlock()
            return
        }
        isProcessing = true
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.isProcessing = false
                self.stateLock.unlock()
            }
            let state = self.profile.observe(
                jpegData: jpegData,
                facePresent: facePresent,
                faceCenterX: faceCenterX,
                faceCenterY: faceCenterY,
                faceArea: faceArea,
                genericHeadphoneConfidence: genericHeadphoneConfidence,
                audioOutputIndicatesHeadphones: audioOutputIndicatesHeadphones,
                confirmedWearing: confirmedWearing
            )
            Task { @MainActor in
                completion(state)
            }
        }
    }
}
