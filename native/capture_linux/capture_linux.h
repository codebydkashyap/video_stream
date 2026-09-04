// native/capture_linux/capture_linux.h
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef struct {
    uint8_t*  data;
    int32_t   width;
    int32_t   height;
    int64_t   timestamp_us;
} CaptureFrame;

int32_t       capture_init(int32_t monitor_index);
CaptureFrame* capture_next_frame(void);
void          capture_free_frame(CaptureFrame* frame);
void          capture_destroy(void);

#ifdef __cplusplus
}
#endif
