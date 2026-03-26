import SwiftUI

#if os(iOS)
struct IOSContentView: View {
    @Bindable var vm: ScribeViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Record
            NavigationStack {
                Group {
                    if vm.isProcessing {
                        progressView
                    } else if vm.hasResults {
                        resultsView
                    } else {
                        RecorderView(vm: vm)
                    }
                }
                .navigationTitle("Minutes")
                .toolbar {
                    if vm.hasResults {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New") { vm.reset() }
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            ShareLink(item: vm.exportContent)
                        }
                    }
                }
            }
            .tabItem { Label("Record", systemImage: "mic.fill") }
            .tag(0)

            // Tab 2: Import file
            NavigationStack {
                Group {
                    if vm.isProcessing {
                        progressView
                    } else if vm.hasResults {
                        resultsView
                    } else {
                        filePickerView
                    }
                }
                .navigationTitle("Minutes")
                .toolbar {
                    if vm.hasResults {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New") { vm.reset() }
                        }
                        ToolbarItem(placement: .secondaryAction) {
                            ShareLink(item: vm.exportContent)
                        }
                    }
                }
            }
            .tabItem { Label("Import", systemImage: "doc.badge.plus") }
            .tag(1)
        }
        .task { await vm.checkBackend() }
    }

    // MARK: - File Picker

    @State private var showingFilePicker = false

    private var filePickerView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Import audio or video")
                .font(.title2)
                .fontWeight(.medium)

            Picker("Mode", selection: $vm.mode) {
                ForEach(ProcessingMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)

            Button(action: { showingFilePicker = true }) {
                Label("Select File", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            if !vm.backendReady {
                Label("Backend unreachable — check connection", systemImage: "exclamationmark.triangle")
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
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio, .audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else { return }
                Task {
                    await vm.processFile(url)
                    url.stopAccessingSecurityScopedResource()
                }
            }
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
            Spacer()
        }
    }

    // MARK: - Results

    @State private var resultTab = 0

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(vm.fileName).font(.caption).fontWeight(.medium)
                    Text(vm.formattedDuration).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Segmented picker instead of nested TabView
            if !vm.minutes.isEmpty {
                Picker("View", selection: $resultTab) {
                    Text("Minutes").tag(0)
                    Text("Transcript").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            Divider()

            // Content
            ScrollView {
                if resultTab == 0 && !vm.minutes.isEmpty {
                    Text(vm.minutes)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(vm.transcript)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
#endif
