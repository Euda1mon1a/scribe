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
