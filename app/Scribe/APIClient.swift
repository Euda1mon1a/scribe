import Foundation

struct TranscribeResponse: Codable {
    let text: String
    let sentences: [SentenceResponse]
    let durationSeconds: Double
    let format: String
    let formattedOutput: String

    enum CodingKeys: String, CodingKey {
        case text
        case sentences
        case durationSeconds = "duration_seconds"
        case format
        case formattedOutput = "formatted_output"
    }
}

struct SentenceResponse: Codable, Identifiable {
    var id: Double { start }
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
}

struct MinutesResponse: Codable {
    let transcript: String
    let minutes: String
    let durationSeconds: Double

    enum CodingKeys: String, CodingKey {
        case transcript
        case minutes
        case durationSeconds = "duration_seconds"
    }
}

struct HealthResponse: Codable {
    let status: String
    let modelLoaded: Bool
    let modelName: String?

    enum CodingKeys: String, CodingKey {
        case status
        case modelLoaded = "model_loaded"
        case modelName = "model_name"
    }
}

final class APIClient: Sendable {
    static let shared = APIClient()
    private let baseURL = "http://127.0.0.1:8890"
    private init() {}

    func checkHealth() async throws -> HealthResponse {
        let url = URL(string: "\(baseURL)/health")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(HealthResponse.self, from: data)
    }

    func transcribe(fileURL: URL, format: String = "txt") async throws -> TranscribeResponse {
        let url = URL(string: "\(baseURL)/transcribe?format=\(format)")!
        let (data, response) = try await upload(fileURL: fileURL, to: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScribeError.serverError(String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try JSONDecoder().decode(TranscribeResponse.self, from: data)
    }

    func generateMinutes(fileURL: URL) async throws -> MinutesResponse {
        let url = URL(string: "\(baseURL)/minutes")!
        let (data, response) = try await upload(fileURL: fileURL, to: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScribeError.serverError(String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try JSONDecoder().decode(MinutesResponse.self, from: data)
    }

    private func upload(fileURL: URL, to url: URL) async throws -> (Data, URLResponse) {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return try await URLSession.shared.data(for: request)
    }
}

enum ScribeError: LocalizedError {
    case serverError(String)
    case backendNotRunning

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return "Server error: \(msg)"
        case .backendNotRunning: return "Scribe backend not running on port 8890. Start it with: python3 -m backend.main"
        }
    }
}
