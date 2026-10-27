#include "GovarAEC3.h"
#include "api/audio/audio_processing.h"
#include <algorithm>
struct GovarAECState {
  rtc::scoped_refptr<webrtc::AudioProcessing> apm;
  webrtc::StreamConfig stream{48000, 1};
};
extern "C" void *GovarAEC3Create() {
  auto *s = new GovarAECState;
  s->apm = webrtc::AudioProcessingBuilder().Create();
  if (!s->apm) { delete s; return nullptr; }
  webrtc::AudioProcessing::Config c;
  c.echo_canceller.enabled = true;
  c.echo_canceller.mobile_mode = false;
  c.echo_canceller.enforce_high_pass_filtering = false;
  c.noise_suppression.enabled = false;
  c.gain_controller1.enabled = false;
  c.gain_controller2.enabled = false;
  c.high_pass_filter.enabled = false;
  s->apm->ApplyConfig(c);
  webrtc::ProcessingConfig streams;
  for (auto &stream : streams.streams) stream = webrtc::StreamConfig(48000, 1);
  if (s->apm->Initialize(streams) != 0) { delete s; return nullptr; }
  return s;
}
extern "C" void GovarAEC3Destroy(void *p) { delete static_cast<GovarAECState *>(p); }
extern "C" int GovarAEC3Render(void *p, const int16_t *input) {
  auto *s = static_cast<GovarAECState *>(p); if (!s || !input) return -1;
  int16_t discarded[480];
  return s->apm->ProcessReverseStream(input, s->stream, s->stream, discarded);
}
extern "C" int GovarAEC3Capture(void *p, const int16_t *input, int16_t *output, int delay) {
  auto *s = static_cast<GovarAECState *>(p); if (!s || !input || !output) return -1;
  s->apm->set_stream_delay_ms(std::clamp(delay, 0, 500));
  return s->apm->ProcessStream(input, s->stream, s->stream, output);
}
extern "C" int GovarAEC3Reset(void *p) {
  auto *s = static_cast<GovarAECState *>(p); if (!s) return -1;
  webrtc::ProcessingConfig streams;
  for (auto &stream : streams.streams) stream = webrtc::StreamConfig(48000, 1);
  return s->apm->Initialize(streams);
}
