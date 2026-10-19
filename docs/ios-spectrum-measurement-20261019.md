# iOS spectrum experiment, 19 October 2026

Production rollback SDK: 36459ceb5d521a074fdb7b49cf517eb5d309fef7 (app 5.0.15/427).

Previous trials: 423 disableAP/NS/AEC/AGC did not remove the approximately 12kHz cutoff. In 424, setting default before AVAudioRecorder was undone: native_file_started logged videoChat.

New bounded experiment: request measurement mode and preferred 48kHz through RTCAudioSession's configuration lock before and immediately after the recorder starts. Repeat only on actual RTC pause/resume, not on a timer or every route notification. No setActive, category replacement, route override, AVAudioEngine, recorder restart or codec change. Existing native WAV PCM16 mono 48kHz continuous file and Dart 10s/60s sample splitting are unchanged. Existing Jitsi identity URL parser is preserved.

Diagnostics record requested/actual mode, preferred/actual rate, file format, channel count, input data source, route, latency and buffer duration. Unsupported preferences are logged without preventing baseline recording. Successful setters are not proof of a full-band microphone signal. Jitsi or Apple's VoiceProcessing I/O may still constrain the signal despite measurement mode.

Validation: Swift typecheck against actual installed JitsiWebRTC 124.0.2 and iOS SDK; 5 existing reader/splitter/recorder tests passed. These verify preservation of captured PCM and one start, not physical microphone bandwidth or sound reaching the peer.

Required hardware test: same iPhone, built-in microphone, 90+ seconds, continuous speech across 10s and 70s boundaries; verify the peer hears speech, microphone mute and camera toggles still work, uploads arrive, no added echo. Compare WAV spectra using a repeatable broadband test signal; ordinary speech alone cannot prove bandwidth. Inspect native_audio_diagnostics.jsonl for whether measurement stayed active, recording grew, interruptions, actual rate and route. Test wired/Bluetooth routes separately: headset profiles can impose bandwidth limits. Reconnect and rejoin must retain identity and capture behavior. If no improvement or call quality regresses, restore production SDK pin. Never advertise the cutoff as fixed before hardware confirmation.
