# iOS 443 gain trial

Rollback: tag rollback-ios-442-aec3, SDK862cb650d641b4b2914475ba6c4c389ec042fe14, signed442 artifact retained.

Keep RemoteIO measurement and AEC3 unchanged. Apply fixed microphone gain8 (+18.06dB) after AEC, before shared WAV/RTC sink. Apply playback gain2 (+6.02dB) before speaker AND render reference. Both stages have sample-peak limit30000 PCM16, immediate attenuation and100ms release. No AGC/NS/HPF changes. Diagnostic gainPolicy and limited sample counters identify actual path.

Synthetic core tests verify exact quiet-signal gains, peak protection/recovery, continuity, AEC, doubletalk and17kHz retention. Physical maximum-volume echo and perceived loudness remain to be tested.
