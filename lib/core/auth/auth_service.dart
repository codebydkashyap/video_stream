// lib/core/auth/auth_service.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthService extends ChangeNotifier {
  static const _deviceIdKey = 'device_id';
  static const _authTokenKey = 'auth_token';

  String? _deviceId;
  String? _authToken;
  String? _pairingCode;

  String? get deviceId => _deviceId;
  String? get authToken => _authToken;
  String? get pairingCode => _pairingCode;

  /// Load or generate a persistent device ID
  Future<void> initialize() async {
    debugPrint('[AuthService] initialize() called.');
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4().substring(0, 8).toUpperCase();
      await prefs.setString(_deviceIdKey, _deviceId!);
      debugPrint('[AuthService] Generated and saved new device ID: $_deviceId');
    } else {
      debugPrint('[AuthService] Loaded existing device ID: $_deviceId');
    }
    _authToken = prefs.getString(_authTokenKey);
    debugPrint('[AuthService] Initial Auth Token status: ${_authToken != null ? "Present" : "Missing"}');
    notifyListeners();
  }

  /// Generate a short-lived 6-digit pairing code for a new session
  String generatePairingCode() {
    final rand = Random.secure();
    _pairingCode = List.generate(6, (_) => rand.nextInt(10)).join();
    notifyListeners();
    return _pairingCode!;
  }

  /// Store the token received from the signaling server after registration
  Future<void> saveAuthToken(String token) async {
    debugPrint('[AuthService] Saving new Auth Token to shared preferences.');
    final prefs = await SharedPreferences.getInstance();
    _authToken = token;
    await prefs.setString(_authTokenKey, token);
    notifyListeners();
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = null;
    _pairingCode = null;
    await prefs.remove(_authTokenKey);
    notifyListeners();
  }
}
