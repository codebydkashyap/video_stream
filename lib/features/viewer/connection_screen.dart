// lib/features/viewer/connection_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../core/auth/auth_service.dart';
import '../signaling/signaling_service.dart';
import '../streaming/webrtc_viewer_service.dart';
import 'session_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _deviceIdCtrl = TextEditingController();
  final _pairingCtrl = TextEditingController();
  bool _isConnecting = false;
  String? _error;

  @override
  void dispose() {
    _deviceIdCtrl.dispose();
    _pairingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final hPad = isMobile ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, isMobile ? 20 : 24, hPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isMobile),
                const SizedBox(height: 24),
                _buildConnectCard(isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect to Host',
          style: TextStyle(
            color: Colors.white,
            fontSize: isMobile ? 22 : 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter the host\'s Device ID and pairing code to view their screen',
          style: TextStyle(color: AppTheme.textMuted, fontSize: isMobile ? 13 : 14),
        ),
      ],
    );
  }

  Widget _buildConnectCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon banner
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.accent.withOpacity(0.2), AppTheme.accentAlt.withOpacity(0.2)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
              ),
              child: Icon(Icons.cast_connected, color: AppTheme.accent, size: 36),
            ),
          ),
          const SizedBox(height: 28),

          // Device ID field
          _FieldLabel(label: 'Host Device ID'),
          const SizedBox(height: 8),
          _textField(
            controller: _deviceIdCtrl,
            hint: 'e.g. A1B2C3D4',
            icon: Icons.computer_rounded,
            maxLength: 8,
          ),
          const SizedBox(height: 20),

          // Pairing code field
          _FieldLabel(label: 'Pairing Code'),
          const SizedBox(height: 8),
          _textField(
            controller: _pairingCtrl,
            hint: '6-digit code',
            icon: Icons.key_rounded,
            maxLength: 6,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 28),

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_error!, style: TextStyle(color: AppTheme.danger, fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Connect button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: GestureDetector(
              onTap: _isConnecting ? null : _onConnect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentAlt],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: _isConnecting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                            SizedBox(width: 8),
                            Text('Connect',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                )),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        counterText: '',
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 18),
        filled: true,
        fillColor: AppTheme.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
        ),
      ),
    );
  }

  Future<void> _onConnect() async {
    final deviceId = _deviceIdCtrl.text.trim().toUpperCase();
    final code = _pairingCtrl.text.trim();

    if (deviceId.length < 4) {
      setState(() => _error = 'Please enter a valid Device ID.');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Pairing code must be 6 digits.');
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      await auth.initialize();

      final signaling = context.read<SignalingService>();
      if (signaling.state != SignalingState.connected) {
        await signaling.connect(
          deviceId: auth.deviceId ?? '',
          authToken: auth.authToken ?? 'demo-token',
        );
      }

      final viewer = context.read<WebRTCViewerService>();
      debugPrint('[ConnectionScreen] Calling viewer.initialize() ...');
      await viewer.initialize();
      debugPrint('[ConnectionScreen] viewer.initialize() completed.');
      
      debugPrint('[ConnectionScreen] Calling viewer.connectToHost() ...');
      await viewer.connectToHost(
        signalingService: signaling,
        hostDeviceId: deviceId,
        viewerDeviceId: auth.deviceId ?? '',
        pairingCode: code,
        authToken: auth.authToken ?? 'demo-token',
      );
      debugPrint('[ConnectionScreen] viewer.connectToHost() completed.');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SessionScreen(hostDeviceId: deviceId)),
        );
      }
    } catch (e) {
      debugPrint('[ConnectionScreen] Exception during _onConnect: $e');
      setState(() => _error = 'Connection failed: $e');
    } finally {
      setState(() => _isConnecting = false);
    }
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
