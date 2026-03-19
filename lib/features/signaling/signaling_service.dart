// lib/features/signaling/signaling_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum SignalingState { disconnected, connecting, connected, error }

typedef SignalHandler = void Function(Map<String, dynamic> msg);

class SignalingService extends ChangeNotifier {
  final String serverUrl;
  WebSocketChannel? _channel;
  String? _deviceId;
  SignalingState _state = SignalingState.disconnected;
  SignalingState get state => _state;

  final Map<String, SignalHandler> _handlers = {};
  StreamSubscription? _sub;

  SignalingService(this.serverUrl);

  /// Connect and register as a device
  Future<void> connect({
    required String deviceId,
    required String authToken,
  }) async {
    _deviceId = deviceId;
    debugPrint('[SignalingService] connect() called for device: $deviceId using token: $authToken to $serverUrl');
    _setState(SignalingState.connecting);
    try {
      debugPrint('[SignalingService] Opening WebSocket connection to $serverUrl ...');
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      
      // Wait for the connection to be established (longer timeout for Render cold starts)
      debugPrint('[SignalingService] Waiting for WebSocket to be ready (up to 30s)...');
      await _channel!.ready.timeout(const Duration(seconds: 30), onTimeout: () {
        throw TimeoutException('Signaling connection timed out after 30 seconds. This often happens if the Render free tier service is sleeping.');
      });
      debugPrint('[SignalingService] WebSocket connected successfully.');

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          debugPrint('[SignalingService] WebSocket stream error: $e');
          _setState(SignalingState.error);
        },
        onDone: () {
          debugPrint('[SignalingService] WebSocket connection closed.');
          _setState(SignalingState.disconnected);
        },
      );
      _setState(SignalingState.connected);
      debugPrint('[SignalingService] WebSocket listening. Sending register message...');
      send({'type': 'register', 'deviceId': deviceId, 'token': authToken});
    } catch (e, stack) {
      debugPrint('[SignalingService] connect() FAILED: $e');
      debugPrint('[SignalingService] Stack trace: $stack');
      _setState(SignalingState.error);
    }
  }

  void _onMessage(dynamic raw) {
    debugPrint('[SignalingService] RECEIVED: $raw');
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      
      // Filter out noisy status messages or outbound-only messages that might be echoed
      if (type == 'registered' || type == 'pairing_set' || type == 'register' || type == 'disconnect') return;

      if (type != null && _handlers.containsKey(type)) {
        debugPrint('[SignalingService] Dispatching handled message type: $type');
        _handlers[type]!(msg);
      } else {
        debugPrint('[SignalingService] No handler registered for message type: $type');
      }
    } catch (e) {
      debugPrint('[SignalingService] Error decoding message: $e');
    }
  }

  void on(String type, SignalHandler handler) => _handlers[type] = handler;

  void send(Map<String, dynamic> msg) {
    if (_state == SignalingState.connected) {
      debugPrint('[SignalingService] SENDING: ${jsonEncode(msg)}');
      _channel?.sink.add(jsonEncode(msg));
    }
  }

  void sendOffer(String targetId, String sdp) =>
      send({'type': 'offer', 'to': targetId, 'from': _deviceId, 'payload': sdp});

  void sendAnswer(String targetId, String sdp) =>
      send({'type': 'answer', 'to': targetId, 'from': _deviceId, 'payload': sdp});

  void sendIce(String targetId, Map<String, dynamic> candidate) =>
      send({'type': 'ice', 'to': targetId, 'from': _deviceId, 'payload': candidate});

  void sendConnect(String hostDeviceId, String pairingCode, String authToken, String fromDeviceId) =>
      send({
        'type': 'connect',
        'from': fromDeviceId,
        'to': hostDeviceId,
        'pairingCode': pairingCode,
        'token': authToken,
      });

  void sendPairingCode(String code) =>
      send({'type': 'pairing', 'pairingCode': code});

  void sendDisconnect(String targetId) =>
      send({'type': 'disconnect', 'to': targetId});

  void _setState(SignalingState s) {
    _state = s;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _setState(SignalingState.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
