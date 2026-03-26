import Foundation
import SwiftUI
#if os(macOS)
import UserNotifications
#endif

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

    // Batch
    var batchItems: [BatchItemResponse] = []
    var batchProgress: Int = 0
    var batchTotal: Int = 0

    // Recent outputs
    var recentOutputs: [OutputEntry] = []

    var hasResults: Bool { !transcript.isEmpty || !batchItems.isEmpty }
    var isBatchResult: Bool { !batchItems.isEmpty }

    func checkBackend() async {
        do {
            let health = try await APIClient.shared.checkHealth()
            backendReady = health.modelLoaded
            if backendReady {
                await loadRecentOutputs()
            }
        } catch {
            backendReady = false
        }
    }

    func processFile(_ url: URL) async {
        errorMessage = nil
        isProcessing = true
        batchItems = []
        fileName = url.lastPathComponent

        do {
            switch mode {
            case .transcribe:
                processingStatus = "Transcribing..."
                let result = try await APIClient.shared.transcribe(fileURL: url)
                transcript = result.formattedOutput
                duration = result.durationSeconds

            case .minutes:
                processingStatus = "Transcribing audio..."
                let result = try await APIClient.shared.generateMinutes(fileURL: url)
                transcript = result.transcript
                minutes = result.minutes
                duration = result.durationSeconds
            }
            await loadRecentOutputs()
            postNotification(title: "Minutes Ready", body: fileName)
        } catch {
            errorMessage = error.localizedDescription
            postNotification(title: "Processing Failed", body: fileName)
        }
        isProcessing = false
    }

    func processBatch(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        errorMessage = nil
        isProcessing = true
        batchItems = []
        transcript = ""
        minutes = ""
        batchTotal = urls.count
        batchProgress = 0
        fileName = "\(urls.count) files"
        processingStatus = "Processing \(urls.count) files..."

        do {
            let result = try await APIClient.shared.batchMinutes(fileURLs: urls)
            batchItems = result.items
            // Show combined transcript/minutes from first successful item
            if let first = result.items.first(where: { $0.status == "ok" }) {
                transcript = first.transcript
                minutes = first.minutes
                duration = result.items.filter { $0.status == "ok" }
                    .reduce(0) { $0 + $1.durationSeconds }
            }
            await loadRecentOutputs()
            postNotification(
                title: "Batch Complete",
                body: "\(result.completed)/\(result.total) files processed"
            )
        } catch {
            errorMessage = error.localizedDescription
            postNotification(title: "Batch Failed", body: error.localizedDescription)
        }
        isProcessing = false
    }

    func loadRecentOutputs() async {
        do {
            recentOutputs = try await APIClient.shared.listOutputs()
        } catch {
            recentOutputs = []
        }
    }

    func reset() {
        transcript = ""
        minutes = ""
        duration = 0
        fileName = ""
        errorMessage = nil
        batchItems = []
        batchProgress = 0
        batchTotal = 0
    }

    var formattedDuration: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    var exportContent: String {
        if isBatchResult {
            return batchItems.filter { $0.status == "ok" }.map { item in
                "# \(item.filename)\n\n## Minutes\n\n\(item.minutes)\n\n## Transcript\n\n\(item.transcript)"
            }.joined(separator: "\n\n---\n\n")
        }
        if minutes.isEmpty {
            return transcript
        }
        return "# Minutes\n\n\(minutes)\n\n---\n\n# Transcript\n\n\(transcript)"
    }

    // MARK: - Notifications

    private func postNotification(title: String, body: String) {
        #if os(macOS)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
        #endif
    }
}
