#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// 48 kHz, mono, signed PCM16, exactly 480 samples per call.
void *GovarAEC3Create(void);
void GovarAEC3Destroy(void *state);
int GovarAEC3Render(void *state, const int16_t *samples);
int GovarAEC3Capture(void *state, const int16_t *samples, int16_t *output, int delay_ms);
int GovarAEC3Reset(void *state);
#ifdef __cplusplus
}
#endif
