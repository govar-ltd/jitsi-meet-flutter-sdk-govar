# iOS 440: reapply wide input after VPIO initialization

439 device diagnostics show default -> implicit voiceChat -> ordinary fallback before the recorder starts. Apple documents that creating VoiceProcessingIO implicitly selects voiceChat. This is not proof that the handset lacks the new echo-cancelled input API.

Before the pinned M124 AudioOutputUnitStart call, reacquire the RTC configuration lock, restore default mode and request echo-cancelled input again. M124 StartPlayout/StartRecording, UpdateAudioUnit and sample-rate restart invoke Start without this lock; AudioUnitInitialize may hold it, so no session setters or recursive locking are added in the Initialize hook. Session setters run outside the policy state lock. Existing generation guards, bypass readback, API-enabled confirmation after start and recorder/route-loss fallback remain intact.

Diagnostics retain the mode before repair, number of attempts, availability and preference acceptance after repair. If preference or mode is rejected, restore ordinary VPIO. No custom ADM, RemoteIO replacement, software AEC change, recorder format or chunk-upload change.

Validation: host scenarios include implicit voiceChat between initialization and start, rejected mode restoration and a non-recursive RTC-lock mock. iOS device compilation is syntax-checked separately. Actual echo and spectrum remain unverified until an on-device call.

Primary references:
- https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat
- https://developer.apple.com/documentation/avfaudio/avaudiosession/setprefersechocancelledinput(_:)
- https://webrtc.googlesource.com/src/+/refs/branch-heads/6367/sdk/objc/native/src/audio/audio_device_ios.mm
- https://webrtc.googlesource.com/src/+/refs/branch-heads/6367/sdk/objc/components/audio/RTCAudioSession.mm
