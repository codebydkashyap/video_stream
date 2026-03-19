// lib/core/config/app_config.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'turn_config.dart';

class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  late SharedPreferences _prefs;

  // ─────────────────────────────────────────────────────────────────────────
  // TODO: Replace the URL below with your actual Render deployment URL.
  //
  // How to find it:
  //   1. Go to https://dashboard.render.com
  //   2. Open your signaling server service
  //   3. Copy the URL shown (e.g. https://desktop-share-signaling-xxxx.onrender.com)
  //   4. Replace "https://" with "wss://" and paste here.
  //
  // If this URL is wrong, BOTH devices will fail to talk to each other.
  // ─────────────────────────────────────────────────────────────────────────
  static const String _defaultSignalingUrl = 'wss://signaling.onrender.com/';

  String get signalingUrl {
    final saved = _prefs.getString('signaling_url');
    final url = (saved != null && saved.isNotEmpty) ? saved : _defaultSignalingUrl;
    if (url == _defaultSignalingUrl) {
      debugPrint(
        '[AppConfig] ⚠️  WARNING: Using placeholder signaling URL "$url". '
        'Cross-device connection will NOT work until you update this to your actual Render URL.',
      );
    }
    return url;
  }

  // STUN-only ICE servers (fast path, tried first by WebRTC automatically)
  // If ICE fails with these, the host/viewer services will retry with TURN.
  List<Map<String, dynamic>> get stunOnlyIceServers => TurnConfig.stunOnlyServers;

  // Full ICE server list: STUN + TURN relay
  List<Map<String, dynamic>> get iceServers => TurnConfig.iceServers;

  int get captureMonitorIndex => _prefs.getInt('monitor_index') ?? 0;
  int get targetFps => _prefs.getInt('target_fps') ?? 30;
  int get maxBitrateBps => _prefs.getInt('max_bitrate_bps') ?? 4000000;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Update the signaling server URL at runtime and persist it.
  Future<void> setSignalingUrl(String url) async {
    await _prefs.setString('signaling_url', url);
  }

  Future<void> setCaptureMonitor(int index) async {
    await _prefs.setInt('monitor_index', index);
  }
}

