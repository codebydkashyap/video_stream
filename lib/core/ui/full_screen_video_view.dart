// lib/core/ui/full_screen_video_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../app.dart';

class FullScreenVideoView extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final String label;
  final bool mirror;

  const FullScreenVideoView({
    super.key,
    required this.renderer,
    required this.label,
    this.mirror = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              mirror: mirror,
            ),
          ),
          
          // Header with label and close button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 16,
                left: 24,
                right: 24,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black87, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),

          // Fallback UI if no stream
          if (renderer.srcObject == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'No Video Stream Available',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
