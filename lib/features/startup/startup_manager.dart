// lib/features/startup/startup_manager.dart
//
// Registers the host agent to start automatically at OS boot.
//
// Platform strategies:
//   Windows → HKCU registry Run key
//   Linux   → systemd user service unit
//   macOS   → LaunchAgent plist in ~/Library/LaunchAgents/

import 'dart:io';
import 'package:flutter/foundation.dart';

class StartupManager {
  static const _appName = 'DesktopShareHost';
  static const _serviceId = 'com.desktopshare.host';

  /// Register the current executable for auto-start.
  static Future<bool> register() async {
    final exe = Platform.resolvedExecutable;
    debugPrint('[StartupManager] Registering: $exe');
    try {
      if (Platform.isWindows) return await _registerWindows(exe);
      if (Platform.isLinux) return await _registerLinux(exe);
      if (Platform.isMacOS) return await _registerMacos(exe);
    } catch (e) {
      debugPrint('[StartupManager] Error: $e');
    }
    return false;
  }

  /// Remove the auto-start registration.
  static Future<bool> unregister() async {
    try {
      if (Platform.isWindows) return await _unregisterWindows();
      if (Platform.isLinux) return await _unregisterLinux();
      if (Platform.isMacOS) return await _unregisterMacos();
    } catch (e) {
      debugPrint('[StartupManager] Unregister error: $e');
    }
    return false;
  }

  // ─── Windows ─────────────────────────────────────────────────────────────

  static Future<bool> _registerWindows(String exe) async {
    final result = await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v', _appName,
      '/t', 'REG_SZ',
      '/d', '"$exe"',
      '/f',
    ]);
    return result.exitCode == 0;
  }

  static Future<bool> _unregisterWindows() async {
    final result = await Process.run('reg', [
      'delete',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v', _appName,
      '/f',
    ]);
    return result.exitCode == 0;
  }

  // ─── Linux ───────────────────────────────────────────────────────────────

  static Future<bool> _registerLinux(String exe) async {
    final home = Platform.environment['HOME'] ?? '';
    final dir = '$home/.config/systemd/user';
    final servicePath = '$dir/$_appName.service';

    await Directory(dir).create(recursive: true);
    await File(servicePath).writeAsString('''
[Unit]
Description=Desktop Share Host Agent
After=graphical-session.target

[Service]
ExecStart=$exe
Restart=on-failure
RestartSec=5s
Environment=DISPLAY=:0

[Install]
WantedBy=default.target
''');

    final enable = await Process.run(
      'systemctl', ['--user', 'enable', '$_appName.service'],
    );
    await Process.run('systemctl', ['--user', 'start', '$_appName.service']);
    return enable.exitCode == 0;
  }

  static Future<bool> _unregisterLinux() async {
    await Process.run('systemctl', ['--user', 'stop', '$_appName.service']);
    final disable = await Process.run(
      'systemctl', ['--user', 'disable', '$_appName.service'],
    );
    final home = Platform.environment['HOME'] ?? '';
    await File('$home/.config/systemd/user/$_appName.service').delete();
    return disable.exitCode == 0;
  }

  // ─── macOS ───────────────────────────────────────────────────────────────

  static Future<bool> _registerMacos(String exe) async {
    final home = Platform.environment['HOME'] ?? '';
    final launchDir = '$home/Library/LaunchAgents';
    final plistPath = '$launchDir/$_serviceId.plist';

    await Directory(launchDir).create(recursive: true);
    await File(plistPath).writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_serviceId</string>
  <key>ProgramArguments</key>
  <array>
    <string>$exe</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$home/Library/Logs/desktop_share_host.log</string>
  <key>StandardErrorPath</key>
  <string>$home/Library/Logs/desktop_share_host_error.log</string>
</dict>
</plist>''');

    final result = await Process.run('launchctl', ['load', plistPath]);
    return result.exitCode == 0;
  }

  static Future<bool> _unregisterMacos() async {
    final home = Platform.environment['HOME'] ?? '';
    final plistPath = '$home/Library/LaunchAgents/$_serviceId.plist';
    await Process.run('launchctl', ['unload', plistPath]);
    await File(plistPath).delete();
    return true;
  }
}
