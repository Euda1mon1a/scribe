import Foundation

struct TranscribeResponse: Codable {
    let text: String
    let sentences: [SentenceResponse]
    let durationSeconds: Double
    let format: String
    let formattedOutput: String

    enum CodingKeys: String, CodingKey {
        case text, sentences, format
        case durationSeconds = "duration_seconds"
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
        case transcript, minutes
        case durationSeconds = "duration_seconds"
    }
}

struct BatchItemResponse: Codable, Identifiable {
    var id: String { filename }
    let filename: String
    let transcript: String
    let minutes: String
    let durationSeconds: Double
    let status: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case filename, transcript, minutes, status, error
        case durationSeconds = "duration_seconds"
    }
}

struct BatchResponse: Codable {
    let total: Int
    let completed: Int
    let failed: Int
    let items: [BatchItemResponse]
}

struct OutputEntry: Codable, Identifiable {
    var id: String { name }
    let name: String
    let path: String
    let size: Int
}

struct OutputListResponse: Codable {
    let outputs: [OutputEntry]
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

enum ScribeError: LocalizedError {
    case serverError(String)
    case backendNotRunning

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return "Server error: \(msg)"
        case .backendNotRunning: return "Scribe backend not reachable. Check that the backend is running."
        }
    }
}
