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
            #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 700)
        #endif
    }
}
