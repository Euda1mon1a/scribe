import SwiftUI
import UniformTypeIdentifiers

enum ProcessingMode: String, CaseIterable {
    case transcribe = "Transcript Only"
    case minutes = "Transcript + Minutes"
}

struct ContentView: View {
    @State private var isDragging = false
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var transcript = ""
    @State private var minutes = ""
    @State private var duration: Double = 0
    @State private var errorMessage: String?
    @State private var mode: ProcessingMode = .minutes
    @State private var backendReady = false
    @State private var fileName = ""

    var body: some View {
        VStack(spacing: 0) {
            if transcript.isEmpty && !isProcessing {
                dropZone
            } else if isProcessing {
                progressView
            } else {
                resultsView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await checkBackend() }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(isDragging ? Color.accentColor : Color.secondary)

                Text("Drop audio or video file here")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Supports MP4, M4A, MP3, WAV, WebM, and more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $mode) {
                ForEach(ProcessingMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            if !backendReady {
                Label("Backend not running — start with: python3 -m backend.main", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isDragging ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(20)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(processingStatus)
                .font(.headline)
            Text(fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(fileName)
                        .font(.headline)
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("New File") { reset() }
            }
            .padding()

            Divider()

            if minutes.isEmpty {
                // Transcript only
                ScrollView {
                    Text(transcript)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Two-pane: transcript + minutes
                HSplitView {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Transcript", systemImage: "text.alignleft")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        ScrollView {
                            Text(transcript)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 300)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Minutes", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        ScrollView {
                            Text(minutes)
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 300)
                }
            }

            Divider()

            // Export bar
            HStack {
                Button("Copy Transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }
                if !minutes.isEmpty {
                    Button("Copy Minutes") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(minutes, forType: .string)
                    }
                }
                Spacer()
                Button("Save...") { saveOutput() }
            }
            .padding()
        }
    }

    // MARK: - Logic

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                await processFile(url)
            }
        }
        return true
    }

    private func processFile(_ url: URL) async {
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

    private func checkBackend() async {
        do {
            let health = try await APIClient.shared.checkHealth()
            backendReady = health.modelLoaded
        } catch {
            backendReady = false
        }
    }

    private func reset() {
        transcript = ""
        minutes = ""
        duration = 0
        fileName = ""
        errorMessage = nil
    }

    private func saveOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = fileName.replacingOccurrences(of: ".", with: "-") + "-minutes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let content = minutes.isEmpty ? transcript : "# Minutes\n\n\(minutes)\n\n---\n\n# Transcript\n\n\(transcript)"
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
