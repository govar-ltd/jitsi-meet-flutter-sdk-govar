import AVFoundation
import Flutter
import WebRTC

/// Passive file recorder: WebRTC owns AVAudioSession configuration and activation.
final class NativeWavCapture: NSObject, AVAudioRecorderDelegate, RTCAudioSessionDelegate {
    private var recorder: AVAudioRecorder?
    private var source: URL?
    private var pending: FlutterResult?
    private var rtcStarted = false
    private var pausedForRTC = false
    private var generation = 0
    private var monitor: Timer?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        RTCAudioSession.sharedInstance().add(self)
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     AVAudioSession.mediaServicesWereResetNotification, AVAudioSession.mediaServicesWereLostNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.log("session_notification", ["name": note.name.rawValue,
                    "type": (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.intValue ?? -1,
                    "routeReason": (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.intValue ?? -1])
                self?.scheduleStart()
            })
        }
    }

    deinit {
        RTCAudioSession.sharedInstance().remove(self)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        monitor?.invalidate()
        recorder?.stop()
    }

    func start(path: String, result: @escaping FlutterResult) {
        stop()
        generation += 1
        source = URL(fileURLWithPath: path)
        pending = result
        log("start_requested")
        scheduleStart()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, self.generation == token, self.pending != nil else { return }
            // Delegate may have begun before registration; only a settled active RTC session can be used.
            if RTCAudioSession.sharedInstance().isActive && AVAudioSession.sharedInstance().isInputAvailable {
                self.begin()
            } else {
                self.log("rtc_audio_not_ready")
                let callback = self.pending; self.pending = nil
                callback?(FlutterError(code: "rtc_audio_not_ready", message: "Jitsi audio session did not become active", details: nil))
            }
        }
    }

    private func scheduleStart() {
        guard pending != nil && rtcStarted else { return }
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.generation == token, self.pending != nil, self.rtcStarted else { return }
            if RTCAudioSession.sharedInstance().isActive && AVAudioSession.sharedInstance().isInputAvailable { self.begin() }
        }
    }

    private func begin() {
        guard let source = source, let callback = pending else { return }
        pending = nil
        do {
            // No setCategory, setMode, setActive, preferred-rate or input-route setters here.
            let value = try AVAudioRecorder(url: source, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            value.delegate = self
            value.isMeteringEnabled = true
            guard value.prepareToRecord(), value.record() else {
                log("native_start_rejected")
                value.stop()
                callback(FlutterError(code: "native_wav_start_failed", message: "AVAudioRecorder refused recording", details: nil))
                return
            }
            recorder = value
            log("native_file_started")
            monitor = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.log("native_status") }
            callback(status())
        } catch {
            log("native_start_error", ["error": error.localizedDescription])
            callback(FlutterError(code: "native_wav_start_failed", message: error.localizedDescription, details: nil))
        }
    }

    func status() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        return ["recording": recorder?.isRecording ?? false, "paused": pausedForRTC,
                "seconds": recorder?.currentTime ?? 0, "rtcStarted": rtcStarted,
                "rtcActive": RTCAudioSession.sharedInstance().isActive,
                "category": session.category.rawValue, "mode": session.mode.rawValue,
                "sampleRate": session.sampleRate,
                "inputPorts": session.currentRoute.inputs.map { $0.portType.rawValue },
                "outputPorts": session.currentRoute.outputs.map { $0.portType.rawValue }]
    }

    func stop() {
        generation += 1
        if let callback = pending {
            pending = nil
            callback(FlutterError(code: "native_wav_cancelled", message: "Capture was cancelled", details: nil))
        }
        monitor?.invalidate(); monitor = nil
        if recorder != nil { log("native_file_stopping") }
        recorder?.stop(); recorder = nil; pausedForRTC = false
        log("native_file_stopped")
    }

    private func log(_ event: String, _ extra: [String: Any] = [:]) {
        guard let source = source else { return }
        var fields = status()
        fields["time"] = ISO8601DateFormatter().string(from: Date())
        fields["event"] = event
        for (key, value) in extra { fields[key] = value }
        let file = source.deletingLastPathComponent().appendingPathComponent("native_audio_diagnostics.jsonl")
        do {
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            data.append(10)
            try handle.write(contentsOf: data)
        } catch { NSLog("Govar capture diagnostics failed: %@", error.localizedDescription) }
    }

    func audioSessionDidStartPlayOrRecord(_ session: RTCAudioSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rtcStarted = true
            self.log("rtc_audio_started")
            if self.pausedForRTC, let recorder = self.recorder {
                self.pausedForRTC = !recorder.record()
                self.log("native_resume_after_rtc")
            }
            self.scheduleStart()
        }
    }

    func audioSessionDidStopPlayOrRecord(_ session: RTCAudioSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rtcStarted = false
            self.log("rtc_audio_stopped")
            if self.recorder?.isRecording == true {
                self.recorder?.pause()
                self.pausedForRTC = true
                self.log("native_paused_with_rtc")
            }
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        log("native_recorder_finished", ["success": flag])
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        log("native_recorder_error", ["error": error?.localizedDescription ?? "unknown"])
    }
}
