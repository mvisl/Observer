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
        let appSurface = [
            context.appName,
            context.appID ?? "",
            context.windowTitle ?? "",
            context.document ?? ""
        ].joined(separator: " ").lowercased()
        let contentSurface = [
            context.focusedElementTitle ?? "",
            context.focusedElementValue ?? "",
            context.selectedText ?? "",
            text
        ].joined(separator: " ").lowercased()
        let haystack = [appSurface, contentSurface].joined(separator: " ")

        if haystack.contains("xcode") || haystack.contains("visual studio code") || haystack.contains("cursor") || haystack.contains("terminal") {
            return "code"
        }
        if appSurface.contains("telegram")
            || appSurface.contains("web.telegram")
            || appSurface.contains("whatsapp")
            || appSurface.contains("viber")
            || appSurface.contains("slack")
            || contentSurface.contains("telegram")
            || contentSurface.contains("whatsapp")
            || contentSurface.contains("viber") {
            return "message"
        }
        if appSurface.contains("mail")
            || contentSurface.contains("mail")
            || contentSurface.contains("subject:")
            || contentSurface.contains("from:") {
            return "email"
        }
        if appSurface.contains("chatgpt") || appSurface.contains("claude") || appSurface.contains("gemini") || appSurface.contains("codex") {
            return "prompt"
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
        let lower = text.lowercased()
        if let phrase = inferredHighSignalTopic(from: lower) {
            return phrase
        }

        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ")
            .prefix(9)
            .joined(separator: " ")

        let topic = cleaned.isEmpty ? fallback : cleaned
        return String(topic.prefix(90))
    }

    private func inferredHighSignalTopic(from lower: String) -> String? {
        if lower.contains("хакатон") {
            if lower.contains("бесполез") || lower.contains("задача ради задачи") || lower.contains("роль") {
                return "хакатон: роль, польза и ощущение бессмысленности"
            }
            return "хакатон и роль в процессе"
        }
        if lower.contains("приоритет") || lower.contains("главным") || lower.contains("второстеп") {
            return "приоритеты и что должно быть главным"
        }
        if lower.contains("карточ") && (lower.contains("описан") || lower.contains("тизер") || lower.contains("вопрос")) {
            return "структура карточек и уровень описаний"
        }
        if lower.contains("тупым роботом") || lower.contains("джира менеджмент") {
            return "фрустрация из-за процесса и менеджмента"
        }
        return nil
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
