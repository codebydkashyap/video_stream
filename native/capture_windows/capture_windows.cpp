// native/capture_windows/capture_windows.cpp
// Windows DXGI Desktop Duplication API screen capture implementation.
// Compile with: cl /LD capture_windows.cpp dxgi.lib d3d11.lib /Fe:capture_windows.dll

#include "capture_windows.h"
#include <d3d11.h>
#include <dxgi1_2.h>
#include <chrono>
#include <cstring>
#include <cstdlib>

// ─── Internal state ────────────────────────────────────────────────────────

static ID3D11Device*              g_device      = nullptr;
static ID3D11DeviceContext*       g_context     = nullptr;
static IDXGIOutputDuplication*    g_duplication = nullptr;
static int32_t                    g_width       = 0;
static int32_t                    g_height      = 0;

// ─── Helpers ──────────────────────────────────────────────────────────────

static int64_t now_us() {
    auto tp = std::chrono::system_clock::now().time_since_epoch();
    return std::chrono::duration_cast<std::chrono::microseconds>(tp).count();
}

// ─── Public API ───────────────────────────────────────────────────────────

extern "C" int32_t capture_init(int32_t monitor_index) {
    HRESULT hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
        nullptr, 0, D3D11_SDK_VERSION,
        &g_device, nullptr, &g_context);
    if (FAILED(hr)) return -1;

    IDXGIDevice*  dxgi_device  = nullptr;
    IDXGIAdapter* dxgi_adapter = nullptr;
    IDXGIOutput*  dxgi_output  = nullptr;
    IDXGIOutput1* dxgi_output1 = nullptr;

    g_device->QueryInterface(__uuidof(IDXGIDevice),  (void**)&dxgi_device);
    dxgi_device->GetParent(__uuidof(IDXGIAdapter), (void**)&dxgi_adapter);
    hr = dxgi_adapter->EnumOutputs(monitor_index, &dxgi_output);
    if (FAILED(hr)) return -2;

    hr = dxgi_output->QueryInterface(__uuidof(IDXGIOutput1), (void**)&dxgi_output1);
    if (FAILED(hr)) return -3;

    DXGI_OUTPUT_DESC desc{};
    dxgi_output->GetDesc(&desc);
    g_width  = desc.DesktopCoordinates.right  - desc.DesktopCoordinates.left;
    g_height = desc.DesktopCoordinates.bottom - desc.DesktopCoordinates.top;

    hr = dxgi_output1->DuplicateOutput(g_device, &g_duplication);
    if (FAILED(hr)) return -4;

    dxgi_output1->Release();
    dxgi_output->Release();
    dxgi_adapter->Release();
    dxgi_device->Release();
    return 0;
}

extern "C" CaptureFrame* capture_next_frame(void) {
    if (!g_duplication) return nullptr;

    DXGI_OUTDUPL_FRAME_INFO frame_info{};
    IDXGIResource* desktop_resource = nullptr;

    HRESULT hr = g_duplication->AcquireNextFrame(16, &frame_info, &desktop_resource);
    if (FAILED(hr)) return nullptr;

    ID3D11Texture2D* desktop_texture = nullptr;
    desktop_resource->QueryInterface(__uuidof(ID3D11Texture2D), (void**)&desktop_texture);

    // Create CPU-readable staging texture
    D3D11_TEXTURE2D_DESC desc{};
    desktop_texture->GetDesc(&desc);
    desc.Usage          = D3D11_USAGE_STAGING;
    desc.BindFlags      = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.MiscFlags      = 0;

    ID3D11Texture2D* staging = nullptr;
    g_device->CreateTexture2D(&desc, nullptr, &staging);
    g_context->CopyResource(staging, desktop_texture);

    D3D11_MAPPED_SUBRESOURCE mapped{};
    g_context->Map(staging, 0, D3D11_MAP_READ, 0, &mapped);

    size_t pixel_count = (size_t)g_width * g_height * 4;
    auto* frame = (CaptureFrame*)malloc(sizeof(CaptureFrame));
    frame->data         = (uint8_t*)malloc(pixel_count);
    frame->width        = g_width;
    frame->height       = g_height;
    frame->timestamp_us = now_us();
    memcpy(frame->data, mapped.pData, pixel_count);

    g_context->Unmap(staging, 0);
    staging->Release();
    desktop_texture->Release();
    desktop_resource->Release();
    g_duplication->ReleaseFrame();

    return frame;
}

extern "C" void capture_free_frame(CaptureFrame* frame) {
    if (frame) {
        free(frame->data);
        free(frame);
    }
}

extern "C" void capture_destroy(void) {
    if (g_duplication) { g_duplication->Release(); g_duplication = nullptr; }
    if (g_context)     { g_context->Release();     g_context     = nullptr; }
    if (g_device)      { g_device->Release();      g_device      = nullptr; }
}
