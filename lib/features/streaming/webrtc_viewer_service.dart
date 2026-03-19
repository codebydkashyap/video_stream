// lib/features/streaming/webrtc_viewer_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../signaling/signaling_service.dart';
import '../../core/webrtc/webrtc_repository.dart';

enum ViewerStreamState { idle, connecting, watching, error, disconnected }

class WebRTCViewerService extends ChangeNotifier {
  final WebRTCRepository _webrtcRepo;
  RTCPeerConnection? _pc;
  SignalingService? _signalingService;
  String? _hostDeviceId;
  
  MediaStream? _screenStream;
  MediaStream? _cameraStream;
  MediaStream? _localStream;

  final RTCVideoRenderer screenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer cameraRenderer = RTCVideoRenderer();
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  ViewerStreamState _state = ViewerStreamState.idle;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteIceQueue = [];

  final Map<String, RTCRtpSender> _senders = {};

  WebRTCViewerService(this._webrtcRepo);

  ViewerStreamState get state => _state;
  bool get isWatching => _state == ViewerStreamState.watching;
  MediaStream? get screenStream => _screenStream;
  MediaStream? get cameraStream => _cameraStream;
  bool get isMicActive => _localStream?.getAudioTracks().any((t) => t.enabled) ?? false;
  bool get isCamActive => _localStream?.getVideoTracks().any((t) => t.enabled) ?? false;
  bool get isScreenSharing => _screenStream != null && _screenStream!.getVideoTracks().isNotEmpty;

  Future<void> initialize() async {
    await screenRenderer.initialize();
    await cameraRenderer.initialize();
    await localRenderer.initialize();
  }

  Future<void> connectToHost({
    required SignalingService signalingService,
    required String hostDeviceId,
    required String viewerDeviceId,
    required String pairingCode,
    required String authToken,
    bool shareCamera = false,
    bool useTurn = false, // set internally on TURN retry; not needed by callers
  }) async {
    _setState(ViewerStreamState.connecting);
    _signalingService = signalingService;
    _hostDeviceId = hostDeviceId;

    try {
      _pc = await _webrtcRepo.createPC(useTurn: useTurn);
      _senders.clear();

      if (shareCamera) {
        await toggleCamera(); // This handles adding tracks and negotiation
      }

      _setupSignaling(signalingService, hostDeviceId);

      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          signalingService.sendIce(hostDeviceId, {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      _pc!.onTrack = _handleTrack;

      // ── TURN fallback: watch ICE connection state ─────────────────────────
      // If STUN-only negotiation fails, we automatically retry with TURN relay.
      _pc!.onIceConnectionState = (RTCIceConnectionState state) async {
        debugPrint('[WebRTCViewer] ICE connection state changed: $state');
        
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected || 
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          debugPrint('[WebRTCViewer] WebRTC connection established! Media should start flowing.');
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed &&
            !useTurn) {
          debugPrint(
              '[WebRTCViewer] ICE failed with STUN-only — retrying with TURN relay...');

          // Close the failed PC cleanly
          await _pc?.close();
          _pc = null;
          _senders.clear();
          _remoteDescriptionSet = false;
          _remoteIceQueue.clear();

          // Reconnect using TURN
          await connectToHost(
            signalingService: signalingService,
            hostDeviceId: hostDeviceId,
            viewerDeviceId: viewerDeviceId,
            pairingCode: pairingCode,
            authToken: authToken,
            shareCamera: shareCamera,
            useTurn: true,
          );
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected || 
                   state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
          debugPrint('[WebRTCViewer] Peer connection lost. Cleaning up...');
          await disconnect();
        }
      };

      _pc!.onRemoveTrack = (stream, track) {
        debugPrint('[WebRTCViewer] onRemoveTrack: ${track.kind} id: ${track.id}');
        _clearRendererForTrack(track);
      };

      signalingService.sendConnect(hostDeviceId, pairingCode, authToken, viewerDeviceId);
    } catch (e) {
      debugPrint('[WebRTCViewer] Connection failed: $e');
      _setState(ViewerStreamState.error);
    }
  }

  void _setupSignaling(SignalingService signalingService, String hostDeviceId) {
    signalingService.on('offer', (msg) async {
      final sdp = msg['payload'] as String;
      debugPrint('[WebRTCViewer] RECEIVED OFFER from host. Setting remote description...');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      
      bool isFirstOffer = !_remoteDescriptionSet;
      _remoteDescriptionSet = true;
      for (var cand in _remoteIceQueue) {
        await _pc!.addCandidate(cand);
      }
      _remoteIceQueue.clear();

      final answer = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(answer);
      debugPrint('[WebRTCViewer] SENDING ANSWER to host.');
      signalingService.sendAnswer(hostDeviceId, answer.sdp!);

      // FORCE explicit renegotiation if we already added tracks locally.
      // This bypasses the Unified Plan limitation where answers cannot attach
      // tracks properly if the Host's initial m-line transceivers misalign.
      if (isFirstOffer && _senders.isNotEmpty) {
        debugPrint('[WebRTCViewer] Forcing explicit offer to synchronize local tracks.');
        try {
          final offer = await _pc!.createOffer({});
          await _pc!.setLocalDescription(offer);
          signalingService.sendOffer(hostDeviceId, offer.sdp!);
        } catch (e) {
          debugPrint('[WebRTCViewer] Failed explicit renegotiation: $e');
        }
      }
    });

    signalingService.on('ice', (msg) async {
      debugPrint('[WebRTCViewer] RECEIVED ICE candidate from host.');
      final payload = msg['payload'] as Map<String, dynamic>;
      final candidate = RTCIceCandidate(
        payload['candidate'] as String?,
        payload['sdpMid'] as String?,
        payload['sdpMLineIndex'] as int?,
      );

      if (_remoteDescriptionSet) {
        await _pc!.addCandidate(candidate);
      } else {
        _remoteIceQueue.add(candidate);
      }
    });

    signalingService.on('answer', (msg) async {
      final sdp = msg['payload'] as String;
      debugPrint('[WebRTCViewer] RECEIVED renegotiation ANSWER from host.');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      
      _remoteDescriptionSet = true;
      for (var cand in _remoteIceQueue) {
        await _pc!.addCandidate(cand);
      }
      _remoteIceQueue.clear();
    });

    signalingService.on('disconnect', (msg) async {
      debugPrint('[WebRTCViewer] Received disconnect message from host.');
      await disconnect();
    });
  }

  void _handleTrack(RTCTrackEvent event) async {
    debugPrint('[WebRTCViewer] onTrack: ${event.track.kind} streams: ${event.streams.length} trackId: ${event.track.id} enabled: ${event.track.enabled} muted: ${event.track.muted}');
    
    // Listen for track ending to clear renderer
    event.track.onEnded = () {
      debugPrint('[WebRTCViewer] Track ended naturally: ${event.track.id}');
      _clearRendererForTrack(event.track);
    };

    if (event.track.kind == 'audio') {
      debugPrint('[WebRTCViewer] Audio track received: ${event.track.id}');
      return;
    }

    MediaStream stream;
    if (event.streams.isNotEmpty) {
      stream = event.streams.first;
    } else {
      debugPrint('[WebRTCViewer] Unified Plan fallback: creating local stream for track ${event.track.id}');
      _screenStream ??= await createLocalMediaStream('remote_screen_fallback');
      _screenStream!.addTrack(event.track);
      stream = _screenStream!;
    }

    if (event.track.kind == 'video') {
      // Logic: If we don't have a screen stream yet, or this track belongs to the main stream
      bool isExistingScreenTrack = _screenStream != null && 
          _screenStream!.getVideoTracks().any((t) => t.id == event.track.id);

      if (_screenStream == null || isExistingScreenTrack) {
        debugPrint('[WebRTCViewer] Attaching track ${event.track.id} to SCREEN renderer.');
        _screenStream = stream;
        // Fix: Force renderer update by clearing srcObject first
        screenRenderer.srcObject = null;
        screenRenderer.srcObject = _screenStream;
      } else {
        debugPrint('[WebRTCViewer] Attaching track ${event.track.id} to CAMERA renderer.');
        _cameraStream = stream;
        cameraRenderer.srcObject = null;
        cameraRenderer.srcObject = _cameraStream;
      }
    }
    
    event.track.enabled = true;
    _setState(ViewerStreamState.watching);
  }

  void _clearRendererForTrack(MediaStreamTrack track) {
    if (track.kind != 'video') return;
    
    // Check if this track is currently what's in our screen or camera stream
    if (_screenStream != null && _screenStream!.getVideoTracks().any((t) => t.id == track.id)) {
      debugPrint('[WebRTCViewer] Clearing SCREEN renderer because track ended.');
      screenRenderer.srcObject = null;
      _screenStream = null;
    } else if (_cameraStream != null && _cameraStream!.getVideoTracks().any((t) => t.id == track.id)) {
      debugPrint('[WebRTCViewer] Clearing CAMERA renderer because track ended.');
      cameraRenderer.srcObject = null;
      _cameraStream = null;
    }
    notifyListeners();
  }


  Future<void> startScreenShare() async {
    try {
      _screenStream = await _webrtcRepo.getScreenStream();
      localRenderer.srcObject = _screenStream;
      await _updateTracks();
      notifyListeners();
    } catch (e) {
      debugPrint('[WebRTCViewer] Start screen share error: $e');
    }
  }

  Future<void> stopScreenShare() async {
    if (_screenStream == null) return;

    if (_pc != null) {
      final trackIds = _screenStream!.getTracks().map((t) => t.id).toSet();
      final sendersToRemove = <String>[];
      for (var entry in _senders.entries) {
        if (trackIds.contains(entry.key)) {
          try {
            await _pc!.removeTrack(entry.value);
          } catch (_) {}
          sendersToRemove.add(entry.key);
        }
      }
      for (var id in sendersToRemove) {
        _senders.remove(id);
      }
    }

    if (localRenderer.srcObject == _screenStream) {
      localRenderer.srcObject = _localStream;
    }

    await _screenStream!.dispose();
    _screenStream = null;
    await _webrtcRepo.stopForegroundService();

    await _updateTracks();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    try {
      if (_localStream == null) {
        _localStream = await _webrtcRepo.getUserMedia(audio: true, video: true);
        localRenderer.srcObject = _localStream;
      } else {
        final videoTracks = _localStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          videoTracks.first.enabled = !videoTracks.first.enabled;
        } else {
          // Add video to existing stream
          final camStream = await _webrtcRepo.getUserMedia(audio: false, video: true);
          _localStream!.addTrack(camStream.getVideoTracks().first);
          localRenderer.srcObject = _localStream;
        }
      }
      await _updateTracks();
      
      // If everything stopped, stop the foreground service
      if (!isCamActive && !isMicActive && !isScreenSharing) {
        await _webrtcRepo.stopForegroundService();
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('[WebRTCViewer] Toggle camera error: $e');
    }
  }

  Future<void> toggleMic() async {
    try {
      if (_localStream == null) {
        _localStream = await _webrtcRepo.getUserMedia(audio: true, video: false);
        localRenderer.srcObject = _localStream;
      } else {
        final audioTracks = _localStream!.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          audioTracks.first.enabled = !audioTracks.first.enabled;
        } else {
          final micStream = await _webrtcRepo.getUserMedia(audio: true, video: false);
          _localStream!.addTrack(micStream.getAudioTracks().first);
        }
      }
      await _updateTracks();

      // If everything stopped, stop the foreground service
      if (!isCamActive && !isMicActive && !isScreenSharing) {
        await _webrtcRepo.stopForegroundService();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[WebRTCViewer] Toggle mic error: $e');
    }
  }

  Future<void> _updateTracks() async {
    if (_pc == null) return;

    final streams = [_screenStream, _cameraStream, _localStream].whereType<MediaStream>();
    bool addedNewTrack = false;

    for (var stream in streams) {
      for (var track in stream.getTracks()) {
        if (!_senders.containsKey(track.id!)) {
          debugPrint('[WebRTCViewer] Adding local track to PC: ${track.kind} id: ${track.id}');
          final sender = await _pc!.addTrack(track, stream);
          _senders[track.id!] = sender;
          addedNewTrack = true;
        }
      }
    }

    bool hasChanges = addedNewTrack;
    
    // Check if we have senders for tracks that are no longer in our local streams
    // (This handles the 'removed' case)
    final allActiveTrackIds = streams.expand((s) => s.getTracks()).map((t) => t.id).toSet();
    final sendersToRemove = _senders.keys.where((id) => !allActiveTrackIds.contains(id)).toList();
    
    if (sendersToRemove.isNotEmpty) {
      for (var id in sendersToRemove) {
        try {
          await _pc!.removeTrack(_senders[id]!);
          _senders.remove(id);
        } catch (_) {}
      }
      hasChanges = true;
    }

    // Only renegotiate if we actually changed something AND the connection is fully established
    if (hasChanges && _hostDeviceId != null && _signalingService != null && _remoteDescriptionSet) {
      debugPrint('[WebRTCViewer] Triggering renegotiation offer from viewer...');
      try {
        final offer = await _pc!.createOffer({});
        await _pc!.setLocalDescription(offer);
        _signalingService!.sendOffer(_hostDeviceId!, offer.sdp!);
        _remoteDescriptionSet = false;
      } catch (e) {
        debugPrint('[WebRTCViewer] Renegotiation error: $e');
      }
    }
  }

  Future<void> disconnect() async {
    _setState(ViewerStreamState.disconnected);
    
    // Clear renderers first to stop native processing
    screenRenderer.srcObject = null;
    cameraRenderer.srcObject = null;
    localRenderer.srcObject = null;
    
    await _screenStream?.dispose();
    await _cameraStream?.dispose();
    await _localStream?.dispose();
    await _pc?.close();
    
    await _webrtcRepo.stopForegroundService();
    
    _pc = null;
    _screenStream = null;
    _cameraStream = null;
    _localStream = null;
    _senders.clear();
    _hostDeviceId = null;
  }

  void _setState(ViewerStreamState s) {
    debugPrint('[WebRTCViewer] State: $_state -> $s');
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    // Synchronously clear srcObject to avoid race conditions during shutdown
    screenRenderer.srcObject = null;
    cameraRenderer.srcObject = null;
    localRenderer.srcObject = null;
    
    // Attempt cleanup (can't await in dispose)
    _screenStream?.dispose();
    _cameraStream?.dispose();
    _localStream?.dispose();
    _pc?.close();
    
    screenRenderer.dispose();
    cameraRenderer.dispose();
    localRenderer.dispose();
    super.dispose();
  }
}
