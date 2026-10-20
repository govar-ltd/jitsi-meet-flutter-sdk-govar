# Native Jitsi configuration experiment 429

Rollback: 428 SDK a7aca45c1f0a9f276e156099dd2caaed3d934805; production 427 SDK 36459ceb5d521a074fdb7b49cf517eb5d309fef7. 428 logs show measurement reverted to videoChat after 0.7s, all 40 periodic statuses videoChat.

Runtime adapter inside the pinned native Jitsi 12.0.0 AudioMode setConfigWithoutLock:error: method. This is NOT a rebuilt JitsiMeetSDK framework: Objective-C runtime replaces the implementation with an adapter that calls the original using a copied configuration. It only modifies playAndRecord configs to measurement / 48kHz. Preserves channel counts, I/O buffer, category, Bluetooth/routing options. Explicit defaultToSpeaker preserves videoChat's implicit speaker default; voiceChat/earpiece configs receive no added speaker option. Ambient/default teardown is untouched. Jitsi's original RTC locking and activation remain in charge. No periodic competing setters.

Install before conference options creation. Guard method existence and ABI; failure leaves normal behavior and diagnostic reason. Record installed flag, intercepted request count, original requested mode alongside actual AVAudioSession mode in every native diagnostic entry. This only measures adapter usage, not microphone bandwidth. WebRTC's VoiceProcessing I/O can still affect audio even if measurement persists. The internal method is version dependent; do not migrate SDK versions without revalidation.

Removed 428's external pre/post-recorder mode setters to isolate this experiment. Recorder and byte splitter are otherwise unchanged (continuous PCM16 mono 48kHz WAV, 10s then 60s, final tail). No Android modifications or new microphone source.

Checks: Objective-C iOS syntax + Swift typecheck, native adapter tests for config copy, error/result forwarding, repeated install, voice/video routing, ambient teardown, missing class and incompatible ABI; five existing PCM/splitter/recorder tests. Hardware required: actual installed adapter and request count; persistent actual measurement; speech and echo at peer; speaker/earpiece/headphones, mute, camera, reconnect and final recording upload. A full-band result is not claimed until measured.
