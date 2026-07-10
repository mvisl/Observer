import Foundation

enum PrivacyRedactor {
    private static let rules: [(pattern: String, replacement: String)] = [
        ("(?i)\\b(password|passcode|passwd|pwd|secret|token|api[_ -]?key|private[_ -]?key|seed phrase|mnemonic|otp|2fa)\\b\\s*[:=]\\s*\\S+", "$1: [redacted]"),
        ("\\b(?:\\d[ -]*?){13,19}\\b", "[redacted-card-like-number]"),
        ("\\b\\d{6}\\b", "[redacted-6-digit-code]"),
        ("\\b[A-Fa-f0-9]{32,}\\b", "[redacted-long-hex]"),
        ("\\b[A-Za-z0-9_\\-]{36,}\\b", "[redacted-long-token]")
    ]

    static func redact(_ value: String) -> String {
        rules.reduce(value) { current, rule in
            current.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
    }

    static func redact(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return redact(value)
    }
}
