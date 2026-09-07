#include "PressTalkHAL.h"
#include <stdatomic.h>
#include <CoreServices/CoreServices.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mach/mach_time.h>

#define PT_SLOTS 64
#define PT_MAX_FRAMES 16384
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "capture requires lock-free 64-bit atomics");
static _Atomic bool teardownFailed;
struct PTHAL {
    AudioUnit unit;
    AudioBufferList *buffers;
    float *queue;
    uint32_t lengths[PT_SLOTS];
    uint32_t maximumFrames, channels, selectedChannel, boundDevice;
    double sampleRate, requestedAt, startedAt, expectedSampleTime;
    bool haveSampleTime, initialized, running, test;
    uint32_t listenerMask;
    _Atomic bool monitoring;
    _Atomic uint64_t writeIndex, readIndex;
    _Atomic uint32_t failure;
    _Atomic int32_t status;
    _Atomic uint64_t callbacks, renderedFrames, retainedFrames, consumedFrames, droppedFrames;
    _Atomic double firstPCMAt, lastPCMAt;
};
static mach_timebase_info_data_t timebase;
__attribute__((constructor)) static void init_clock(void) { mach_timebase_info(&timebase); }
double pt_now(void) {
    return (double)mach_absolute_time() * timebase.numer / timebase.denom / 1e9;
}
static void fail(PTHAL *c, uint32_t reason, OSStatus status) {
    uint32_t expected = PT_OK;
    if (atomic_compare_exchange_strong(&c->failure, &expected, reason))
        atomic_store(&c->status, status);
}
void pt_invalidate(PTHAL *c) { fail(c, PT_CONFIGURATION, 0); }
static const AudioUnitPropertyID monitoredProperties[] = {
    kAudioOutputUnitProperty_CurrentDevice,
    kAudioUnitProperty_StreamFormat,
    kAudioUnitProperty_MaximumFramesPerSlice
};
static void unit_property_changed(void *context, AudioUnit unit, AudioUnitPropertyID property,
                                  AudioUnitScope scope, AudioUnitElement element) {
    PTHAL *c = context;
    if (!atomic_load(&c->monitoring)) return;
    // This also catches a binding that changes away and back between polls.
    // The callback only marks a sticky fault; teardown remains on the consumer.
    if (property != kAudioUnitProperty_StreamFormat || element == 1) pt_invalidate(c);
}
static bool allocate_queue(PTHAL *c) {
    if (!isfinite(c->sampleRate) || c->sampleRate < 8000 || c->sampleRate > 384000 ||
        !c->maximumFrames || c->maximumFrames > PT_MAX_FRAMES ||
        !c->channels || c->channels > 32 || c->selectedChannel >= c->channels) return false;
    c->queue = calloc((size_t)PT_SLOTS * c->maximumFrames, sizeof(float));
    return c->queue != NULL;
}
static void retain_pcm(PTHAL *c, const float *pcm, uint32_t frames, double sampleTime) {
    if (!frames || atomic_load(&c->failure)) return;
    if (frames > c->maximumFrames) { fail(c, PT_CAPACITY, 0); return; }
    if (!isfinite(sampleTime)) { fail(c, PT_TIMESTAMP, 0); return; }
    if (c->haveSampleTime && fabs(sampleTime - c->expectedSampleTime) > 0.5) {
        fail(c, PT_DISCONTINUITY, 0); return;
    }
    c->expectedSampleTime = sampleTime + frames;
    c->haveSampleTime = true;
    for (uint32_t i = 0; i < frames; i++) {
        if (!isfinite(pcm[i])) { fail(c, PT_NONFINITE, 0); return; }
    }
    uint64_t w = atomic_load_explicit(&c->writeIndex, memory_order_relaxed);
    uint64_t r = atomic_load_explicit(&c->readIndex, memory_order_acquire);
    if (w - r >= PT_SLOTS) {
        atomic_fetch_add(&c->droppedFrames, frames);
        fail(c, PT_OVERFLOW, 0); return;
    }
    uint32_t slot = w % PT_SLOTS;
    memcpy(c->queue + (size_t)slot * c->maximumFrames, pcm, frames * sizeof(float));
    c->lengths[slot] = frames;
    double now = pt_now();
    if (!atomic_load(&c->firstPCMAt)) atomic_store(&c->firstPCMAt, now);
    atomic_store(&c->lastPCMAt, now);
    atomic_fetch_add(&c->retainedFrames, frames);
    atomic_store_explicit(&c->writeIndex, w + 1, memory_order_release);
}
static OSStatus input_callback(void *context, AudioUnitRenderActionFlags *flags,
                               const AudioTimeStamp *time, UInt32 bus, UInt32 frames,
                               AudioBufferList *unused) {
    PTHAL *c = context;
    atomic_fetch_add(&c->callbacks, 1);
    if (atomic_load(&c->failure)) return noErr;
    if (frames > c->maximumFrames) { fail(c, PT_CAPACITY, 0); return noErr; }
    for (uint32_t ch = 0; ch < c->channels; ch++)
        c->buffers->mBuffers[ch].mDataByteSize = frames * sizeof(float);
    OSStatus s = AudioUnitRender(c->unit, flags, time, 1, frames, c->buffers);
    if (s || (*flags & kAudioUnitRenderAction_PostRenderError)) { fail(c, PT_RENDER, s); return noErr; }
    atomic_fetch_add(&c->renderedFrames, frames);
    if (!(time->mFlags & kAudioTimeStampSampleTimeValid)) {
        fail(c, PT_TIMESTAMP, 0); return noErr;
    }
    if (c->buffers->mNumberBuffers != c->channels) { fail(c, PT_CONFIGURATION, 0); return noErr; }
    for (uint32_t ch = 0; ch < c->channels; ch++) {
        AudioBuffer b = c->buffers->mBuffers[ch];
        if (!b.mData || b.mNumberChannels != 1 || b.mDataByteSize != frames * sizeof(float)) {
            fail(c, PT_CONFIGURATION, 0); return noErr;
        }
    }
    retain_pcm(c, c->buffers->mBuffers[c->selectedChannel].mData, frames, time->mSampleTime);
    return noErr;
}
PTHAL *pt_create(AudioDeviceID device, uint32_t channel, OSStatus *outStatus) {
    if (atomic_load(&teardownFailed)) { *outStatus = kAudioUnitErr_CannotDoInCurrentContext; return NULL; }
    PTHAL *c = calloc(1, sizeof(PTHAL));
    if (!c) { *outStatus = memFullErr; return NULL; }
    c->requestedAt = pt_now(); c->selectedChannel = channel;
    AudioComponentDescription desc = {kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
                                      kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    OSStatus s = component ? AudioComponentInstanceNew(component, &c->unit) : kAudio_ParamError;
#define CHECK(call) do { s = (call); if (s) goto error; } while (0)
    if (s) goto error;
    UInt32 on = 1, off = 0;
    CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, sizeof(on)));
    CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, sizeof(off)));
    CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof(device)));
    UInt32 size = sizeof(c->boundDevice);
    CHECK(AudioUnitGetProperty(c->unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &c->boundDevice, &size));
    if (c->boundDevice != device || device == kAudioObjectUnknown) { s = kAudio_ParamError; goto error; }
    AudioStreamBasicDescription hardware = {0}; size = sizeof(hardware);
    CHECK(AudioUnitGetProperty(c->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size));
    c->sampleRate = hardware.mSampleRate; c->channels = hardware.mChannelsPerFrame;
    c->maximumFrames = 4096;
    if (!isfinite(c->sampleRate) || c->sampleRate < 8000 || c->sampleRate > 384000 ||
        !c->channels || c->channels > 32 || channel >= c->channels) { s = kAudio_ParamError; goto error; }
    AudioStreamBasicDescription client = {c->sampleRate, kAudioFormatLinearPCM,
        kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
        4, 1, 4, c->channels, 32, 0};
    CHECK(AudioUnitSetProperty(c->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client, sizeof(client)));
    AudioStreamBasicDescription accepted = {0}; size = sizeof(accepted);
    CHECK(AudioUnitGetProperty(c->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &accepted, &size));
    if (memcmp(&client, &accepted, sizeof(client))) { s = kAudio_ParamError; goto error; }
    CHECK(AudioUnitSetProperty(c->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &c->maximumFrames, sizeof(c->maximumFrames)));
    CHECK(AudioUnitSetProperty(c->unit, kAudioUnitProperty_ShouldAllocateBuffer, kAudioUnitScope_Output, 1, &off, sizeof(off)));
    AURenderCallbackStruct callback = {input_callback, c};
    CHECK(AudioUnitSetProperty(c->unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(callback)));
    CHECK(AudioUnitInitialize(c->unit)); c->initialized = true;
    size = sizeof(c->maximumFrames);
    CHECK(AudioUnitGetProperty(c->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &c->maximumFrames, &size));
    if (!allocate_queue(c)) { s = memFullErr; goto error; }
    c->buffers = calloc(1, offsetof(AudioBufferList, mBuffers) + c->channels * sizeof(AudioBuffer));
    if (!c->buffers) { s = memFullErr; goto error; }
    c->buffers->mNumberBuffers = c->channels;
    for (uint32_t ch = 0; ch < c->channels; ch++) {
        c->buffers->mBuffers[ch] = (AudioBuffer){1, c->maximumFrames * sizeof(float), calloc(c->maximumFrames, sizeof(float))};
        if (!c->buffers->mBuffers[ch].mData) { s = memFullErr; goto error; }
    }
    for (uint32_t i = 0; i < 3; i++) {
        CHECK(AudioUnitAddPropertyListener(c->unit, monitoredProperties[i], unit_property_changed, c));
        c->listenerMask |= 1u << i;
    }
    *outStatus = noErr; return c;
error:
    *outStatus = s;
    pt_destroy(c);
    return NULL;
#undef CHECK
}
OSStatus pt_start(PTHAL *c) {
    atomic_store(&c->monitoring, true);
    OSStatus s = AudioOutputUnitStart(c->unit);
    if (s) fail(c, PT_SETUP, s);
    else { c->running = true; c->startedAt = pt_now(); }
    return s;
}
OSStatus pt_validate(PTHAL *c) {
    if (c->test) return noErr;
    UInt32 device = 0, size = sizeof(device);
    OSStatus s = AudioUnitGetProperty(c->unit, kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global, 0, &device, &size);
    if (s || device != c->boundDevice) goto invalid;
    AudioStreamBasicDescription hardware = {0}; size = sizeof(hardware);
    s = AudioUnitGetProperty(c->unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 1, &hardware, &size);
    if (s || hardware.mSampleRate != c->sampleRate || hardware.mChannelsPerFrame != c->channels) goto invalid;
    AudioStreamBasicDescription client = {0}; size = sizeof(client);
    s = AudioUnitGetProperty(c->unit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output, 1, &client, &size);
    if (s || client.mSampleRate != c->sampleRate || client.mChannelsPerFrame != c->channels ||
        client.mFormatID != kAudioFormatLinearPCM || client.mBytesPerFrame != 4 ||
        client.mFormatFlags != (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved)) goto invalid;
    UInt32 maximum = 0; size = sizeof(maximum);
    s = AudioUnitGetProperty(c->unit, kAudioUnitProperty_MaximumFramesPerSlice,
        kAudioUnitScope_Global, 0, &maximum, &size);
    if (s || !maximum || maximum > c->maximumFrames) goto invalid;
    return noErr;
invalid:
    fail(c, PT_CONFIGURATION, s);
    return s ? s : kAudio_ParamError;
}
OSStatus pt_stop(PTHAL *c) {
    if (!c->running) { atomic_store(&c->monitoring, false); return noErr; }
    OSStatus s = AudioOutputUnitStop(c->unit);
    if (s) fail(c, PT_TEARDOWN, s);
    else { c->running = false; atomic_store(&c->monitoring, false); }
    return s;
}
bool pt_destroy(PTHAL *c) {
    if (!c) return true;
    if (pt_stop(c)) { atomic_store(&teardownFailed, true); return false; }
    for (uint32_t i = 0; i < 3; i++) {
        if (!(c->listenerMask & (1u << i))) continue;
        OSStatus status = AudioUnitRemovePropertyListenerWithUserData(
            c->unit, monitoredProperties[i], unit_property_changed, c);
        if (status) { fail(c, PT_TEARDOWN, status); atomic_store(&teardownFailed, true); return false; }
        c->listenerMask &= ~(1u << i);
    }
    if (c->initialized && AudioUnitUninitialize(c->unit)) { fail(c, PT_TEARDOWN, 0); atomic_store(&teardownFailed, true); return false; }
    c->initialized = false;
    if (c->unit && AudioComponentInstanceDispose(c->unit)) { fail(c, PT_TEARDOWN, 0); atomic_store(&teardownFailed, true); return false; }
    c->unit = NULL;
    if (c->buffers) {
        for (uint32_t ch = 0; ch < c->channels; ch++) free(c->buffers->mBuffers[ch].mData);
        free(c->buffers);
    }
    free(c->queue); free(c); return true;
}
uint32_t pt_read(PTHAL *c, float *destination, uint32_t capacity) {
    if (atomic_load(&c->failure)) return 0;
    uint64_t r = atomic_load_explicit(&c->readIndex, memory_order_relaxed);
    if (r == atomic_load_explicit(&c->writeIndex, memory_order_acquire)) return 0;
    uint32_t slot = r % PT_SLOTS, n = c->lengths[slot];
    if (n > capacity) { fail(c, PT_CAPACITY, 0); return 0; }
    memcpy(destination, c->queue + (size_t)slot * c->maximumFrames, n * sizeof(float));
    atomic_fetch_add(&c->consumedFrames, n);
    atomic_store_explicit(&c->readIndex, r + 1, memory_order_release);
    return n;
}
PTStats pt_stats(PTHAL *c) {
    return (PTStats){atomic_load(&c->failure), atomic_load(&c->status),
        c->boundDevice, c->channels, c->maximumFrames, c->selectedChannel,
        c->sampleRate, c->requestedAt, c->startedAt,
        atomic_load(&c->firstPCMAt), atomic_load(&c->lastPCMAt),
        atomic_load(&c->callbacks), atomic_load(&c->renderedFrames), atomic_load(&c->retainedFrames),
        atomic_load(&c->consumedFrames), atomic_load(&c->droppedFrames)};
}
PTHAL *pt_test_create(double rate, uint32_t maximumFrames) {
    PTHAL *c = calloc(1, sizeof(PTHAL));
    if (!c) return NULL;
    c->test = true; c->sampleRate = rate; c->channels = 1;
    c->maximumFrames = maximumFrames; c->requestedAt = pt_now();
    if (!allocate_queue(c)) { free(c); return NULL; }
    return c;
}
void pt_test_push(PTHAL *c, const float *pcm, uint32_t frames, double sampleTime) {
    if (!c->test) return;
    atomic_fetch_add(&c->callbacks, 1);
    atomic_fetch_add(&c->renderedFrames, frames);
    retain_pcm(c, pcm, frames, sampleTime);
}
void pt_test_property_change(PTHAL *c, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element) {
    if (!c->test) return;
    atomic_store(&c->monitoring, true);
    unit_property_changed(c, NULL, property, scope, element);
    atomic_store(&c->monitoring, false);
}
