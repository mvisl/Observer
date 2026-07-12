import CoreGraphics
import Foundation
import ImageIO

final class OwnerFaceRecognizer {
    private var ownerFingerprints: [UInt64] = []
    private let maximumFingerprints = 16
    private let hammingThreshold = 18

    var hasProfile: Bool {
        !ownerFingerprints.isEmpty
    }

    func learnOwnerFace(from jpegData: Data?) {
        guard let fingerprint = visualFingerprint(from: jpegData) else {
            return
        }
        ownerFingerprints.append(fingerprint)
        if ownerFingerprints.count > maximumFingerprints {
            ownerFingerprints.removeFirst(ownerFingerprints.count - maximumFingerprints)
        }
    }

    func isOwnerFace(_ jpegData: Data?) -> Bool? {
        guard !ownerFingerprints.isEmpty,
              let current = visualFingerprint(from: jpegData)
        else {
            return nil
        }
        let best = ownerFingerprints.map { Self.hammingDistance(current, $0) }.min() ?? Int.max
        return best <= hammingThreshold
    }

    private func visualFingerprint(from jpegData: Data?) -> UInt64? {
        guard let jpegData,
              let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let average = pixels.reduce(0) { $0 + Int($1) } / max(1, pixels.count)
        var hash: UInt64 = 0
        for (index, pixel) in pixels.enumerated() where Int(pixel) >= average {
            hash |= UInt64(1) << UInt64(index)
        }
        return hash
    }

    private static func hammingDistance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}
