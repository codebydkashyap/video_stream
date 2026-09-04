// lib/features/viewer/connection_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../core/auth/auth_service.dart';
import '../signaling/signaling_service.dart';
import '../streaming/webrtc_viewer_service.dart';
import 'session_screen.dart';

class ConnectionScreen extends StatefulWidget {
  final String? prefilledDeviceId;
  final String? prefilledCode;

  const ConnectionScreen({
    super.key,
    this.prefilledDeviceId,
    this.prefilledCode,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with TickerProviderStateMixin {
  final _deviceIdCtrl = TextEditingController();
  final _pairingCtrl = TextEditingController();
  final _deviceFocus = FocusNode();
  final _pairingFocus = FocusNode();

  bool _isConnecting = false;
  String? _error;
  Timer? _autoConnectTimer;
  bool _autoConnecting = false;
  int _countdown = 3;

  late final AnimationController _radarCtrl;

  @override
  void initState() {
    super.initState();

    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    final deviceId = widget.prefilledDeviceId;
    final code = widget.prefilledCode;

    if (deviceId != null && deviceId.isNotEmpty) {
      _deviceIdCtrl.text = deviceId.toUpperCase();
    }
    if (code != null && code.isNotEmpty) {
      _pairingCtrl.text = code;
    }

    if (deviceId != null &&
        deviceId.isNotEmpty &&
        code != null &&
        code.isNotEmpty) {
      _startAutoConnect();
    }
  }

  void _startAutoConnect() {
    setState(() {
      _autoConnecting = true;
      _countdown = 3;
    });
    _autoConnectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        setState(() => _autoConnecting = false);
        _onConnect();
      }
    });
  }

  void _cancelAutoConnect() {
    _autoConnectTimer?.cancel();
    setState(() => _autoConnecting = false);
  }

  @override
  void dispose() {
    _autoConnectTimer?.cancel();
    _deviceIdCtrl.dispose();
    _pairingCtrl.dispose();
    _deviceFocus.dispose();
    _pairingFocus.dispose();
    _radarCtrl.dispose();
    super.dispose();
  }

  Future<void> _onConnect() async {
    final deviceId = _deviceIdCtrl.text.trim().toUpperCase();
    final code = _pairingCtrl.text.trim();

    if (deviceId.isEmpty || code.isEmpty) {
      setState(() => _error = 'Please enter both Device ID and Pairing Code.');
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
      await signaling.connect(
        deviceId: auth.deviceId ?? '',
        authToken: auth.authToken ?? 'demo-token',
      );

      final viewer = context.read<WebRTCViewerService>();
      await viewer.connectToHost(
        signalingService: signaling,
        hostDeviceId: deviceId,
        viewerDeviceId: auth.deviceId ?? '',
        pairingCode: code,
        authToken: auth.authToken ?? 'demo-token',
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionScreen(hostDeviceId: deviceId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection failed: ${e.toString()}';
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;
    final hPad = isMobile ? 24.0 : 40.0;

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by AppShell
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, 40, hPad, 100),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildRadarIcon(),
                            const SizedBox(height: 48),
                            _buildTitle(),
                            const SizedBox(height: 40),
                            
                            if (_autoConnecting) ...[
                              _buildAutoConnectBanner(),
                              const SizedBox(height: 24),
                            ],
                            
                            _buildTerminalForm(),
                            
                            if (_error != null) ...[
                              const SizedBox(height: 24),
                              _buildError(),
                            ],
                            
                            const SizedBox(height: 48),
                            _buildConnectButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 1. Animated Radar Icon ──────────────────────────────────────────────────

  Widget _buildRadarIcon() {
    return SizedBox(
      height: 200,
      child: AnimatedBuilder(
        animation: _radarCtrl,
        builder: (context, child) {
          return CustomPaint(
            painter: _SonarPainter(
              progress: _radarCtrl.value,
              color: AppTheme.electricBlue,
            ),
            child: Center(
              child: Icon(
                Icons.desktop_windows_outlined,
                size: 64,
                color: AppTheme.electricBlue.withValues(alpha: 0.8),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 2. Title ────────────────────────────────────────────────────────────────

  Widget _buildTitle() {
    return ShaderMask(
      shaderCallback: (bounds) => AppTheme.connectGradient.createShader(bounds),
      child: const Text(
        'Join Session',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
        ),
      ),
    );
  }

  // ── 3. Terminal Form ────────────────────────────────────────────────────────

  Widget _buildTerminalForm() {
    return Column(
      children: [
        _TerminalInput(
          controller: _deviceIdCtrl,
          focusNode: _deviceFocus,
          hint: 'DEVICE_ID',
          isMonospace: true,
          maxLength: 8,
          onSubmitted: (_) => _pairingFocus.requestFocus(),
        ),
        const SizedBox(height: 16),
        _TerminalInput(
          controller: _pairingCtrl,
          focusNode: _pairingFocus,
          hint: 'PAIRING_CODE',
          isMonospace: true,
          isNumber: true,
          maxLength: 6,
          onSubmitted: (_) => _onConnect(),
        ),
      ],
    );
  }

  // ── 4. Connect Button ───────────────────────────────────────────────────────

  Widget _buildConnectButton() {
    return GestureDetector(
      onTap: _isConnecting ? null : _onConnect,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: AppTheme.connectGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.violet.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _isConnecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : const Text(
                'CONNECT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
      ),
    );
  }

  Widget _buildAutoConnectBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlass.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.electricBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppTheme.electricBlue,
              strokeWidth: 2,
              value: _countdown / 3.0,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Connecting via invite in $_countdown...',
              style: const TextStyle(
                color: AppTheme.electricBlue,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: _cancelAutoConnect,
            child: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
      ),
      child: Text(
        _error!,
        style: const TextStyle(color: AppTheme.danger, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SonarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _SonarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    
    for (int i = 0; i < 3; i++) {
      double ringProgress = (progress + (i * 0.33)) % 1.0;
      
      final paint = Paint()
        ..color = color.withValues(alpha: (1.0 - ringProgress) * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        
      canvas.drawCircle(center, maxRadius * ringProgress, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SonarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _TerminalInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool isMonospace;
  final bool isNumber;
  final int maxLength;
  final ValueChanged<String>? onSubmitted;

  const _TerminalInput({
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.isMonospace = false,
    this.isNumber = false,
    required this.maxLength,
    this.onSubmitted,
  });

  @override
  State<_TerminalInput> createState() => _TerminalInputState();
}

class _TerminalInputState extends State<_TerminalInput> with SingleTickerProviderStateMixin {
  late AnimationController _cursorCtrl;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    widget.focusNode.addListener(() {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _cursorCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlass.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isFocused ? AppTheme.electricBlue : Colors.white.withValues(alpha: 0.1),
          width: _isFocused ? 2 : 1,
        ),
        boxShadow: _isFocused
            ? [BoxShadow(color: AppTheme.electricBlue.withValues(alpha: 0.2), blurRadius: 16)]
            : [],
      ),
      child: Row(
        children: [
          Text(
            '>',
            style: TextStyle(
              color: _isFocused ? AppTheme.neonGreen : AppTheme.textMuted,
              fontSize: 20,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              textCapitalization: TextCapitalization.characters,
              keyboardType: widget.isNumber ? TextInputType.number : TextInputType.text,
              maxLength: widget.maxLength,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                letterSpacing: 4,
                fontFamily: widget.isMonospace ? 'monospace' : null,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: AppTheme.textMuted.withValues(alpha: 0.5),
                  letterSpacing: 2,
                ),
                border: InputBorder.none,
                counterText: '',
                isDense: true,
              ),
              onSubmitted: widget.onSubmitted,
              cursorColor: Colors.transparent, // Hide default cursor
            ),
          ),
          if (_isFocused)
            AnimatedBuilder(
              animation: _cursorCtrl,
              builder: (context, child) {
                return Container(
                  width: 10,
                  height: 24,
                  color: AppTheme.neonGreen.withValues(alpha: _cursorCtrl.value),
                );
              },
            ),
        ],
      ),
    );
  }
}
