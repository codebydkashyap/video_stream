// native/capture_linux/capture_linux.c
// Linux X11 screen capture using XShm extension for zero-copy shared memory.
// Compile: gcc -shared -fPIC capture_linux.c -lX11 -lXext -o libcapture_linux.so

#include "capture_linux.h"
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <sys/shm.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdio.h>

static Display*         g_display   = NULL;
static Window           g_root      = 0;
static XShmSegmentInfo  g_shm       = {0};
static XImage*          g_image     = NULL;
static int32_t          g_width     = 0;
static int32_t          g_height    = 0;
static int              g_use_shm   = 0;

static int64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000000LL + ts.tv_nsec / 1000LL;
}

int32_t capture_init(int32_t monitor_index) {
    (void)monitor_index; // X11: always capture default/primary screen

    g_display = XOpenDisplay(NULL);
    if (!g_display) { fprintf(stderr, "[capture_linux] Cannot open display\n"); return -1; }

    g_root   = DefaultRootWindow(g_display);
    g_width  = DisplayWidth(g_display,  DefaultScreen(g_display));
    g_height = DisplayHeight(g_display, DefaultScreen(g_display));

    // Try shared memory (faster path)
    int shm_major, shm_minor;
    Bool shm_pixmaps;
    if (XShmQueryVersion(g_display, &shm_major, &shm_minor, &shm_pixmaps)) {
        g_image = XShmCreateImage(
            g_display,
            DefaultVisual(g_display, DefaultScreen(g_display)),
            DefaultDepth(g_display, DefaultScreen(g_display)),
            ZPixmap, NULL, &g_shm, g_width, g_height);

        if (g_image) {
            g_shm.shmid  = shmget(IPC_PRIVATE,
                                   (size_t)g_image->bytes_per_line * g_image->height,
                                   IPC_CREAT | 0777);
            g_shm.shmaddr = g_image->data = (char*)shmat(g_shm.shmid, 0, 0);
            g_shm.readOnly = 0;
            XShmAttach(g_display, &g_shm);
            XSync(g_display, False);
            g_use_shm = 1;
        }
    }

    if (!g_image) {
        // Fallback: XGetImage
        g_use_shm = 0;
    }

    return 0;
}

CaptureFrame* capture_next_frame(void) {
    if (!g_display) return NULL;

    uint8_t* pixels = NULL;
    size_t   size   = (size_t)g_width * g_height * 4;

    if (g_use_shm && g_image) {
        XShmGetImage(g_display, g_root, g_image, 0, 0, AllPlanes);
        pixels = (uint8_t*)malloc(size);
        if (!pixels) return NULL;
        memcpy(pixels, g_image->data, size);
    } else {
        XImage* img = XGetImage(g_display, g_root, 0, 0, g_width, g_height, AllPlanes, ZPixmap);
        if (!img) return NULL;
        pixels = (uint8_t*)malloc(size);
        if (!pixels) { XDestroyImage(img); return NULL; }
        memcpy(pixels, img->data, size);
        XDestroyImage(img);
    }

    CaptureFrame* frame = (CaptureFrame*)malloc(sizeof(CaptureFrame));
    frame->data         = pixels;
    frame->width        = g_width;
    frame->height       = g_height;
    frame->timestamp_us = now_us();
    return frame;
}

void capture_free_frame(CaptureFrame* frame) {
    if (frame) {
        free(frame->data);
        free(frame);
    }
}

void capture_destroy(void) {
    if (g_use_shm && g_image) {
        XShmDetach(g_display, &g_shm);
        XDestroyImage(g_image);
        shmdt(g_shm.shmaddr);
        shmctl(g_shm.shmid, IPC_RMID, 0);
        g_image = NULL;
    }
    if (g_display) {
        XCloseDisplay(g_display);
        g_display = NULL;
    }
}
