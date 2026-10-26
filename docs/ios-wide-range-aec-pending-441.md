# iOS 441: defer transient configuration failure until actual start

440 device diagnostics: the new repair never ran (preStartRepairs=0). A repeated Jitsi configuration during VPIO initialization failed its wide-input trial and set disabled before AudioOutputUnitStart. Thus 440 still recorded with standard voice processing; the owner reports no echo and an unchanged approximately 12kHz cutoff.

441 keeps a speaker-call trial pending while no unit is running, including repeated default/voiceChat transitions, rejected preferences and rejected trial configurations. A failed trial configuration falls back to Jitsi's original configuration for initialization without cancelling the final pre-start attempt. Actual mode/preference rejection during pre-start or unconfirmed enabled/bypass status after start remains a permanent protected fallback for that conference. A failed AudioOutputUnitStart now restores VPIO immediately and preserves the original OSStatus.

Diagnostics separately retain configurationAttempt and preStartAttempt: configuration/mode acceptance, availability, preference acceptance, error domains/codes and observed mode; configurationAttempts and lastStartStatus are included. Existing preStartRepairs and API-enabled confirmation remain authoritative. No unbounded retry loop; each actual start has one pre-start verification. No recorder/chunk/upload/UI/backend changes.

Validation: 17 host scenarios, including three transient configuration regressions, permanent failure, non-recursive RTC locking, route/capture loss and start failure. Five existing recorder/chunk/tail tests and iOS syntax check pass. Physical capability, echo and spectrum remain to be tested on device.
