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
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1/interactions")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let prompt = Self.buildPrompt(context: context, digest: digest, attention: attention)
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
