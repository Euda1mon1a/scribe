import Foundation
import SwiftUI

enum ProcessingMode: String, CaseIterable {
    case transcribe = "Transcript Only"
    case minutes = "Transcript + Minutes"
}

@MainActor
@Observable
final class ScribeViewModel {
    var isDragging = false
    var isProcessing = false
    var processingStatus = ""
    var transcript = ""
    var minutes = ""
    var duration: Double = 0
    var errorMessage: String?
    var mode: ProcessingMode = .minutes
    var backendReady = false
    var fileName = ""

    var hasResults: Bool { !transcript.isEmpty }

    func checkBackend() async {
        do {
            let health = try await APIClient.shared.checkHealth()
            backendReady = health.modelLoaded
        } catch {
            backendReady = false
        }
    }

    func processFile(_ url: URL) async {
        errorMessage = nil
        isProcessing = true
        fileName = url.lastPathComponent

        do {
            switch mode {
            case .transcribe:
                processingStatus = "Transcribing..."
                let result = try await APIClient.shared.transcribe(fileURL: url)
                transcript = result.formattedOutput
                duration = result.durationSeconds

            case .minutes:
                processingStatus = "Transcribing..."
                let result = try await APIClient.shared.generateMinutes(fileURL: url)
                transcript = result.transcript
                minutes = result.minutes
                duration = result.durationSeconds
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }

    func reset() {
        transcript = ""
        minutes = ""
        duration = 0
        fileName = ""
        errorMessage = nil
    }

    var formattedDuration: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var exportContent: String {
        if minutes.isEmpty {
            return transcript
        }
        return "# Minutes\n\n\(minutes)\n\n---\n\n# Transcript\n\n\(transcript)"
    }
}
