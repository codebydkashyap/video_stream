// native/capture_windows/capture_windows.h
// Windows screen capture plugin using DXGI Desktop Duplication API.
// Exposes a C API callable from Dart FFI.

#pragma once
#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/// Pixel buffer + metadata for one captured frame.
typedef struct {
    uint8_t*  data;          ///< BGRA pixel data (width * height * 4 bytes)
    int32_t   width;
    int32_t   height;
    int64_t   timestamp_us;  ///< Microseconds since epoch
} CaptureFrame;

/// Initialize the capture session.
/// @param monitor_index  0-based monitor index.
/// @return 0 on success, negative error code on failure.
int32_t capture_init(int32_t monitor_index);

/// Capture the next frame. Returns NULL if no new frame is available.
/// Caller MUST call capture_free_frame() when done.
CaptureFrame* capture_next_frame(void);

/// Release memory for a frame returned by capture_next_frame().
void capture_free_frame(CaptureFrame* frame);

/// Destroy the capture session and release all resources.
void capture_destroy(void);

#ifdef __cplusplus
}
#endif
