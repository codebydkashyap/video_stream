// lib/features/host/host_dashboard_screen.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../app.dart';
import '../../core/auth/auth_service.dart';
import '../../core/config/app_config.dart';
import '../signaling/signaling_service.dart';
import '../streaming/webrtc_host_service.dart';
import 'host_session_screen.dart';

class HostDashboardScreen extends StatefulWidget {
  const HostDashboardScreen({super.key});

  @override
  State<HostDashboardScreen> createState() => _HostDashboardScreenState();
}

class _HostDashboardScreenState extends State<HostDashboardScreen>
    with TickerProviderStateMixin {
  bool _initialized = false;
  bool _isConnecting = false;
  
  late final AnimationController _radarCtrl;
  late final AnimationController _sweepCtrl;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    
    _sweepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _init();
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _sweepCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final auth = context.read<AuthService>();
    await auth.initialize();
    auth.generatePairingCode();

    final host = context.read<WebRTCHostService>();
    await host.initialize();

    setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.electricBlue),
      );
    }

    final auth = context.watch<AuthService>();
    final signaling = context.watch<SignalingService>();
    final host = context.watch<WebRTCHostService>();

    if (host.isStreaming && mounted) {
      final currentRoute = ModalRoute.of(context);
      if (currentRoute?.isCurrent ?? false) {
        Future.microtask(() {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HostSessionScreen(),
                settings: const RouteSettings(name: '/host/session'),
              ),
            );
          }
        });
      }
    }

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
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildRadarStatus(signaling),
                            const SizedBox(height: 40),
                            _buildDeviceID(auth),
                            const SizedBox(height: 40),
                            _buildPairingCode(auth, signaling),
                            const SizedBox(height: 24),
                            _buildShareRow(auth),
                            const SizedBox(height: 48),
                            _buildActionButtons(host, signaling, auth),
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

  // ── 1. Animated Radar Status ────────────────────────────────────────────────

  Widget _buildRadarStatus(SignalingService signaling) {
    final isOnline = signaling.state == SignalingState.connected;
    final color = isOnline ? AppTheme.neonGreen : AppTheme.electricBlue;
    
    return Column(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: AnimatedBuilder(
            animation: _radarCtrl,
            builder: (context, child) {
              return CustomPaint(
                painter: _RadarPainter(
                  progress: _radarCtrl.value,
                  color: color,
                ),
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.8),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isOnline ? 'ONLINE' : 'READY',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  // ── 2. Massive Device ID ────────────────────────────────────────────────────

  Widget _buildDeviceID(AuthService auth) {
    final id = auth.deviceId ?? '--------';
    final formattedId = id.length > 4 ? '${id.substring(0, 4)} • ${id.substring(4)}' : id;
    
    return Column(
      children: [
        const Text(
          'DEVICE ID',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
          child: Text(
            formattedId,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, // Required for ShaderMask
              fontSize: 56,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ── 3. Holographic Pairing Code ─────────────────────────────────────────────

  Widget _buildPairingCode(AuthService auth, SignalingService signaling) {
    final hasCode = auth.pairingCode != null;
    if (!hasCode) return const SizedBox();
    
    final code = auth.pairingCode!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PAIRING CODE',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            GestureDetector(
              onTap: () {
                final newCode = auth.generatePairingCode();
                if (signaling.state == SignalingState.connected) {
                  signaling.sendPairingCode(newCode);
                }
              },
              child: const Icon(Icons.refresh_rounded, color: AppTheme.textMuted, size: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The 6 digit blocks
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return _DigitBlock(digit: code[i], sweepCtrl: _sweepCtrl, delayOffset: i * 0.15);
          }),
        ),
        const SizedBox(height: 16),
        // The scanning line below
        AnimatedBuilder(
          animation: _sweepCtrl,
          builder: (context, child) {
            return Container(
              height: 2,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.3,
                alignment: FractionalOffset(_sweepCtrl.value * 2.0 - 0.5, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.electricBlue,
                    boxShadow: [
                      BoxShadow(color: AppTheme.electricBlue.withValues(alpha: 0.8), blurRadius: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── 4. Shimmering Share Link ────────────────────────────────────────────────

  Widget _buildShareRow(AuthService auth) {
    final deviceId = auth.deviceId ?? '';
    final code = auth.pairingCode ?? '';
    final link = AppConfig.buildJoinLink(deviceId, code);
    
    return HoloCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('Share link: ', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Expanded(
            child: Text(
              link,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _shareLink(context, deviceId, code),
            child: const Icon(Icons.share_rounded, color: AppTheme.electricBlue, size: 18),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
               Clipboard.setData(ClipboardData(text: link));
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Link copied!'), backgroundColor: AppTheme.surfaceGlass),
               );
            },
            child: const Icon(Icons.copy_rounded, color: AppTheme.textMuted, size: 18),
          ),
        ],
      ),
    );
  }

  // ── 5. Action Buttons ───────────────────────────────────────────────────────

  Widget _buildActionButtons(WebRTCHostService host, SignalingService signaling, AuthService auth) {
    final isStarting = host.state == HostStreamState.starting;
    
    if (host.state == HostStreamState.idle) {
      return SizedBox(
        width: double.infinity,
        height: 64,
        child: _GlowingButton(
          label: 'START',
          colors: const [AppTheme.neonGreen, Color(0xFF059669)],
          loading: _isConnecting,
          onTap: () async {
            setState(() => _isConnecting = true);
            try {
              if (signaling.state != SignalingState.connected) {
                await signaling.connect(
                  deviceId: auth.deviceId ?? '',
                  authToken: auth.authToken ?? 'demo-token',
                );
              }
              await host.startMeeting(signaling);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to start: $e'),
                    backgroundColor: AppTheme.danger,
                  ),
                );
              }
            } finally {
              if (mounted) {
                setState(() => _isConnecting = false);
              }
            }
          },
        ),
      );
    }
    
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 64,
            child: _GlowingButton(
              label: host.isScreenSharing ? 'STOP SHARE' : 'SHARE SCREEN',
              colors: const [AppTheme.electricBlue, AppTheme.violet],
              loading: isStarting && !host.isScreenSharing,
              onTap: () async {
                try {
                  if (host.isScreenSharing) {
                    await host.stopScreenShare();
                  } else {
                    await host.startScreenShare(signaling);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Screen share error: $e'),
                        backgroundColor: AppTheme.danger,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 64,
            child: _GlowingButton(
              label: 'END',
              colors: const [AppTheme.danger, Color(0xFFB91C1C)],
              onTap: () async => host.stopHosting(),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _shareLink(BuildContext ctx, String deviceId, String code) async {
    final link = AppConfig.buildJoinLink(deviceId, code);
    await Share.share(
      'Join my DK Meet session!\n\nDevice ID: $deviceId\nPairing Code: $code\n\nTap the link to join directly:\n$link',
      subject: 'DK Meet — Invite Link',
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    
    for (int i = 0; i < 3; i++) {
      // Offset progress for each ring
      double ringProgress = (progress + (i * 0.33)) % 1.0;
      
      final paint = Paint()
        ..color = color.withValues(alpha: (1.0 - ringProgress) * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
        
      canvas.drawCircle(center, maxRadius * ringProgress, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _DigitBlock extends StatelessWidget {
  final String digit;
  final AnimationController sweepCtrl;
  final double delayOffset;

  const _DigitBlock({
    required this.digit,
    required this.sweepCtrl,
    required this.delayOffset,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sweepCtrl,
      builder: (context, child) {
        // Calculate a glow pulse based on sweep progress and delay offset
        double t = (sweepCtrl.value - delayOffset) % 1.0;
        if (t < 0) t += 1.0;
        
        // Spike when t is near 0.5
        double intensity = 0.0;
        if (t > 0.4 && t < 0.6) {
          intensity = 1.0 - ((t - 0.5).abs() * 10).clamp(0.0, 1.0);
        }

        return Container(
          width: 54,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.surfaceGlass.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Color.lerp(
                Colors.white.withValues(alpha: 0.1), 
                AppTheme.violet, 
                intensity
              )!,
              width: 1.5,
            ),
            boxShadow: [
              if (intensity > 0)
                BoxShadow(
                  color: AppTheme.violet.withValues(alpha: intensity * 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        );
      },
    );
  }
}

class _GlowingButton extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool loading;

  const _GlowingButton({
    required this.label,
    required this.colors,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
      ),
    );
  }
}
