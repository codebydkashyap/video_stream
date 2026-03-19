// lib/features/host/host_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

class _HostDashboardScreenState extends State<HostDashboardScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[HostDashboardScreen] initState called.');
    _init();
  }

  Future<void> _init() async {
    debugPrint('[HostDashboardScreen] _init() started.');
    final auth = context.read<AuthService>();
    await auth.initialize();
    debugPrint('[HostDashboardScreen] auth.initialize() completed.');

    final host = context.read<WebRTCHostService>();
    await host.initialize();
    debugPrint('[HostDashboardScreen] host.initialize() completed.');

    setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final auth = context.watch<AuthService>();
    final signaling = context.watch<SignalingService>();
    final host = context.watch<WebRTCHostService>();

    // Navigate to Session Screen if streaming starts
    if (host.isStreaming && mounted) {
      final currentRoute = ModalRoute.of(context);
      final isTop = currentRoute?.isCurrent ?? false;

      if (isTop) {
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

    // Responsive padding based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final hPad = isMobile ? 16.0 : 24.0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hPad, isMobile ? 20 : 24, hPad, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isMobile),
            const SizedBox(height: 24),
            _buildDeviceCard(auth, isMobile),
            const SizedBox(height: 16),
            _buildPairingCard(auth, signaling, isMobile),
            const SizedBox(height: 16),
            _buildStatusCard(host, signaling),
            const SizedBox(height: 24),
            _buildStreamControls(host, signaling, auth),
            const SizedBox(height: 16),
            if (host.isStreaming) _buildStreamStats(host, isMobile),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Host Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 22 : 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: AppTheme.textMuted, size: 22),
              tooltip: 'Signaling Settings',
              onPressed: () => _showSignalingConfigDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Share your screen with remote viewers',
          style: TextStyle(color: AppTheme.textMuted, fontSize: isMobile ? 13 : 14),
        ),
      ],
    );
  }

  void _showSignalingConfigDialog(BuildContext context) {
    final config = AppConfig.instance;
    final controller = TextEditingController(text: config.signalingUrl);
    final signaling = context.read<SignalingService>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Signaling Configuration', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WebSocket URL',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.bg,
                hintText: 'wss://your-app.onrender.com/',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Changing this will disconnect your current session.',
              style: TextStyle(color: AppTheme.warning, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                await config.setSignalingUrl(newUrl);
                if (signaling.state == SignalingState.connected) {
                  await signaling.disconnect();
                }
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signaling URL updated.')),
                );
                setState(() {}); // Refresh UI warning status
              }
            },
            child: const Text('Save & Apply', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(AuthService auth, bool isMobile) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.computer, color: AppTheme.accent, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Device ID',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                // FittedBox prevents the monospace Device ID from overflowing
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      auth.deviceId ?? '--------',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: isMobile ? 20 : 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: isMobile ? 3 : 4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.copy_rounded, color: AppTheme.accent, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: auth.deviceId ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device ID copied!')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Share this ID with viewers who want to connect.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(WebRTCHostService host, SignalingService signaling) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering, color: AppTheme.accent, size: 16),
              const SizedBox(width: 8),
              const Text('Connection Status',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          _StatusRow('Signaling', _signalingLabel(signaling.state),
              _signalingColor(signaling.state)),
          const SizedBox(height: 8),
          _StatusRow('Stream', _streamLabel(host.state), _streamColor(host.state)),
          const SizedBox(height: 8),
          _StatusRow('Viewers', '${host.viewerCount} connected', AppTheme.textMuted),
        ],
      ),
    );
  }

  Widget _buildPairingCard(
      AuthService auth, SignalingService signaling, bool isMobile) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, color: AppTheme.accent, size: 16),
              const SizedBox(width: 8),
              const Text('Pairing Code',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.refresh_rounded, color: AppTheme.accent, size: 15),
                label: Text('Generate',
                    style: TextStyle(color: AppTheme.accent, fontSize: 12)),
                onPressed: () {
                  final code = auth.generatePairingCode();
                  if (signaling.state == SignalingState.connected) {
                    signaling.sendPairingCode(code);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (auth.pairingCode != null)
            // Use LayoutBuilder to size digits proportionally to available width
            LayoutBuilder(builder: (context, constraints) {
              // 6 digits + 5 gaps (6px each) + card padding already accounted
              final totalGaps = 5 * 6.0;
              final digitWidth = (constraints.maxWidth - totalGaps) / 6;
              final digitHeight = (digitWidth * 1.3).clamp(44.0, 64.0);
              final fontSize = (digitWidth * 0.5).clamp(14.0, 24.0);

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  return Container(
                    width: digitWidth,
                    height: digitHeight,
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      auth.pairingCode![i],
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                }),
              );
            })
          else
            Text(
              'Tap "Generate" to create a pairing code for a new session.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _buildStreamControls(
    WebRTCHostService host,
    SignalingService signaling,
    AuthService auth,
  ) {
    if (host.state == HostStreamState.idle) {
      return _GradientButton(
        label: 'Start Meet',
        icon: Icons.play_arrow_rounded,
        color: AppTheme.success,
        onPressed: () async {
          if (signaling.state != SignalingState.connected) {
            await signaling.connect(
              deviceId: auth.deviceId ?? '',
              authToken: auth.authToken ?? 'demo-token',
            );
          }
          await host.startMeeting(signaling);
        },
      );
    }

    final isStarting = host.state == HostStreamState.starting;
    final isScreenOn = host.isScreenSharing;
    final isCameraOn = host.isCameraSharing;
    final isMicOn = host.isMicActive;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _GradientButton(
                label: isScreenOn ? 'Stop Screen' : 'Share Screen',
                icon: isScreenOn
                    ? Icons.stop_circle_rounded
                    : Icons.screenshot_monitor,
                color: isScreenOn ? AppTheme.danger : AppTheme.accent,
                loading: isStarting && !isScreenOn && !isCameraOn,
                onPressed: () async {
                  if (isScreenOn) {
                    await host.stopScreenShare();
                  } else {
                    await host.startScreenShare(signaling);
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GradientButton(
                label: isCameraOn ? 'Stop Cam' : 'Start Cam',
                icon: isCameraOn
                    ? Icons.videocam_off_rounded
                    : Icons.videocam_rounded,
                color: isCameraOn ? AppTheme.danger : AppTheme.success,
                onPressed: () async => await host.toggleCamera(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _GradientButton(
                label: isMicOn ? 'Mute' : 'Unmute',
                icon: isMicOn ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: isMicOn ? AppTheme.danger : AppTheme.success,
                onPressed: () async => await host.toggleMic(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _GradientButton(
                label: 'End Meet',
                icon: Icons.exit_to_app_rounded,
                color: Colors.grey[800]!,
                onPressed: () async => await host.stopHosting(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStreamStats(WebRTCHostService host, bool isMobile) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: AppTheme.success, size: 16),
              const SizedBox(width: 8),
              const Text('Stream Stats',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              _LiveBadge(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatTile(label: 'FPS', value: '30', isMobile: isMobile),
              _StatTile(label: 'Bitrate', value: '3.2M', isMobile: isMobile),
              _StatTile(label: 'Latency', value: '~80ms', isMobile: isMobile),
              _StatTile(
                  label: 'Viewers',
                  value: '${host.viewerCount}',
                  isMobile: isMobile),
            ],
          ),
        ],
      ),
    );
  }

  String _signalingLabel(SignalingState s) => switch (s) {
        SignalingState.connected => 'Connected',
        SignalingState.connecting => 'Connecting…',
        SignalingState.error => 'Error',
        _ => 'Disconnected',
      };
  Color _signalingColor(SignalingState s) => switch (s) {
        SignalingState.connected => AppTheme.success,
        SignalingState.connecting => AppTheme.warning,
        SignalingState.error => AppTheme.danger,
        _ => AppTheme.textMuted,
      };
  String _streamLabel(HostStreamState s) => switch (s) {
        HostStreamState.streaming => 'Streaming',
        HostStreamState.starting => 'Starting…',
        HostStreamState.error => 'Error',
        _ => 'Idle',
      };
  Color _streamColor(HostStreamState s) => switch (s) {
        HostStreamState.streaming => AppTheme.success,
        HostStreamState.starting => AppTheme.warning,
        HostStreamState.error => AppTheme.danger,
        _ => AppTheme.textMuted,
      };
}

// ─── Reusable Widgets ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatusRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text('LIVE',
              style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.color,
    this.loading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.9),
              color.withValues(alpha: 0.6)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isMobile;
  const _StatTile(
      {required this.label, required this.value, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 15 : 18,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
