import AVFoundation
import SwiftUI

#if os(macOS)
@MainActor
@Observable
final class MacAudioRecorder {
    var isRecording = false
    var duration: TimeInterval = 0
    var recordingURL: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minutes-\(Int(Date().timeIntervalSince1970)).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.record()
            recordingURL = url
            isRecording = true
            duration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.duration += 1
                }
            }
        } catch {
            return
        }
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        return recordingURL
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct MacRecorderSheet: View {
    @Bindable var vm: ScribeViewModel
    @State private var recorder = MacAudioRecorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: recorder.isRecording ? "waveform" : "mic.circle")
                .font(.system(size: 48))
                .foregroundStyle(recorder.isRecording ? .red : .secondary)
                .symbolEffect(.variableColor, isActive: recorder.isRecording)

            Text(recorder.formattedDuration)
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .foregroundStyle(recorder.isRecording ? .primary : .secondary)

            // Record / Stop button
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? .red : .red.opacity(0.8))
                        .frame(width: 56, height: 56)

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 20, height: 20)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(recorder.isRecording ? "Click to stop" : "Click to record")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !recorder.isRecording && recorder.recordingURL != nil {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        Button("Transcribe + Minutes") {
                            submitRecording(mode: .minutes)
                        }
                        Button("Transcript Only") {
                            submitRecording(mode: .transcribe)
                        }
                    }
                    .buttonStyle(.glass)
                }

                Button("Discard") {
                    cleanupAndDismiss()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 320)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            _ = recorder.stopRecording()
        } else {
            recorder.startRecording()
        }
    }

    private func submitRecording(mode: ProcessingMode) {
        guard let url = recorder.recordingURL else { return }
        vm.mode = mode
        Task { await vm.processFile(url) }
        dismiss()
    }

    private func cleanupAndDismiss() {
        if let url = recorder.recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        dismiss()
    }
}
#endif
