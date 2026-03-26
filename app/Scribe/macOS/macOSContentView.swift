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
            } else if vm.isBatchResult {
                batchResultsView
            } else {
                resultsView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await vm.checkBackend() }
        .sheet(isPresented: $showingRecorder) {
            MacRecorderSheet(vm: vm)
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(vm.isDragging ? Color.accentColor : Color.secondary)

                Text("Drop audio or video file here")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Cmd+O to open, Cmd+Shift+O for batch")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("Supports MP4, M4A, MP3, WAV, WebM, and more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(selection: $vm.mode) {
                ForEach(ProcessingMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .padding(.top, 16)

            GlassEffectContainer {
                HStack(spacing: 12) {
                    Button(action: { showingRecorder = true }) {
                        Label("Record", systemImage: "mic.fill")
                    }
                    Button(action: openFile) {
                        Label("Open File", systemImage: "folder")
                    }
                    Button(action: openBatch) {
                        Label("Batch", systemImage: "doc.on.doc")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.top, 12)

            if !vm.backendReady {
                Label("Backend not running — start with: python3 -m backend.main", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            Spacer()

            // Recent transcriptions
            if !vm.recentOutputs.isEmpty {
                recentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    vm.isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(20)
        )
        .onDrop(of: [.fileURL], isTargeted: $vm.isDragging) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Recent List

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Recent", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.recentOutputs.prefix(8)) { entry in
                        recentChip(entry)
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 24)
    }

    private func recentChip(_ entry: OutputEntry) -> some View {
        let displayName = entry.name
            .replacingOccurrences(of: "-minutes.md", with: "")

        return Button {
            openRecentOutput(entry)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text(displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(vm.processingStatus)
                    .font(.headline)
                Text(vm.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vm.batchTotal > 0 {
                    Text("\(vm.batchProgress)/\(vm.batchTotal) files")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("This may take a few minutes for long recordings")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .glassEffect(in: .rect(cornerRadius: 16))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Single Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            resultsHeader
            Divider()

            if vm.minutes.isEmpty {
                ScrollView {
                    Text(vm.transcript)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .draggable(vm.transcript)
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
                                .draggable(vm.transcript)
                        }
                    }
                    .frame(minWidth: 300)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Minutes", systemImage: "doc.text")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.top, 8)
                        ScrollView {
                            markdownView(vm.minutes)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .draggable(vm.minutes)
                        }
                    }
                    .frame(minWidth: 300)
                }
            }

            Divider()
            actionBar
        }
    }

    // MARK: - Batch Results

    private var batchResultsView: some View {
        VStack(spacing: 0) {
            resultsHeader
            Divider()

            HSplitView {
                // File list sidebar
                VStack(alignment: .leading, spacing: 0) {
                    Label("Files", systemImage: "doc.on.doc")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal).padding(.top, 8)

                    List(vm.batchItems, selection: $selectedBatchItem) { item in
                        HStack {
                            Image(systemName: item.status == "ok" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(item.status == "ok" ? .green : .red)
                                .font(.caption)
                            VStack(alignment: .leading) {
                                Text(item.filename)
                                    .font(.caption)
                                    .lineLimit(1)
                                if item.status == "ok" {
                                    Text(formatDuration(item.durationSeconds))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else if let error = item.error {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .tag(item.filename)
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

                // Detail pane
                VStack(alignment: .leading, spacing: 4) {
                    if let selected = selectedItem {
                        Label("Minutes — \(selected.filename)", systemImage: "doc.text")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal).padding(.top, 8)
                        ScrollView {
                            markdownView(selected.minutes)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Spacer()
                        Text("Select a file to view its minutes")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                }
                .frame(minWidth: 400)
            }

            Divider()
            actionBar
        }
    }

    @State private var selectedBatchItem: String?
    @State private var showingRecorder = false

    private var selectedItem: BatchItemResponse? {
        guard let id = selectedBatchItem else {
            return vm.batchItems.first(where: { $0.status == "ok" })
        }
        return vm.batchItems.first(where: { $0.filename == id })
    }

    // MARK: - Shared Components

    private var resultsHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(vm.fileName).font(.headline)
                Text(vm.formattedDuration).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("New") { vm.reset() }
                .buttonStyle(.glass)
        }
        .padding()
    }

    private var actionBar: some View {
        GlassEffectContainer {
            HStack {
                if !vm.isBatchResult {
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
                } else if let item = selectedItem {
                    Button("Copy Minutes") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.minutes, forType: .string)
                    }
                }
                Spacer()
                Button("Save to DEVONthink") { saveToDevonThink() }
                Button("Save...") { saveOutput() }
            }
            .buttonStyle(.glass)
            .padding()
        }
    }

    @MainActor
    private func markdownView(_ text: String) -> some View {
        let rendered: AttributedString = {
            if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                return attr
            }
            return AttributedString(text)
        }()
        return Text(rendered)
            .textSelection(.enabled)
    }

    @State private var dtSaved = false

    // MARK: - Logic

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Collect all dropped file URLs
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if urls.count == 1 {
                Task { @MainActor in
                    await vm.processFile(urls[0])
                }
            } else if urls.count > 1 {
                Task { @MainActor in
                    await vm.processBatch(urls)
                }
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

    private func openBatch() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .audiovisualContent]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select multiple audio/video files for batch processing"
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            Task { @MainActor in
                if panel.urls.count == 1 {
                    await vm.processFile(panel.urls[0])
                } else {
                    await vm.processBatch(panel.urls)
                }
            }
        }
    }

    private func openRecentOutput(_ entry: OutputEntry) {
        // Read the output file and display it
        guard let content = try? String(contentsOfFile: entry.path, encoding: .utf8) else { return }

        vm.fileName = entry.name.replacingOccurrences(of: "-minutes.md", with: "")

        // Parse the markdown to extract minutes and transcript sections
        if let minutesRange = content.range(of: "## Minutes\n\n"),
           let transcriptRange = content.range(of: "## Transcript\n\n") {
            let dividerRange = content.range(of: "\n\n---\n\n", range: minutesRange.upperBound..<content.endIndex)
            if let divider = dividerRange {
                vm.minutes = String(content[minutesRange.upperBound..<divider.lowerBound])
            }
            vm.transcript = String(content[transcriptRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            vm.transcript = content
            vm.minutes = ""
        }
    }

    private func saveToDevonThink() {
        let title = vm.isBatchResult ? "Batch — \(vm.fileName)" : vm.fileName
        let content = vm.exportContent
        Task {
            do {
                let ok = try await APIClient.shared.exportToDevonThink(
                    title: title,
                    content: content
                )
                dtSaved = ok
            } catch {
                vm.errorMessage = "DEVONthink export failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let stem = vm.fileName.replacingOccurrences(of: ".", with: "-")
        panel.nameFieldStringValue = "\(stem)-minutes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? vm.exportContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
#endif
