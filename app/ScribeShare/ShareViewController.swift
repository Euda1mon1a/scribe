import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            close()
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                    handleAudio(provider: provider)
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    handleAudio(provider: provider)
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    handleAudio(provider: provider)
                    return
                }
            }
        }
        close()
    }

    private func handleAudio(provider: NSItemProvider) {
        let types = [UTType.audio.identifier, UTType.movie.identifier, UTType.fileURL.identifier]
        let type = types.first { provider.hasItemConformingToTypeIdentifier($0) } ?? UTType.data.identifier

        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
            guard let url = url else {
                DispatchQueue.main.async { self?.close() }
                return
            }

            // Copy to shared container so main app can access it
            let sharedDir = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.aaronmontgomery.scribe"
            )
            guard let sharedDir = sharedDir else {
                DispatchQueue.main.async { self?.close() }
                return
            }

            let dest = sharedDir.appendingPathComponent("shared-audio-\(UUID().uuidString).\(url.pathExtension)")
            try? FileManager.default.copyItem(at: url, to: dest)

            // Store the path for the main app to pick up
            UserDefaults(suiteName: "group.com.aaronmontgomery.scribe")?.set(dest.path, forKey: "pendingAudioPath")

            // Open main app via URL scheme
            let openURL = URL(string: "scribe://transcribe")!
            _ = self?.openURL(openURL)

            DispatchQueue.main.async { self?.close() }
        }
    }

    @objc @discardableResult
    private func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let r = responder {
            if let application = r as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = r.next
        }
        // Fallback for extensions
        let selector = sel_registerName("openURL:")
        var target: UIResponder? = self
        while let r = target {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                return true
            }
            target = r.next
        }
        return false
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
