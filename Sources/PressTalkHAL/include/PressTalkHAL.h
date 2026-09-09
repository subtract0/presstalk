#ifndef PRESSTALK_HAL_H
#define PRESSTALK_HAL_H
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct PTHAL PTHAL;
enum { PT_OK = 0, PT_SETUP = 1, PT_RENDER = 2, PT_CAPACITY = 3,
       PT_OVERFLOW = 4, PT_NONFINITE = 5, PT_DISCONTINUITY = 6,
       PT_CONFIGURATION = 7, PT_TEARDOWN = 8, PT_TIMESTAMP = 9 };
typedef struct {
    uint32_t failure;
    int32_t status;
    uint32_t boundDevice, channels, maximumFrames, selectedChannel;
    double sampleRate, requestedAt, startedAt, firstPCMAt, lastPCMAt;
    uint64_t callbacks, renderedFrames, retainedFrames, consumedFrames, droppedFrames;
    // Valid only for PT_DISCONTINUITY. Preserve both sides of the first jump;
    // a timestamp jump alone does not establish how much audio was lost.
    double discontinuityExpectedSampleTime, discontinuityObservedSampleTime;
} PTStats;
// One control/consumer thread. One HAL producer. Stop before destroy.
PTHAL *pt_create(AudioDeviceID device, uint32_t channel, OSStatus *status);
OSStatus pt_start(PTHAL *c);
OSStatus pt_stop(PTHAL *c);
OSStatus pt_validate(PTHAL *c);
// Does not free a context if HAL teardown failed: callbacks must never see freed memory.
bool pt_destroy(PTHAL *c);
uint32_t pt_read(PTHAL *c, float *destination, uint32_t capacity);
PTStats pt_stats(PTHAL *c);
void pt_invalidate(PTHAL *c);
double pt_now(void);
// Deterministic transport fixture, using the same validation and queue as the HAL callback.
PTHAL *pt_test_create(double rate, uint32_t maximumFrames);
void pt_test_push(PTHAL *c, const float *pcm, uint32_t frames, double sampleTime);
void pt_test_property_change(PTHAL *c, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element);
#endif
