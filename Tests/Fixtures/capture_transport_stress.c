#include "PressTalkHAL.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <sched.h>

static PTHAL *capture;
static _Atomic unsigned readBlocks;
static const unsigned blocks = 10000;
static void *produce(void *unused) {
    float input[257];
    double sampleTime = 0;
    for (unsigned block = 0; block < blocks; block++) {
        // Keep this producer behind the queue capacity without modifying its
        // production callback. Consumer/producer execute concurrently.
        while (block - atomic_load(&readBlocks) >= 16) sched_yield();
        unsigned count = 1 + block % 257;
        for (unsigned i = 0; i < count; i++) input[i] = (float)(block * 257 + i) / 4000000;
        pt_test_push(capture, input, count, sampleTime);
        sampleTime += count;
    }
    return NULL;
}
int main(void) {
    capture = pt_test_create(48000, 257);
    assert(capture);
    pthread_t producer;
    assert(pthread_create(&producer, NULL, produce, NULL) == 0);
    float output[257];
    uint64_t frames = 0;
    for (unsigned block = 0; block < blocks;) {
        unsigned count = pt_read(capture, output, 257);
        assert(pt_stats(capture).failure == 0);
        if (!count) { sched_yield(); continue; }
        assert(count == 1 + block % 257);
        for (unsigned i = 0; i < count; i++) assert(output[i] == (float)(block * 257 + i) / 4000000);
        frames += count;
        atomic_store(&readBlocks, ++block);
    }
    assert(pthread_join(producer, NULL) == 0);
    PTStats stats = pt_stats(capture);
    assert(stats.retainedFrames == frames && stats.consumedFrames == frames);
    assert(pt_destroy(capture));
    // An oversized callback must be rejected before reading even a one-float source.
    capture = pt_test_create(48000, 8);
    float one = 1;
    pt_test_push(capture, &one, 9, 0);
    assert(pt_stats(capture).failure == PT_CAPACITY);
    assert(pt_destroy(capture));
    printf("PASS: %u concurrent blocks, %llu exact frames, capacity fault rejected\n", blocks, frames);
}
