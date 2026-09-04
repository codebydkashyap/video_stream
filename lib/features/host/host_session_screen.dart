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

class _HostSessionScreenState extends State<HostSessionScreen>
    with SingleTickerProviderStateMixin {
  bool _controlsVisible = true;
  bool _fullscreen = false;
  late final AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _controlsVisible) _hideControls();
    });
  }

  void _hideControls() {
    _fadeCtrl.reverse();
    setState(() => _controlsVisible = false);
  }

  void _showControls() {
    _fadeCtrl.forward();
    setState(() => _controlsVisible = true);
    _scheduleAutoHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

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
    _fadeCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = context.watch<WebRTCHostService>();
    final signaling = context.watch<SignalingService>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Main view ────────────────────────────────────────────────────
            Positioned.fill(
              child: host.isStreaming
                  ? RTCVideoView(
                      host.localRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      mirror: host.isCameraSharing && !host.isScreenSharing,
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: CircularProgressIndicator(
                                  color: AppTheme.cyan.withOpacity(0.2),
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(
                                width: 50,
                                height: 50,
                                child: CircularProgressIndicator(
                                  color: AppTheme.cyan,
                                  strokeWidth: 3,
                                ),
                              ),
                              Icon(Icons.satellite_alt_rounded, color: AppTheme.cyan, size: 24),
                            ],
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'STARTING STREAM...',
                            style: TextStyle(
                              color: AppTheme.cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Initializing WebRTC connection',
                            style: TextStyle(
                              color: AppTheme.textMuted.withOpacity(0.6),
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // ── Touch layer for controls toggle ──────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                child: const SizedBox.expand(),
              ),
            ),

            // ── Viewer PiP ───────────────────────────────────────────────────
            if (host.isStreaming && host.remoteRenderer.srcObject != null)
              _DraggablePiP(
                renderer: host.remoteRenderer,
                label: 'VIEWER',
                initialOffset:
                    Offset(MediaQuery.of(context).size.width - 168, 90),
              ),

            // ── Self camera PiP (when screen sharing) ────────────────────────
            if (host.isStreaming &&
                host.isScreenSharing &&
                host.isCameraSharing)
              _DraggablePiP(
                renderer: host.cameraRenderer,
                label: 'YOU',
                mirror: true,
                initialOffset: const Offset(16, 90),
              ),

            // ── Top bar ──────────────────────────────────────────────────────
            FadeTransition(
              opacity: _fadeCtrl,
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: _buildTopBar(host),
              ),
            ),

            // ── Bottom bar ───────────────────────────────────────────────────
            FadeTransition(
              opacity: _fadeCtrl,
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
    );
  }

  // ── Top Bar ──────────────────────────────────────────────────────────────────

  Widget _buildTopBar(WebRTCHostService host) {
    final auth = context.watch<AuthService>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          16, MediaQuery.of(context).padding.top + 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Live Session',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    Text(
                      '${host.viewerCount} viewer${host.viewerCount == 1 ? '' : 's'} connected',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // LIVE badge
              if (host.isStreaming) _LivePill(),
            ],
          ),
          const SizedBox(height: 12),
          // Info chips
          Row(
            children: [
              _InfoPill(
                  icon: Icons.computer_rounded, label: auth.deviceId ?? '---'),
              const SizedBox(width: 8),
              if (auth.pairingCode != null)
                _InfoPill(icon: Icons.key_rounded, label: auth.pairingCode!),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar ────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(WebRTCHostService host, SignalingService signaling) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xEE000000), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SessionBtn(
            icon: host.isMicActive ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: 'Mic',
            active: host.isMicActive,
            activeColor: AppTheme.success,
            onTap: () => host.toggleMic(),
          ),
          const SizedBox(width: 10),
          _SessionBtn(
            icon: host.isCameraSharing
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            label: 'Camera',
            active: host.isCameraSharing,
            activeColor: AppTheme.success,
            onTap: () => host.toggleCamera(),
          ),
          const SizedBox(width: 10),
          _SessionBtn(
            icon: host.isScreenSharing
                ? Icons.stop_screen_share_rounded
                : Icons.screenshot_monitor_rounded,
            label: host.isScreenSharing ? 'Stop' : 'Share',
            active: host.isScreenSharing,
            activeColor: AppTheme.cyan,
            onTap: () async {
              if (host.isScreenSharing) {
                await host.stopScreenShare();
              } else {
                await host.startScreenShare(signaling);
              }
            },
          ),
          const SizedBox(width: 10),
          _SessionBtn(
            icon: _fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            label: _fullscreen ? 'Exit' : 'Full',
            active: _fullscreen,
            activeColor: AppTheme.electricBlue,
            onTap: _toggleFullscreen,
          ),
          const SizedBox(width: 10),
          // End call — prominent red
          GestureDetector(
            onTap: () async {
              await host.stopHosting();
              if (mounted) Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.danger, Color(0xFFB91C1C)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: AppTheme.danger.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.call_end_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('End',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Live Pill ────────────────────────────────────────────────────────────────

class _LivePill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.danger.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.danger,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppTheme.danger.withValues(alpha: 0.8),
                    blurRadius: 5)
              ],
            ),
          ),
          const SizedBox(width: 5),
          const Text('LIVE',
              style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ─── Info Pill ────────────────────────────────────────────────────────────────

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: label));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Copied!'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.cyan, size: 12),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
            const SizedBox(width: 5),
            const Icon(Icons.copy_rounded, color: Colors.white24, size: 10),
          ],
        ),
      ),
    );
  }
}

// ─── Session Button ───────────────────────────────────────────────────────────

class _SessionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _SessionBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? activeColor : Colors.white38;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: active ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.3)),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: c.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
        ),
      ),
    );
  }
}

// ─── Draggable PiP View ───────────────────────────────────────────────────────

class _DraggablePiP extends StatefulWidget {
  final RTCVideoRenderer renderer;
  final String label;
  final bool mirror;
  final Offset initialOffset;

  const _DraggablePiP({
    required this.renderer,
    required this.label,
    this.mirror = false,
    required this.initialOffset,
  });

  @override
  State<_DraggablePiP> createState() => _DraggablePiPState();
}

class _DraggablePiPState extends State<_DraggablePiP> {
  late Offset _pos;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos += d.delta),
        onTap: () {
          if (widget.renderer.srcObject != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullScreenVideoView(
                  renderer: widget.renderer,
                  label: widget.label,
                  mirror: widget.mirror,
                ),
              ),
            );
          }
        },
        child: Container(
          width: 148,
          height: 106,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.18), width: 1.2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              RTCVideoView(
                widget.renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: widget.mirror,
              ),
              if (widget.renderer.srcObject == null)
                const Center(
                    child: Icon(Icons.videocam_off_rounded,
                        color: Colors.white24, size: 26)),

              // Label badge
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8),
                  ),
                ),
              ),

              // Drag handle
              Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.open_with_rounded,
                    color: Colors.white.withValues(alpha: 0.4), size: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
