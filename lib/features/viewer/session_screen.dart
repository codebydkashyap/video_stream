import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../app.dart';
import '../../core/ui/full_screen_video_view.dart';
import '../streaming/webrtc_viewer_service.dart';

class SessionScreen extends StatefulWidget {
  final String hostDeviceId;
  const SessionScreen({super.key, required this.hostDeviceId});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool _controlsVisible = true;
  bool _fullscreen = false;
  RTCVideoViewObjectFit _objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[SessionScreen] initState called. hostDeviceId: ${widget.hostDeviceId}');
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

  void _toggleFit() {
    setState(() {
      _objectFit = _objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
          ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
          : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain;
    });
    
    // Show a brief snackbar/hint about the change
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Video Fit: ${_objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitContain ? "Contain" : "Cover"}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewer = context.watch<WebRTCViewerService>();
    debugPrint(
        '[SessionScreen] build() called. state: ${viewer.state}, isWatching: ${viewer.isWatching}');

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // ── Main Screen Video ──
            Positioned.fill(
              child: viewer.isWatching
                  ? Container(
                      color: Colors.blue
                          .withValues(alpha: 0.2), // Confirmation background
                      child: RTCVideoView(
                        viewer.screenRenderer,
                        objectFit: _objectFit,
                        mirror: false,
                      ),
                    )
                  : _buildLoadingState(viewer.state),
            ),

            // ── Host Camera (PiP 1) ──
            if (viewer.isWatching && viewer.cameraStream != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 80,
                right: 20,
                child: _PiPView(
                  renderer: viewer.cameraRenderer,
                  label: 'HOST CAMERA',
                ),
              ),

            // ── Viewer Local Camera (PiP 2) ──
            Positioned(
              bottom: 140, // More space for the bottom control bar
              left: 20,    // Move to left side to avoid stacking with host camera
              child: _PiPView(
                renderer: viewer.localRenderer,
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
                child: _buildTopBar(viewer),
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
                  child: _buildBottomBar(viewer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ViewerStreamState state) {
    if (state == ViewerStreamState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.signal_wifi_off_rounded,
                color: AppTheme.danger, size: 56),
            const SizedBox(height: 16),
            const Text('Connection failed',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Go back', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      );
    }
    
    if (state == ViewerStreamState.disconnected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded,
                color: AppTheme.textMuted, size: 56),
            const SizedBox(height: 16),
            const Text('Meeting has ended',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),
            _ControlBtn(
              icon: Icons.arrow_back_rounded,
              label: 'Go Back',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }

    if (state == ViewerStreamState.idle) {
      return const Center(
        child: Text('Initializing session…', style: TextStyle(color: Colors.white38)),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
                color: AppTheme.accent, strokeWidth: 2.5),
          ),
          const SizedBox(height: 20),
          Text(
            state == ViewerStreamState.connecting
                ? 'Connecting to host…'
                : 'Waiting for stream…',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(WebRTCViewerService viewer) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 32),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () async {
              await viewer.disconnect();
              if (mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Remote Desktop',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              Text(
                'Host: ${widget.hostDeviceId}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          if (viewer.isWatching)
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
                  Text('LIVE',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(WebRTCViewerService viewer) {
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
              icon: viewer.isMicActive ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: 'Mic',
              color: viewer.isMicActive ? AppTheme.success : AppTheme.textMuted,
              onTap: () => viewer.toggleMic(),
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: viewer.isCamActive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: 'Cam',
              color: viewer.isCamActive ? AppTheme.success : AppTheme.textMuted,
              onTap: () => viewer.toggleCamera(),
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: viewer.isScreenSharing ? Icons.screen_share_rounded : Icons.stop_screen_share_rounded,
              label: viewer.isScreenSharing ? 'Stop Screen' : 'Share Screen',
              color: viewer.isScreenSharing ? AppTheme.accent : AppTheme.textMuted,
              onTap: () async {
                if (viewer.isScreenSharing) {
                  await viewer.stopScreenShare();
                } else {
                  await viewer.startScreenShare();
                }
              },
            ),
            const SizedBox(width: 12),
            _ControlBtn(
              icon: Icons.screen_rotation_outlined,
              label: 'Fit',
              color: _objectFit == RTCVideoViewObjectFit.RTCVideoViewObjectFitCover ? AppTheme.accent : null,
              onTap: _toggleFit,
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
                await viewer.disconnect();
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
            // Tap indicator hint
            Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.fullscreen_rounded, color: Colors.white38, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

