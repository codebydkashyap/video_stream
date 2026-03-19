// lib/core/webrtc/webrtc_repository.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';

class WebRTCRepository {
  final _config = AppConfig.instance;

  static const _foregroundChannel =
      MethodChannel('com.example.desktop_sharing/foreground_service');

  /// Creates a PeerConnection.
  ///
  /// [useTurn] – when `false` (default) only STUN servers are used (fast path).
  /// When `true`, TURN relay servers are included so peers can connect even
  /// through strict firewalls / symmetric NATs.
  ///
  /// The host & viewer services call this with [useTurn]=true automatically
  /// when ICE connection state reaches `failed` on the STUN-only attempt.
  Future<RTCPeerConnection> createPC({bool useTurn = false}) async {
    final iceServers =
        useTurn ? _config.iceServers : _config.stunOnlyIceServers;

    debugPrint(
      '[WebRTCRepository] createPC() — useTurn=$useTurn, '
      'using ${iceServers.length} ICE server(s)',
    );

    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      // Allow ICE restart when retrying with TURN
      'iceTransportPolicy': useTurn ? 'relay' : 'all',
    });
    return pc;
  }

  Future<MediaStream> getScreenStream() async {
    try {
      // Android specific: Request notification permission and start foreground service
      if (!kIsWeb && Platform.isAndroid) {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }

        // Android 14/15 FIX: Start service in 'initial' mode FISRT (no mediaProjection type yet)
        // to stay alive while the user accepts the system "Screen Cast" dialog.
        try {
          await _foregroundChannel.invokeMethod('startForegroundService', {
            'title': 'Preparing Screen Share',
            'body': 'Please accept the system prompt...',
            'mode': 'initial',
          });
        } catch (e) {
          debugPrint('[WebRTCRepository] Initial foreground service start failed: $e');
        }
      }

      // For macOS, getDisplayMedia is significantly more stable and handles
      // permissions/system picker correctly on macOS 14/15.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        return await navigator.mediaDevices.getDisplayMedia({
          'audio': false,
          'video': true,
        });
      }

      // Capture the stream (this triggers the system dialog on Android)
      final MediaStream stream;
      
      // Determine capture method
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux)) {
        stream = await _getDesktopCaptureStream();
      } else {
        stream = await navigator.mediaDevices.getDisplayMedia({
          'audio': false,
          'video': true,
        });
      }

      // Android 14/15 FIX: Once we HAVE the stream (token granted), "upgrade" the service
      // to FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION to satisfy the OS requirement.
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await _foregroundChannel.invokeMethod('startForegroundService', {
            'title': 'Screen Sharing Active',
            'body': 'You are sharing your screen...',
            'mode': 'active',
          });
        } catch (e) {
          debugPrint('[WebRTCRepository] Upgrading foreground service failed: $e');
        }
      }

      return stream;
    } catch (e) {
      debugPrint('[WebRTCRepository] getScreenStream fatal error: $e');
      rethrow;
    }
  }

  /// Helper for Windows/Linux desktop capture
  Future<MediaStream> _getDesktopCaptureStream() async {
    final List<DesktopCapturerSource> sources =
        await desktopCapturer.getSources(types: [SourceType.Screen]);
    if (sources.isNotEmpty) {
      final source = sources.first;
      debugPrint('[WebRTCRepository] Capturing screen: ${source.name}');
      return await navigator.mediaDevices.getUserMedia({
        'video': {
          'mandatory': {
            'chromeMediaSource': 'screen',
            'chromeMediaSourceId': source.id,
            'maxFrameRate': 30,
          },
          'optional': [],
        },
        'audio': false,
      });
    }
    throw Exception('No screen capture sources found');
  }

  /// Stop the foreground service (call when screen sharing stops)
  Future<void> stopForegroundService() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _foregroundChannel.invokeMethod('stopForegroundService');
      } catch (e) {
        debugPrint('[WebRTCRepository] Failed to stop foreground service: $e');
      }
    }
  }

  Future<MediaStream> getUserMedia({bool video = true, bool audio = true}) async {
    try {
      // Permission handling specifically for mobile (Android/iOS) where it is mandatory.
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final permissionsToRequest = <Permission>[];
        if (audio && await Permission.microphone.isDenied) {
          permissionsToRequest.add(Permission.microphone);
        }
        if (video && await Permission.camera.isDenied) {
          permissionsToRequest.add(Permission.camera);
        }
        
        if (permissionsToRequest.isNotEmpty) {
          debugPrint('[WebRTCRepository] Requesting permissions: $permissionsToRequest');
          await permissionsToRequest.request();
        }
      }

      final constraints = {
        'audio': audio
            ? {
                'echoCancellation': true,
                'noiseSuppression': true,
                'autoGainControl': true,
              }
            : false,
        'video': video
            ? {
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 30},
                'facingMode': 'user',
              }
            : false,
      };

      debugPrint('[WebRTCRepository] Calling getUserMedia with constraints: $constraints');

      if (!kIsWeb && Platform.isAndroid) {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }

        // Start foreground service for Cam/Mic usage to maintain background access
        try {
          await _foregroundChannel.invokeMethod('startForegroundService', {
            'title': 'Meeting Active',
            'body': 'Camera/Microphone is in use...',
            'mode': 'active', // Use active mode for camera/mic
          });
        } catch (e) {
          debugPrint('[WebRTCRepository] Foreground service start failed for getUserMedia: $e');
        }
      }
      
      return await navigator.mediaDevices.getUserMedia(constraints);
    } catch (e) {
      debugPrint('[WebRTCRepository] getUserMedia error: $e');
      rethrow;
    }
  }
}
