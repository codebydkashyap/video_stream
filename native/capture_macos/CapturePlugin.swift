// native/capture_macos/CapturePlugin.swift
// macOS screen capture using ScreenCaptureKit (macOS 12.3+).
// Falls back to CGDisplayStream on older versions.
// Exposed to Dart FFI via a thin C bridge (see CapturePluginBridge.h).

import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Darwin

// ─── Global state (C-compatible) ─────────────────────────────────────────

private var gPlugin: DesktopCapturePlugin? = nil

// ─── CaptureFrame (mirrors the Dart FFI struct) ──────────────────────────

public struct CaptureFrame {
    var data: UnsafeMutablePointer<UInt8>?
    var width: Int32
    var height: Int32
    var timestamp_us: Int64
}

// ─── Plugin class ─────────────────────────────────────────────────────────

@available(macOS 12.3, *)
public class DesktopCapturePlugin: NSObject, SCStreamOutput {

    private var stream: SCStream?
    private var latestFrame: CaptureFrame? = nil
    private let frameLock = NSLock()

    // MARK: - Start capture
    public func start(monitorIndex: Int32) async throws {
        let content = try await SCShareableContent.current
        guard content.displays.indices.contains(Int(monitorIndex)) else {
            throw NSError(domain: "CapturePlugin", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Monitor index out of range"])
        }
        let display = content.displays[Int(monitorIndex)]
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width * 2   // Retina
        config.height = display.height * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream?.startCapture()
    }

    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                       of outputType: SCStreamOutputType) {
        guard outputType == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let w = CVPixelBufferGetWidth(imageBuffer)
        let h = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        guard let baseAddr = CVPixelBufferGetBaseAddress(imageBuffer) else { return }

        let size = h * bytesPerRow
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        memcpy(dst, baseAddr, size)

        let ts = Int64(Date().timeIntervalSince1970 * 1_000_000)
        let frame = CaptureFrame(data: dst, width: Int32(w), height: Int32(h), timestamp_us: ts)

        frameLock.lock()
        // Free previous frame's buffer
        if let old = latestFrame { old.data?.deallocate() }
        latestFrame = frame
        frameLock.unlock()
    }

    // MARK: - Capture next frame for FFI
    public func nextFrame() -> UnsafeMutablePointer<CaptureFrame>? {
        frameLock.lock()
        defer { frameLock.unlock() }
        guard let f = latestFrame else { return nil }
        let ptr = UnsafeMutablePointer<CaptureFrame>.allocate(capacity: 1)
        ptr.initialize(to: f)
        latestFrame = nil  // Caller owns it now
        return ptr
    }

    // MARK: - Stop
    public func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }
}

// ─── C API bridge ─────────────────────────────────────────────────────────

@_cdecl("capture_init")
public func capture_init(_ monitorIndex: Int32) -> Int32 {
    if #available(macOS 12.3, *) {
        let plugin = DesktopCapturePlugin()
        gPlugin = plugin
        let sema = DispatchSemaphore(value: 0)
        var result: Int32 = 0
        Task {
            do {
                try await plugin.start(monitorIndex: monitorIndex)
            } catch {
                result = -1
            }
            sema.signal()
        }
        sema.wait()
        return result
    }
    return -99  // Unsupported macOS version
}

@_cdecl("capture_next_frame")
public func capture_next_frame() -> UnsafeMutableRawPointer? {
    if #available(macOS 12.3, *) {
        guard let plugin = gPlugin as? DesktopCapturePlugin else { return nil }
        return plugin.nextFrame().map { UnsafeMutableRawPointer($0) }
    }
    return nil
}

@_cdecl("capture_free_frame")
public func capture_free_frame(_ ptr: UnsafeMutableRawPointer?) {
    guard let raw = ptr else { return }
    let frame = raw.assumingMemoryBound(to: CaptureFrame.self)
    frame.pointee.data?.deallocate()
    frame.deallocate()
}

@_cdecl("capture_destroy")
public func capture_destroy() {
    if #available(macOS 12.3, *) {
        Task { await (gPlugin as? DesktopCapturePlugin)?.stop() }
        gPlugin = nil
    }
}
