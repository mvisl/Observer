import Foundation

struct TextAffectCue: Equatable {
    let name: String
    let insight: String
    let confidence: Double
    let payload: [String: String]
}

struct TextAffectCueBuilder {
    func build(
        text: String,
        appName: String?,
        activityInsight: String?
    ) -> TextAffectCue? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 8 else {
            return nil
        }

        var markers: [String] = []
        let lowercased = normalized.lowercased()

        let frustrationWords = [
            "злюсь",
            "бесит",
            "хует",
            "хуй",
            "пизд",
            "говн",
            "ненавиж",
            "строго запрещено",
            "не помог",
            "сломал",
            "не работает"
        ]

        if frustrationWords.contains(where: { lowercased.contains($0) }) {
            markers.append("strong_negative_language")
        }
        if normalized.contains("!!!") || normalized.contains("???") {
            markers.append("repeated_punctuation")
        }
        if containsLongUppercaseRun(normalized) {
            markers.append("uppercase_emphasis")
        }
        if lowercased.contains("правил") || lowercased.contains("запрещ") {
            markers.append("rule_violation_context")
        }
        if containsVisualDesignFriction(lowercased) {
            markers.append("visual_design_friction")
        }

        let hasStrongEvidence = markers.contains("strong_negative_language")
            || markers.contains("visual_design_friction")
            || (markers.contains("rule_violation_context") && markers.count >= 2)
            || (markers.contains("repeated_punctuation") && markers.contains("uppercase_emphasis"))
        guard hasStrongEvidence else {
            return nil
        }

        let confidence = min(0.9, 0.48 + Double(markers.count) * 0.12)
        var payload: [String: String] = [
            "cue": "frustration_candidate",
            "interpretation": "frustrated_writing_tone",
            "markers": markers.joined(separator: ","),
            "text_length": "\(normalized.count)"
        ]
        if markers.contains("visual_design_friction") {
            // The phrase is evidence, not a diagnosis. The causal source is resolved only
            // when fresh independent context is available in the fusion layer.
            payload["mentioned_context"] = "visual_design"
        }
        if let appName {
            payload["app_name"] = appName
        }
        if let activityInsight {
            payload["activity_insight"] = activityInsight
        }

        return TextAffectCue(
            name: "frustration_candidate",
            insight: "Фрикция: резкая реакция в текущем контексте",
            confidence: confidence,
            payload: payload
        )
    }

    private func containsVisualDesignFriction(_ text: String) -> Bool {
        [
            "какафони",
            "визуаль",
            "дизайн",
            "хаос",
            "развал",
            "разъех",
            "крив",
            "лишние элементы",
            "не нужные элементы",
            "не сходится",
            "плохо выглядит"
        ].contains { text.contains($0) }
    }

    private func containsLongUppercaseRun(_ text: String) -> Bool {
        let tokens = text
            .split { !$0.isLetter }
            .map(String.init)

        return tokens.contains { token in
            guard token.count >= 5 else {
                return false
            }
            let letters = token.filter(\.isLetter)
            guard !letters.isEmpty else {
                return false
            }
            return letters.allSatisfy { String($0).uppercased() == String($0) }
        }
    }
}
