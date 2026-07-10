import AppKit
import CoreGraphics
import Foundation
import Vision

struct OCRResult {
    let appID: String?
    let appName: String
    let windowTitle: String?
    let text: String
    let confidence: Double
    let lineCount: Int
}

struct ScreenOCRService {
    func recognizeText(for focus: AppFocusSnapshot) throws -> OCRResult? {
        guard let image = captureImage(for: focus.processID) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap { observation -> (String, Float)? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            return (candidate.string, candidate.confidence)
        }

        let text = PrivacyRedactor.redact(sanitize(lines.map(\.0).joined(separator: " ")))
        guard !text.isEmpty else {
            return nil
        }

        let averageConfidence = lines.isEmpty
            ? 0.0
            : Double(lines.map(\.1).reduce(0, +) / Float(lines.count))

        return OCRResult(
            appID: focus.appID,
            appName: focus.appName,
            windowTitle: focus.windowTitle,
            text: text,
            confidence: averageConfidence,
            lineCount: lines.count
        )
    }

    private func captureImage(for processID: pid_t) -> CGImage? {
        guard
            let windowInfo = frontWindowInfo(for: processID),
            let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
            let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else {
            return nil
        }

        return CGWindowListCreateImage(
            bounds,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
    }

    private func frontWindowInfo(for processID: pid_t) -> [String: Any]? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return info.first { window in
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == processID,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                return false
            }

            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1.0
            return alpha > 0
        }
    }

    private func sanitize(_ value: String) -> String {
        var sanitized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while sanitized.contains("  ") {
            sanitized = sanitized.replacingOccurrences(of: "  ", with: " ")
        }

        if sanitized.count > 1_500 {
            let index = sanitized.index(sanitized.startIndex, offsetBy: 1_500)
            return String(sanitized[..<index]) + "..."
        }

        return sanitized
    }
}

extension OCRResult {
    var eventPayload: [String: String] {
        var payload: [String: String] = [
            "app_name": appName,
            "content_source": "vision_ocr",
            "text": text,
            "line_count": "\(lineCount)"
        ]
        if let appID {
            payload["app_id"] = appID
        }
        if let windowTitle {
            payload["window_title"] = windowTitle
        }
        return payload
    }
}
