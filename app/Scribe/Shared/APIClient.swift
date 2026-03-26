import Foundation

final class APIClient: Sendable {
    static let shared = APIClient()
    private init() {}

    private var baseURL: String {
        // Override via UserDefaults key "scribeBackendURL" or Settings
        // iOS defaults to localhost — set to your server's IP if running remotely
        return UserDefaults.standard.string(forKey: "scribeBackendURL")
            ?? "http://127.0.0.1:8890"
    }

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

    func batchMinutes(fileURLs: [URL]) async throws -> BatchResponse {
        let url = URL(string: "\(baseURL)/batch/minutes")!
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 1800 // 30 min for large batches

        var body = Data()
        for fileURL in fileURLs {
            let fileData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScribeError.serverError(String(data: data, encoding: .utf8) ?? "Batch failed")
        }
        return try JSONDecoder().decode(BatchResponse.self, from: data)
    }

    func listOutputs() async throws -> [OutputEntry] {
        let url = URL(string: "\(baseURL)/output/list")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(OutputListResponse.self, from: data)
        return response.outputs
    }

    func exportToDevonThink(title: String, content: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/export/devonthink")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body = ["title": title, "content": content]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
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
