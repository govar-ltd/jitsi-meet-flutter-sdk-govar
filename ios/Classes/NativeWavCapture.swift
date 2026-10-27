import AVFoundation
import Flutter

/// WAV consumes exactly the processed PCM delivered to WebRTC by RemoteIO/AEC3.
/// The old recorder is used only if custom-device preparation selected stock audio.
final class NativeWavCapture {
    private enum Mode { case undecided, custom, legacy }
    private let legacy = LegacyWavCapture()
    private var mode = Mode.undecided
    private var source: URL?
    private var pending: FlutterResult?
    private var generation = 0
    private var monitor: Timer?

    func start(path: String, result: @escaping FlutterResult) {
        let token = generation + 1
        stop { [weak self] in
            guard let self = self, self.generation == token else {
                result(FlutterError(code: "native_wav_cancelled", message: "Capture was superseded", details: nil))
                return
            }
            self.source = URL(fileURLWithPath: path)
            self.pending = result
            self.log("start_requested")
            self.attemptStart(token: self.generation, deadline: Date().addingTimeInterval(8))
        }
    }

    private func attemptStart(token: Int, deadline: Date) {
        guard token == generation, pending != nil, let source = source else { return }
        let state = GovarUnifiedAudio.diagnostics()
        let selected = state["factorySelected"] as? Bool ?? false
        let custom = state["customDevice"] as? Bool ?? false
        let initialized = state["deviceInitialized"] as? Bool ?? false
        if selected && !custom {
            mode = .legacy
            let callback = pending; pending = nil
            legacy.start(path: source.path, result: { value in callback?(value) })
            return
        }
        if selected && initialized {
            mode = .custom
            GovarUnifiedAudio.startRecording(path: source.path) { [weak self] error in
                guard let self = self, self.generation == token else { return }
                let callback = self.pending; self.pending = nil
                if let error = error {
                    self.log("native_start_error", ["error": error.localizedDescription])
                    callback?(FlutterError(code: "native_wav_start_failed", message: error.localizedDescription, details: nil))
                } else {
                    self.log("native_file_started")
                    self.monitor = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.log("native_status") }
                    callback?(self.status())
                }
            }
            return
        }
        guard Date() < deadline else {
            let callback = pending; pending = nil
            log("unified_audio_not_ready")
            callback?(FlutterError(code: "rtc_audio_not_ready", message: "Audio device did not become ready", details: nil))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.attemptStart(token: token, deadline: deadline) }
    }

    func stop(completion: @escaping () -> Void = {}) {
        generation += 1
        if let callback = pending { pending = nil; callback(FlutterError(code: "native_wav_cancelled", message: "Capture was cancelled", details: nil)) }
        monitor?.invalidate(); monitor = nil
        let token = generation
        let previous = mode; mode = .undecided
        if previous == .custom {
            log("native_file_stopping")
            GovarUnifiedAudio.stopRecording { [weak self] in
                if self?.generation == token { self?.log("native_file_stopped") }
                completion()
            }
        } else { legacy.stop(); completion() }
    }

    func status() -> [String: Any] {
        if mode == .legacy { return legacy.status() }
        let audio = GovarUnifiedAudio.diagnostics()
        let session = AVAudioSession.sharedInstance()
        let paused = (audio["fileWanted"] as? Bool ?? false) && !(audio["unitRunning"] as? Bool ?? false)
        return ["recording": audio["recording"] ?? false, "seconds": audio["seconds"] ?? 0,
                "paused": paused, "rtcStarted": audio["unitRunning"] ?? false,
                "rtcActive": audio["unitRunning"] ?? false,
                "audioPolicy": audio["audioPolicy"] ?? "unified_remote_io_aec3",
                "unifiedAudio": audio, "category": session.category.rawValue, "mode": session.mode.rawValue,
                "sampleRate": session.sampleRate, "preferredSampleRate": session.preferredSampleRate,
                "inputChannels": session.inputNumberOfChannels, "ioBufferDuration": session.ioBufferDuration,
                "inputLatency": session.inputLatency, "fileSampleRate": audio["fileSampleRate"] ?? 0,
                "fileChannels": audio["fileChannels"] ?? 0,
                "inputPorts": session.currentRoute.inputs.map { $0.portType.rawValue },
                "outputPorts": session.currentRoute.outputs.map { $0.portType.rawValue }]
    }

    private func log(_ event: String, _ extra: [String: Any] = [:]) {
        guard let source = source else { return }
        var fields = status(); fields["time"] = ISO8601DateFormatter().string(from: Date()); fields["event"] = event
        for (key, value) in extra { fields[key] = value }
        let path = source.deletingLastPathComponent().appendingPathComponent("native_audio_diagnostics.jsonl")
        do {
            if !FileManager.default.fileExists(atPath: path.path) { FileManager.default.createFile(atPath: path.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: path); defer { try? handle.close() }
            try handle.seekToEnd()
            var data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]); data.append(10)
            try handle.write(contentsOf: data)
        } catch { NSLog("Govar capture diagnostics failed: %@", error.localizedDescription) }
    }

    deinit { monitor?.invalidate() }
}
