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
        #endif
    }

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
