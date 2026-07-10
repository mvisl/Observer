import Foundation

struct GeminiInsightProvider {
    private struct InteractionRequest: Encodable {
        let model: String
        let store: Bool
        let input: String
    }

    struct InteractionResponse: Decodable {
        struct Step: Decodable {
            let type: String?
            let content: [Content]?
        }

        struct Content: Decodable {
            let type: String?
            let text: String?
        }

        let steps: [Step]?
    }

    private struct ErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    let apiKey: String
    let model: String

    func generateInsight(context: String, digest: String, attention: String) async throws -> String {
        try await generate(prompt: Self.buildPrompt(context: context, digest: digest, attention: attention))
    }

    func generateWidgetInsight(context: String, digest: String, attention: String) async throws -> String {
        let text = try await generate(prompt: Self.buildWidgetPrompt(context: context, digest: digest, attention: attention))
        return Self.extractWidgetLine(from: text)
    }

    func generateDailyInsight(context: String, digest: String, attention: String) async throws -> String {
        try await generate(prompt: Self.buildDailyPrompt(context: context, digest: digest, attention: attention))
    }

    private func generate(prompt: String) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1/interactions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        request.httpBody = try JSONEncoder().encode(
            InteractionRequest(model: model, store: false, input: prompt)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiInsightError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error?.message)
            throw GeminiInsightError.requestFailed(status: httpResponse.statusCode, message: message)
        }

        return try Self.extractInsight(from: data)
    }

    static func buildPrompt(context: String, digest: String, attention: String) -> String {
        """
        You are Observer's on-demand external reasoning layer.

        The app observes work locally and sends you only a compact, user-triggered context packet.
        Read it as imperfect telemetry. Do not invent facts.

        Produce:
        1. likely current task,
        2. useful behavioral insight,
        3. one concrete next action,
        4. one idea for improving Observer itself.

        Keep the answer concise, practical, and in Russian.

        Current soft attention state:
        \(attention)

        Local research digest:
        \(digest)

        Context pack:
        \(context)
        """
    }

    static func buildWidgetPrompt(context: String, digest: String, attention: String) -> String {
        """
        You are Observer's higher-level sensemaking layer for a tiny macOS floating widget.

        The local system sends imperfect telemetry. Treat low-level activity labels like "switching tabs",
        "reading page", "active work", or "formulating a task" only as evidence. Never output them.
        If the screen content contains a conversation, read the actual topic and emotional tone first:
        dispute, joking, relief, frustration, priority negotiation, decision pressure, or recovery.
        Facial signals are not diagnoses; use them as tone modifiers for the content.

        Infer the user's current work situation at the second or third level:
        - what tension, blocker, loop, decision, or abstraction the user is dealing with;
        - what the current conversation is really about, if communication is visible;
        - whether an emotional reaction may affect the next work block;
        - why the recent app/content switches matter;
        - what would be useful to notice now.

        Return STRICT JSON only:
        {"widget_line":"short Russian line, max 86 chars","confidence":0.0,"evidence":["event/source phrase"],"next_action":"optional short Russian action"}

        Good widget_line examples:
        - "Пилюля: ищешь не статус, а рабочую гипотезу"
        - "Observer: конфликт между телеметрией и смыслом инсайта"
        - "ИИ-связка: уточняешь, как объяснить критерий качества"
        - "Переписка: спор о приоритетах карточек разряжается шуткой"
        - "Общение со Стасом даёт подъём перед возвратом в задачу"

        Bad widget_line examples:
        - "Веб-контекст: переключает вкладки"
        - "Диалог с ИИ: формулирует задачу"
        - "Коммуникация: отвечает"
        - "Активная работа"

        Current soft attention state:
        \(attention)

        Local research digest:
        \(digest)

        Context pack:
        \(context)
        """
    }

    static func buildDailyPrompt(context: String, digest: String, attention: String) -> String {
        """
        You are Observer's daily pattern-mining layer.

        The input is imperfect local telemetry from one workday. Do not diagnose personality or mental health.
        Do not summarize low-level actions. Infer behavioral patterns only when multiple evidence streams agree.

        Produce concise Russian markdown with:
        1. Главный паттерн дня: one clear pattern with evidence.
        2. Рабочий инсайт: why this pattern matters for tomorrow.
        3. Задел на будущее: what Observer should watch next time.
        4. Неуверенность: what may be wrong or noisy in the data.

        Prefer formulations like:
        - "после X темп/переключения меняются"
        - "когда контекст распадается между A и B, растёт фрикция"
        - "общение с Y может быть восстановительным, but needs more evidence"

        Never output generic labels like "active work", "reading", "switching tabs", or "formulating task" as insights.

        Current end-of-day attention state:
        \(attention)

        Local research digest:
        \(digest)

        Day context pack:
        \(context)
        """
    }

    static func extractInsight(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(InteractionResponse.self, from: data)
        var texts: [String] = []

        for step in response.steps ?? [] where step.type == nil || step.type == "model_output" {
            for content in step.content ?? [] where content.type == nil || content.type == "text" {
                guard let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else {
                    continue
                }
                texts.append(text)
            }
        }

        guard !texts.isEmpty else {
            throw GeminiInsightError.emptyResponse
        }

        return texts.joined(separator: "\n\n")
    }

    static func extractWidgetLine(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONDecoder().decode([String: FlexibleJSONValue].self, from: data),
           let line = object["widget_line"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty {
            return String(line.prefix(110))
        }

        let line = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? trimmed
        return String(line.prefix(110))
    }
}

private enum FlexibleJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([FlexibleJSONValue])
    case object([String: FlexibleJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([FlexibleJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: FlexibleJSONValue].self))
        }
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

enum GeminiInsightError: Error, CustomStringConvertible {
    case emptyAPIKey
    case emptyResponse
    case invalidResponse
    case requestFailed(status: Int, message: String?)

    var description: String {
        switch self {
        case .emptyAPIKey:
            return "Gemini API key is not configured."
        case .emptyResponse:
            return "Gemini returned no text output."
        case .invalidResponse:
            return "Gemini returned an invalid response."
        case .requestFailed(let status, let message):
            if let message, !message.isEmpty {
                return "Gemini request failed with HTTP \(status): \(message)"
            }
            return "Gemini request failed with HTTP \(status)."
        }
    }
}
