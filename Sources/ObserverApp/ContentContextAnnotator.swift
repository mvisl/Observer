import Foundation

struct ContentContextAnnotation: Equatable {
    let contentKind: String
    let sourceEntityDisplayName: String?
    let topic: String
    let sentiment: String
    let language: String
    let isIncoming: Bool
    let rawFragment: String?

    var payload: [String: String] {
        var payload: [String: String] = [
            "content_kind": contentKind,
            "topic": topic,
            "sentiment": sentiment,
            "language": language,
            "is_incoming": isIncoming ? "true" : "false"
        ]
        if let sourceEntityDisplayName {
            payload["source_entity_display_name"] = sourceEntityDisplayName
        }
        if let rawFragment {
            payload["raw_fragment"] = rawFragment
        }
        return payload
    }
}

struct ContentContextAnnotator {
    func annotate(
        context: ScreenContextSnapshot,
        allowRawKinds: Set<String>
    ) -> ContentContextAnnotation? {
        let text = context.combinedTextForAnnotation
        guard !text.isEmpty else {
            return nil
        }

        let kind = classifyKind(context: context, text: text)
        let scrubbedText = PrivacyRedactor.redact(text)
        let topic = topicPhrase(from: scrubbedText, fallback: context.windowTitle ?? context.appName)
        let rawFragment = allowRawKinds.contains(kind) ? String(scrubbedText.prefix(500)) : nil

        return ContentContextAnnotation(
            contentKind: kind,
            sourceEntityDisplayName: sourceEntityName(context: context, kind: kind),
            topic: topic,
            sentiment: sentiment(text: scrubbedText),
            language: language(text: scrubbedText),
            isIncoming: isIncoming(context: context, kind: kind),
            rawFragment: rawFragment
        )
    }

    private func classifyKind(context: ScreenContextSnapshot, text: String) -> String {
        let haystack = [
            context.appName,
            context.appID ?? "",
            context.windowTitle ?? "",
            context.focusedElementRole ?? "",
            text
        ].joined(separator: " ").lowercased()

        if haystack.contains("chatgpt") || haystack.contains("claude") || haystack.contains("gemini") || haystack.contains("codex") {
            return "prompt"
        }
        if haystack.contains("xcode") || haystack.contains("visual studio code") || haystack.contains("cursor") || haystack.contains("terminal") {
            return "code"
        }
        if haystack.contains("mail") || haystack.contains("@") {
            return "email"
        }
        if haystack.contains("telegram") || haystack.contains("whatsapp") || haystack.contains("slack") {
            return "message"
        }
        if haystack.contains("youtube") || haystack.contains("video") {
            return "video"
        }
        if haystack.contains("docs") || haystack.contains("pages") || haystack.contains("notion") {
            return "doc"
        }
        if haystack.contains("chrome") || haystack.contains("safari") || haystack.contains("firefox") {
            return "article"
        }
        return "feed"
    }

    private func sourceEntityName(context: ScreenContextSnapshot, kind: String) -> String? {
        guard ["message", "email"].contains(kind) else {
            return nil
        }
        let title = (context.windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }
        return title
            .replacingOccurrences(of: " - WhatsApp", with: "")
            .replacingOccurrences(of: " - Telegram", with: "")
            .replacingOccurrences(of: " — Slack", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func topicPhrase(from text: String, fallback: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .prefix(9)
            .joined(separator: " ")

        let topic = cleaned.isEmpty ? fallback : cleaned
        return String(topic.prefix(90))
    }

    private func sentiment(text: String) -> String {
        let lower = text.lowercased()
        let negative = ["хует", "хуета", "злюсь", "бесит", "wrong", "bad", "hate", "angry", "shit", "fuck"]
            .contains { lower.contains($0) }
        let positive = ["спасибо", "отлично", "класс", "улыб", "love", "great", "nice", "thanks"]
            .contains { lower.contains($0) }
        if positive && negative {
            return "mixed"
        }
        if positive {
            return "pos"
        }
        if negative {
            return "neg"
        }
        return "neutral"
    }

    private func language(text: String) -> String {
        if text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil {
            return "ru"
        }
        return "en"
    }

    private func isIncoming(context: ScreenContextSnapshot, kind: String) -> Bool {
        guard ["message", "email"].contains(kind) else {
            return false
        }
        return context.hasTextualFocus == false
    }
}

private extension ScreenContextSnapshot {
    var combinedTextForAnnotation: String {
        [
            windowTitle,
            document,
            focusedElementTitle,
            selectedText,
            focusedElementValue
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
