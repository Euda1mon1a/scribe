import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
struct MacContentView: View {
    @Bindable var vm: ScribeViewModel

    var body: some View {
        VStack(spacing: 0) {
            if !vm.hasResults && !vm.isProcessing {
                dropZone
            } else if vm.isProcessing {
                progressView
            } else {
                resultsView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await vm.checkBackend() }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(vm.isDragging ? Color.accentColor : Color.secondary)

                Text("Drop audio or video file here")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("or use File → Open (Cmd+O)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("Supports MP4, M4A, MP3, WAV, WebM, and more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $vm.mode) {
                ForEach(ProcessingMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            Button(action: openFile) {
                Label("Open File", systemImage: "folder")
            }
            .controlSize(.large)

            if !vm.backendReady {
                Label("Backend not running — start with: python3 -m backend.main", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = vm.errorMessage {
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
                .strokeBorder(vm.isDragging ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding(20)
        )
        .onDrop(of: [.fileURL], isTargeted: $vm.isDragging) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(vm.processingStatus)
                .font(.headline)
            Text(vm.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("This may take a few minutes for long recordings")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(vm.fileName).font(.headline)
                    Text(vm.formattedDuration).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("New File") { vm.reset() }
            }
            .padding()

            Divider()

            if vm.minutes.isEmpty {
                ScrollView {
                    Text(vm.transcript)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Transcript", systemImage: "text.alignleft")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.top, 8)
                        ScrollView {
                            Text(vm.transcript)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 300)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Minutes", systemImage: "doc.text")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.top, 8)
                        ScrollView {
                            Text(vm.minutes)
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(minWidth: 300)
                }
            }

            Divider()

            HStack {
                Button("Copy Transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.transcript, forType: .string)
                }
                if !vm.minutes.isEmpty {
                    Button("Copy Minutes") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(vm.minutes, forType: .string)
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
                await vm.processFile(url)
            }
        }
        return true
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await vm.processFile(url)
            }
        }
    }

    private func saveOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = vm.fileName.replacingOccurrences(of: ".", with: "-") + "-minutes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? vm.exportContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
