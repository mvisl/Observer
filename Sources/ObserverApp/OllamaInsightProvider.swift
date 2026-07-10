import Foundation

struct OllamaInsightProvider {
    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    func generateInsight(context: String) async throws -> String {
        let model = ProcessInfo.processInfo.environment["OBSERVER_OLLAMA_MODEL"] ?? "llama3.2"
        let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let prompt = """
        You are a local work-observer assistant. Read the context below and produce:
        1. the likely current task,
        2. any weak signals of stuckness or context switching,
        3. one useful next action.

        Be concise. Do not invent facts.

        \(context)
        """

        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(model: model, prompt: prompt, stream: false)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw OllamaInsightError.requestFailed
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum OllamaInsightError: Error {
    case requestFailed
}
