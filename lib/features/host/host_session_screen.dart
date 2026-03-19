// lib/features/host/host_session_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../core/auth/auth_service.dart';
import '../../core/ui/full_screen_video_view.dart';
import '../streaming/webrtc_host_service.dart';
import '../signaling/signaling_service.dart';

class HostSessionScreen extends StatefulWidget {
  const HostSessionScreen({super.key});

  @override
  State<HostSessionScreen> createState() => _HostSessionScreenState();
}

class _HostSessionScreenState extends State<HostSessionScreen> {
  bool _controlsVisible = true;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[HostSessionScreen] initState called.');
    // Auto-hide controls after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() =>
      setState(() => _controlsVisible = !_controlsVisible);

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = context.watch<WebRTCHostService>();
    final signaling = context.watch<SignalingService>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // ── Main View (Local Screen or Camera) ──
            Positioned.fill(
              child: host.isStreaming
                  ? Container(
                      color: AppTheme.accent.withValues(alpha: 0.05),
                      child: RTCVideoView(
                        host.localRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        mirror: host.isCameraSharing && !host.isScreenSharing,
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),

            // ── Remote Viewer (PiP) ──
            if (host.isStreaming && host.remoteRenderer.srcObject != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 80,
                right: 20,
                child: _PiPView(
                  renderer: host.remoteRenderer,
                  label: 'VIEWER',
                ),
              ),

            // ── Host Self Camera (PiP - only when screen sharing) ──
            if (host.isStreaming && host.isScreenSharing && host.isCameraSharing)
              Positioned(
                bottom: 140, // More space for bottom control bar
                left: 20,    // Move to left side to avoid stacking if viewer was moved
                child: _PiPView(
                  renderer: host.cameraRenderer,
                  label: 'SELF',
                  mirror: true,
                ),
              ),

            // ── Top controls bar ──
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _buildTopBar(host),
              ),
            ),

            // ── Bottom controls bar ──
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildBottomBar(host, signaling),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(WebRTCHostService host) {
    final auth = context.watch<AuthService>();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 32),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Hosting Session',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  Text(
                    '${host.viewerCount} Viewer(s) connected',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              if (host.isStreaming)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: AppTheme.success, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      const Text('LIVE',
                          style: TextStyle(
                              color: AppTheme.success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // ID and Pairing Code Info
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _InfoChip(
                  label: 'ID',
                  value: auth.deviceId ?? '---',
                  icon: Icons.computer_rounded,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: auth.deviceId ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device ID copied!')),
                    );
                  },
                ),
                if (auth.pairingCode != null) ...[
                  const SizedBox(width: 8),
                  _InfoChip(
                    label: 'CODE',
                    value: auth.pairingCode!,
                    icon: Icons.key_rounded,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: auth.pairingCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pairing Code copied!')),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(WebRTCHostService host, SignalingService signaling) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlBtn(
              icon: host.isMicActive ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: 'Mic',
              color: host.isMicActive ? AppTheme.success : AppTheme.textMuted,
              onTap: () => host.toggleMic(),
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: host.isCameraSharing ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: 'Cam',
              color: host.isCameraSharing ? AppTheme.success : AppTheme.textMuted,
              onTap: () => host.toggleCamera(),
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: host.isScreenSharing ? Icons.screen_share_rounded : Icons.stop_screen_share_rounded,
              label: host.isScreenSharing ? 'Stop Screen' : 'Share Screen',
              color: host.isScreenSharing ? AppTheme.accent : AppTheme.textMuted,
              onTap: () async {
                if (host.isScreenSharing) {
                  await host.stopScreenShare();
                } else {
                  await host.startScreenShare(signaling);
                }
              },
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: _fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              label: _fullscreen ? 'Exit' : 'Full',
              onTap: _toggleFullscreen,
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: Icons.close_rounded,
              label: 'End',
              color: AppTheme.danger,
              onTap: () async {
                await host.stopHosting();
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ControlBtn({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: c, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PiPView extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String label;
  final bool mirror;

  const _PiPView({
    required this.renderer,
    required this.label,
    this.mirror = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (renderer.srcObject != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FullScreenVideoView(
                renderer: renderer,
                label: label,
                mirror: mirror,
              ),
            ),
          );
        }
      },
      child: Container(
        width: 140,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black54, blurRadius: 10, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirror: mirror,
            ),
            if (renderer.srcObject == null)
              Container(
                color: Colors.black,
                child: const Center(
                  child: Icon(Icons.videocam_off_rounded,
                      color: Colors.white24, size: 24),
                ),
              ),
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: const Icon(Icons.fullscreen_rounded, color: Colors.white38, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.accent, size: 14),
            const SizedBox(width: 6),
            Text(
              '$label: ',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.copy_rounded, color: Colors.white24, size: 10),
          ],
        ),
      ),
    );
  }
}
