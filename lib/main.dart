// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/auth/auth_service.dart';
import 'core/config/app_config.dart';
import 'features/signaling/signaling_service.dart';
import 'core/webrtc/webrtc_repository.dart';
import 'features/streaming/webrtc_host_service.dart';
import 'features/streaming/webrtc_viewer_service.dart';

void main() async {
  debugPrint('[App] Starting main() ...');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[App] Flutter binding initialized.');
  final config = AppConfig.instance;
  await config.load();
  final webrtcRepo = WebRTCRepository();
  debugPrint('[App] AppConfig loaded. Signaling URL: ${config.signalingUrl}');
  debugPrint('[App] Launching DesktopSharingApp UI ...');
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: webrtcRepo),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SignalingService(config.signalingUrl)),
        ChangeNotifierProvider(create: (context) => WebRTCHostService(context.read<WebRTCRepository>())),
        ChangeNotifierProvider(create: (context) => WebRTCViewerService(context.read<WebRTCRepository>())),
      ],
      child: const DesktopSharingApp(),
    ),
  );
}
