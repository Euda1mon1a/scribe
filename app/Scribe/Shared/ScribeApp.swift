import SwiftUI

@main
struct ScribeApp: App {
    @State private var viewModel = ScribeViewModel()

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacContentView(vm: viewModel)
            #else
            IOSContentView(vm: viewModel)
                .onOpenURL { url in
                    if url.scheme == "scribe", url.host == "transcribe" {
                        handleSharedAudio()
                    }
                }
            #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Audio/Video...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Multiple Files...") {
                    openBatch()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Save Output...") {
                    saveOutput()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!viewModel.hasResults)

                Button("Export to DEVONthink") {
                    exportToDevonThink()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!viewModel.hasResults)

                Divider()

                Button("Copy Minutes") {
                    copyMinutes()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(viewModel.minutes.isEmpty)

                Button("New Transcription") {
                    viewModel.reset()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        #endif
    }

    #if os(macOS)
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .audiovisualContent]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select an audio or video file to transcribe"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                await viewModel.processFile(url)
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
            Task {
                await viewModel.processBatch(panel.urls)
            }
        }
    }

    private func saveOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let stem = viewModel.fileName.replacingOccurrences(of: ".", with: "-")
        panel.nameFieldStringValue = "\(stem)-minutes.md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? viewModel.exportContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportToDevonThink() {
        Task {
            _ = try? await APIClient.shared.exportToDevonThink(
                title: viewModel.fileName,
                content: viewModel.exportContent
            )
        }
    }

    private func copyMinutes() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.minutes, forType: .string)
    }
    #endif

    #if os(iOS)
    private func handleSharedAudio() {
        guard let path = UserDefaults(suiteName: "group.com.aaronmontgomery.scribe")?.string(forKey: "pendingAudioPath") else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }

        UserDefaults(suiteName: "group.com.aaronmontgomery.scribe")?.removeObject(forKey: "pendingAudioPath")

        Task {
            await viewModel.processFile(url)
        }
    }
    #endif
}
