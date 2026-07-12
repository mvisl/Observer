import Foundation

enum PrivacyRedactor {
    private static let secretFieldPattern = "(?i)\\b(password|passcode|passwd|pwd|secret|token|api[_ -]?key|private[_ -]?key|mnemonic|otp|2fa)\\b\\s*[:=]\\s*\\S+"
    private static let privateKeyPattern = "(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"
    private static let ibanPattern = "\\b[A-Z]{2}\\d{2}[A-Z0-9]{11,30}\\b"
    private static let twoFactorPattern = "(?i)\\b(verification|verify|code|otp|2fa|one[- ]time)\\D{0,24}\\b\\d{4,8}\\b"
    private static let uuidPattern = "\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\b"
    private static let longHexPattern = "\\b[A-Fa-f0-9]{32,}\\b"
    private static let longTokenPattern = "\\b[A-Za-z0-9_\\-]{36,}\\b"
    private static let bip39ProbeWords: Set<String> = [
        "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
        "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
        "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",
        "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance",
        "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
        "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album",
        "alcohol", "alert", "alien", "all", "alley", "allow", "almost", "alone",
        "alpha", "already", "also", "alter", "always", "amateur", "amazing", "among"
    ]

    static func redact(_ value: String) -> String {
        var protectedUUIDs: [String] = []
        var redacted = protectUUIDs(in: value, into: &protectedUUIDs)
        redacted = replace(pattern: secretFieldPattern, in: redacted, with: "$1: [secret:credential]")
        redacted = replace(pattern: twoFactorPattern, in: redacted, with: "$1 [secret:2fa_code]")
        redacted = replace(pattern: ibanPattern, in: redacted, with: "[secret:iban]")
        redacted = redactCardNumbers(in: redacted)
        redacted = redactSeedPhrases(in: redacted)
        redacted = replace(pattern: longHexPattern, in: redacted, with: "[secret:hex_token]")
        redacted = replace(pattern: longTokenPattern, in: redacted, with: "[secret:token]")
        redacted = replace(pattern: privateKeyPattern, in: redacted, with: "[secret:private_key]")
        return restoreUUIDs(in: redacted, from: protectedUUIDs)
    }

    static func redact(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return redact(value)
    }

    private static func replace(pattern: String, in value: String, with replacement: String) -> String {
        value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: .regularExpression
        )
    }

    private static func protectUUIDs(in value: String, into protected: inout [String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: uuidPattern) else {
            return value
        }
        var result = value
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        for match in regex.matches(in: value, range: nsRange).reversed() {
            guard let range = Range(match.range, in: value) else {
                continue
            }
            let index = protected.count
            protected.append(String(value[range]))
            result.replaceSubrange(range, with: "__OBSERVER_UUID_\(index)__")
        }
        return result
    }

    private static func restoreUUIDs(in value: String, from protected: [String]) -> String {
        var result = value
        for (index, uuid) in protected.enumerated() {
            result = result.replacingOccurrences(of: "__OBSERVER_UUID_\(index)__", with: uuid)
        }
        return result
    }

    private static func redactCardNumbers(in value: String) -> String {
        let pattern = "\\b(?:\\d[ -]*?){13,19}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return value
        }

        var result = value
        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        for match in regex.matches(in: value, range: nsRange).reversed() {
            guard let range = Range(match.range, in: value) else {
                continue
            }
            let digits = String(value[range].filter(\.isNumber))
            guard luhnValid(digits) else {
                continue
            }
            result.replaceSubrange(range, with: "[secret:card_pan]")
        }
        return result
    }

    private static func luhnValid(_ digits: String) -> Bool {
        guard digits.count >= 13, digits.count <= 19 else {
            return false
        }
        var sum = 0
        for (index, digit) in digits.reversed().compactMap(\.wholeNumberValue).enumerated() {
            if index.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum % 10 == 0
    }

    private static func redactSeedPhrases(in value: String) -> String {
        let words = value.lowercased().split { !$0.isLetter }.map(String.init)
        guard words.count >= 12 else {
            return value
        }

        var currentRun = 0
        var longestRun = 0
        for word in words {
            if bip39ProbeWords.contains(word) {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return longestRun >= 12 ? "[secret:seed_phrase]" : value
    }
}
