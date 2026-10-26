# iOS 438: standard system voice processing comparison

Base: SDK 1a0d301 / successful software-AEC recording branch. For this comparison, conference setup no longer installs the Jitsi measurement-mode adapter, the VPIO bypass interceptor or the software-AEC logger. Use official JitsiWebRTC 124.0.2, not the patched 431 binary: that binary forcibly enables software AEC even if the app stops installing its bypass.

Jitsi's original audio mode, voice-processing I/O and gain configuration own the call. No additional software AEC is forced. A passive image-scoped observer reads bypass/AGC flags after WebRTC init/start without changing any property or return value. Failed observer installation/readback cannot prevent calls. Runtime confirmation is `systemVoiceProcessing.lastBypassReadback=0` with confirmedProcessingStarts>0; this confirms the system path, not acoustic performance.

The continuous AVAudioRecorder PCM16 mono 48kHz WAV, Dart chunking, final tail and upload behavior are unchanged. The file format does not guarantee an unfiltered frequency response. Read actual AVAudioSession rate/mode/routes and compare the recordings before claiming a spectrum fix.

Test max-volume iPhone–Android, double talk, iPhone–iPhone and bot; repeat with recording enabled/disabled and route changes. New iOS 18.2 echo-cancelled input API is deliberately a separate subsequent comparison; not enabled in this build.

No store delivery as part of this task.
