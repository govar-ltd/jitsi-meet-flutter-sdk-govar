# iOS 442: one RemoteIO capture, standalone AEC3, shared processed WAV/WebRTC PCM

Base: complete 441. No Android, UI, registration, visits, SendPulse/welcome, support, push or server changes. Device 441 confirmed preStartRepairs=1 but wide input became unavailable after VPIO initialization. This variant removes VPIO and the parallel recorder from the custom path rather than retrying that preference again.

## Pipeline

- RemoteIO, playAndRecord/measurement, requested 48kHz PCM16 mono and speaker route. Uses the actual 16-bit PCM delivered to RemoteIO as the AEC render reference.
- Standalone webrtc-audio-processing 2.1 (M131 AEC3), namespace-isolated from Jitsi M124. AEC enabled; NS, both AGCs, highpass and enforced AEC highpass disabled. Delay includes current input/output latency plus I/O buffer; AEC3 estimates remaining render/capture alignment.
- Independent variable-size input/render framers feed 480-sample/10ms processing. Processed capture is both delivered through RTCAudioDeviceDelegate and appended to a bounded ring for the growing WAV. No AVAudioRecorder in this path, no disk I/O or dispatch from real-time callbacks. On DSP error only silence is delivered, never unprotected raw microphone data; errors and dropped callbacks are counted.
- Serial disk consumer flushes PCM/header every 20ms. Final partial frame is zero-padded for processing but only its valid samples are written. Stop waits for drain before Flutter completion/Dart final read. It stops RemoteIO before final flush and detaches WebRTC's I/O thread checkers before restart; tail flushing never invokes WebRTC from the control thread.
- Route changes and interruptions stop/recreate the unit on the ADM owner thread, reset AEC and notify WebRTC; the same file format continues. Session activation ownership is balanced. Reinitialization after terminate is supported. Category changes away from recording pause the unit instead of fighting Jitsi teardown.

## Integration and fallback

Pinned JitsiMeetSDK12 binary references initWithEncoderFactory:decoderFactory:audioDevice:. Its public initializer is intercepted, keeping init-family ARC ownership. An explicitly supplied device is preserved. Permission must already be granted: no permission request or microphone activation at app startup. Before handing a custom device to the factory, prepare RemoteIO/AEC; on preparation or integration failure keep the stock factory and legacy recorder. Runtime unit/DSP failures remain errors/silence, not a claim of successful fallback or echo cancellation.

Jitsi AudioMode's pinned configuration adapter preserves measurement/speaker for this device. RTCMediaConstraints dictionaries are copied using checked Objective-C ivars present in pinned M124; all existing network-adaptor/source options are retained while only four processing switches are overridden. Other factory APIs and Android untouched. The old 439–441 wide-range hooks are not installed. Full stock JitsiWebRTC124.0.2 binary identity remains required.

Native recording waits for the factory choice before selecting unified versus legacy capture. Generation guards protect cancellation and rapid reentry. Legacy cancellation still completes Flutter results. Native stop completes only after file drain; existing Dart 10/60-second chunks and final-tail upload behavior remain unchanged.

## Build and verification

APM source release SHA256 ae9302824b2038d394f10213cab05312c564a038434269f11dbf68f511f9f9fe. tools/aec3/build.py builds mac/ios/sim outside the repo, pins archive/Abseil wrap hashes, isolates namespaces, and tools/aec3/package.py creates the arm64-device/arm64-simulator static XCFramework with all dependency licenses and binary identities in Assets. Intel simulator slice is not included. No binary ABI patching or replacement of Jitsi WebRTC.

Host DSP checks: irregular callbacks, ring wrap, final tail and WAV exactness (384137 samples); synthetic echo reduction about 22.97dB; 17kHz RMS ratio about0.943; double-talk near-end tone amplitude ratio about0.738. Four Swift lifecycle tests and five existing Dart recorder/chunk/tail tests pass. Device-target ObjC++ syntax/podspec checks pass. These are controlled synthetic tests; they do not establish iPhone acoustic quality.

Device acceptance: confirm customDevice=true, unitRunning=true, audioUnit=RemoteIO, wavSource=same_post_aec_pcm_as_webrtc, increasing render/capture/processed counts and apmErrors/callbackErrors/wavError/wavOverruns=0. If selection says stock fallback this variant was not exercised. Test high-volume iPhone–Android self echo, simultaneous speech, audibility, mute/unmute, repeated entry, background/interruption and headset route. Download WAVs and compare spectrum. No promise of no echo or preserved hardware bandwidth until physical testing.

References: https://freedesktop.org/software/pulseaudio/webrtc-audio-processing/ ; https://github.com/react-native-webrtc/react-native-webrtc/blob/master/ios/RCTWebRTC/WebRTCModule.m ; pinned RTCAudioDevice.h/RTCPeerConnectionFactory.h in official JitsiWebRTC124.0.2.
