import AVFoundation
import SwiftUI

#if os(iOS)
@MainActor
@Observable
final class AudioRecorder {
    var isRecording = false
    var duration: TimeInterval = 0
    var recordingURL: URL?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            return
        }

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

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)

        return recordingURL
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct RecorderView: View {
    @Bindable var vm: ScribeViewModel
    @State private var recorder = AudioRecorder()
    @State private var showingConfirm = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Waveform indicator
            Image(systemName: recorder.isRecording ? "waveform" : "mic.circle")
                .font(.system(size: 64))
                .foregroundStyle(recorder.isRecording ? .red : .secondary)
                .symbolEffect(.variableColor, isActive: recorder.isRecording)

            // Timer
            Text(recorder.formattedDuration)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(recorder.isRecording ? .primary : .secondary)

            // Record / Stop button
            Button(action: {
                if recorder.isRecording {
                    if let url = recorder.stopRecording() {
                        showingConfirm = true
                    }
                } else {
                    recorder.startRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? .red : .red.opacity(0.8))
                        .frame(width: 72, height: 72)

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(recorder.isRecording ? "Tap to stop" : "Tap to record")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .alert("Transcribe recording?", isPresented: $showingConfirm) {
            Button("Transcribe + Minutes") {
                if let url = recorder.recordingURL {
                    vm.mode = .minutes
                    Task { await vm.processFile(url) }
                }
            }
            Button("Transcript Only") {
                if let url = recorder.recordingURL {
                    vm.mode = .transcribe
                    Task { await vm.processFile(url) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(recorder.formattedDuration) recorded")
        }
    }
}
#endif
