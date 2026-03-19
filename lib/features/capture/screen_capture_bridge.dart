// lib/features/capture/screen_capture_bridge.dart
//
// Cross-platform screen capture bridge using Dart FFI.
// On each platform, this loads the matching native dynamic library and
// exposes a Dart-friendly API.
//
// Platforms:
//   Windows → capture_windows.dll  (DXGI Desktop Duplication)
//   Linux   → libcapture_linux.so  (X11 XShm / PipeWire)
//   macOS   → libcapture_macos.dylib (ScreenCaptureKit / CGDisplayStream)

import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';

// ─── Native struct ---------------------------------------------------------

final class CaptureFrame extends Struct {
  /// Pointer to BGRA pixel buffer (width * height * 4 bytes)
  external Pointer<Uint8> data;

  @Int32()
  external int width;

  @Int32()
  external int height;

  /// Capture timestamp in microseconds since epoch
  @Int64()
  external int timestampUs;
}

// ─── Native function typedefs ---------------------------------------------

typedef _InitNative = Int32 Function(Int32 monitorIndex);
typedef _Init = int Function(int monitorIndex);

typedef _NextFrameNative = Pointer<CaptureFrame> Function();
typedef _NextFrame = Pointer<CaptureFrame> Function();

typedef _FreeFrameNative = Void Function(Pointer<CaptureFrame> frame);
typedef _FreeFrame = void Function(Pointer<CaptureFrame> frame);

typedef _DestroyNative = Void Function();
typedef _Destroy = void Function();

// ─── Bridge class ---------------------------------------------------------

class ScreenCaptureBridge {
  late final DynamicLibrary _lib;
  late final _Init _init;
  late final _NextFrame _nextFrame;
  late final _FreeFrame _freeFrame;
  late final _Destroy _destroy;

  bool _initialized = false;

  ScreenCaptureBridge() {
    _lib = _loadLib();
    _init = _lib.lookupFunction<_InitNative, _Init>('capture_init');
    _nextFrame = _lib.lookupFunction<_NextFrameNative, _NextFrame>('capture_next_frame');
    _freeFrame = _lib.lookupFunction<_FreeFrameNative, _FreeFrame>('capture_free_frame');
    _destroy = _lib.lookupFunction<_DestroyNative, _Destroy>('capture_destroy');
  }

  static DynamicLibrary _loadLib() {
    if (Platform.isWindows) return DynamicLibrary.open('capture_windows.dll');
    if (Platform.isLinux) return DynamicLibrary.open('libcapture_linux.so');
    if (Platform.isMacOS) return DynamicLibrary.open('libcapture_macos.dylib');
    throw UnsupportedError('ScreenCaptureBridge: unsupported platform: ${Platform.operatingSystem}');
  }

  /// Initialize the capture session for [monitorIndex].
  /// Returns 0 on success, negative on error.
  int initialize({int monitorIndex = 0}) {
    final result = _init(monitorIndex);
    _initialized = result == 0;
    if (!_initialized) debugPrint('[ScreenCaptureBridge] init failed, code=$result');
    return result;
  }

  /// Capture and return the next frame.
  /// Caller MUST call [freeFrame] when done to avoid memory leaks.
  Pointer<CaptureFrame>? nextFrame() {
    if (!_initialized) return null;
    final ptr = _nextFrame();
    return ptr == nullptr ? null : ptr;
  }

  /// Free a frame returned by [nextFrame].
  void freeFrame(Pointer<CaptureFrame> frame) => _freeFrame(frame);

  /// Destroy the capture session and release all resources.
  void destroy() {
    if (_initialized) {
      _destroy();
      _initialized = false;
    }
  }
}
