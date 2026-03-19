// lib/features/streaming/webrtc_host_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../signaling/signaling_service.dart';
import '../../core/webrtc/webrtc_repository.dart';

enum HostStreamState { idle, starting, streaming, error }

class WebRTCHostService extends ChangeNotifier {
  final WebRTCRepository _webrtcRepo;
  RTCPeerConnection? _pc;
  SignalingService? _signalingService;
  String? _activeViewerId;

  MediaStream? _screenStream;
  MediaStream? _cameraStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer cameraRenderer = RTCVideoRenderer();

  int _viewerCount = 0;
  HostStreamState _state = HostStreamState.idle;

  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteIceQueue = [];

  // Track senders for dynamic replacement/removal
  final Map<String, RTCRtpSender> _senders = {};

  WebRTCHostService(this._webrtcRepo);

  HostStreamState get state => _state;
  bool get isStreaming => _state == HostStreamState.streaming;
  bool get isScreenSharing =>
      _screenStream != null && _screenStream!.getVideoTracks().isNotEmpty;
  bool get isCameraSharing => _cameraStream != null;
  bool get isMicActive {
    return _cameraStream?.getAudioTracks().any((t) => t.enabled) ?? false;
  }

  int get viewerCount => _viewerCount;

  Future<void> initialize() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await cameraRenderer.initialize();
  }

  Future<void> startMeeting(SignalingService signalingService) async {
    try {
      _signalingService = signalingService;
      _setState(HostStreamState.starting);

      // Request audio stream to invoke permissions immediately as requested
      _cameraStream = await _webrtcRepo.getUserMedia(audio: true, video: false);
      localRenderer.srcObject = _cameraStream;
      cameraRenderer.srcObject = _cameraStream;

      // Setup signaling handlers
      _setupSignaling(signalingService);

      _setState(HostStreamState.streaming);

      if (_pc != null) {
        await _updateTracks();
      }
    } catch (e) {
      debugPrint('[WebRTCHost] Start meeting error: $e');
      _setState(HostStreamState.error);
    }
  }

  Future<void> startScreenShare(SignalingService signalingService) async {
    try {
      _signalingService = signalingService;
      _screenStream = await _webrtcRepo.getScreenStream();
      localRenderer.srcObject = _screenStream;

      if (_state == HostStreamState.idle) {
        _setState(HostStreamState.streaming);
        _setupSignaling(signalingService);
      } else {
        notifyListeners();
      }

      if (_pc != null) {
        await _updateTracks();
      }
    } catch (e) {
      debugPrint('[WebRTCHost] Screen share error: $e');
      if (_state == HostStreamState.idle ||
          _state == HostStreamState.starting) {
        _setState(HostStreamState.error);
      }
    }
  }

  Future<void> toggleCamera() async {
    try {
      if (_cameraStream == null) {
        _cameraStream =
            await _webrtcRepo.getUserMedia(audio: true, video: true);
        
        // Initial assignment
        if (_screenStream == null) {
          localRenderer.srcObject = _cameraStream;
        }
        cameraRenderer.srcObject = _cameraStream;
      } else {
        final videoTracks = _cameraStream!.getVideoTracks();
        if (videoTracks.isNotEmpty) {
          // Toggle existing video track
          final track = videoTracks.first;
          track.enabled = !track.enabled;
        } else {
          // No video tracks yet (audio only). Safe approach: replace entire stream
          final oldAudioEnabled = _cameraStream!.getAudioTracks().isNotEmpty
              ? _cameraStream!.getAudioTracks().first.enabled
              : true;

          // Remove old tracks from PC and dispose
          if (_pc != null) {
            for (var track in _cameraStream!.getTracks()) {
              if (_senders.containsKey(track.id)) {
                try {
                  await _pc!.removeTrack(_senders[track.id]!);
                  _senders.remove(track.id);
                } catch (_) {}
              }
            }
          }

          await _cameraStream!.dispose();

          // Get brand new AV stream
          _cameraStream =
              await _webrtcRepo.getUserMedia(audio: true, video: true);

          // Restore audio state
          for (var t in _cameraStream!.getAudioTracks()) {
            t.enabled = oldAudioEnabled;
          }
        }

        // Force renderer update to catch the new stream/tracks
        if (_screenStream == null) {
          localRenderer.srcObject = null;
          localRenderer.srcObject = _cameraStream;
        }
        cameraRenderer.srcObject = null;
        cameraRenderer.srcObject = _cameraStream;
      }
      
      await _updateTracks();
      notifyListeners();
    } catch (e) {
      debugPrint('[WebRTCHost] Camera toggle error: $e');
    }
  }

  Future<void> toggleMic() async {
    try {
      if (_cameraStream == null) {
        _cameraStream =
            await _webrtcRepo.getUserMedia(audio: true, video: false);
      }

      final audioTracks = _cameraStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        audioTracks.first.enabled = !audioTracks.first.enabled;
      } else {
        // No audio tracks. Safe approach: replace entire stream
        final oldVideoEnabled = _cameraStream!.getVideoTracks().isNotEmpty
            ? _cameraStream!.getVideoTracks().first.enabled
            : false; // if no video tracks, it was false anyway

        // Remove old tracks from PC
        if (_pc != null) {
          for (var track in _cameraStream!.getTracks()) {
            if (_senders.containsKey(track.id)) {
              try {
                await _pc!.removeTrack(_senders[track.id]!);
                _senders.remove(track.id);
              } catch (_) {}
            }
          }
        }

        await _cameraStream!.dispose();

        // If old stream had video enabled, get AV stream, else get Audio-only
        _cameraStream =
            await _webrtcRepo.getUserMedia(audio: true, video: oldVideoEnabled);

        // Force renderer update if it had video
        if (oldVideoEnabled && _screenStream == null) {
          localRenderer.srcObject = null;
          localRenderer.srcObject = _cameraStream;
        }
        cameraRenderer.srcObject = _cameraStream;
      }
      await _updateTracks();
      notifyListeners();
    } catch (e) {
      debugPrint('[WebRTCHost] Mic toggle error: $e');
    }
  }

  Future<void> _updateTracks() async {
    if (_pc == null) return;

    final streams = [_screenStream, _cameraStream].whereType<MediaStream>();
    bool addedNewTrack = false;

    debugPrint('[WebRTCHost] _updateTracks called. Active streams: ${streams.length}');
    for (var stream in streams) {
      debugPrint('[WebRTCHost] Stream ${stream.id} tracks: ${stream.getTracks().length}');
      for (var track in stream.getTracks()) {
        if (!_senders.containsKey(track.id!)) {
          debugPrint(
              '[WebRTCHost] ATTACHING new track to PC: ${track.kind} id: ${track.id}');
          final sender = await _pc!.addTrack(track, stream);
          _senders[track.id!] = sender;
          addedNewTrack = true;
        } else {
          debugPrint('[WebRTCHost] Track ${track.id} already attached.');
        }
      }
    }

    // Renegotiate ONLY if we added new tracks
    if (addedNewTrack) {
      await _renegotiate();
    }
  }

  Future<void> _renegotiate() async {
    if (_pc == null || _activeViewerId == null || _signalingService == null)
      return;

    debugPrint('[WebRTCHost] Renegotiating session with viewer $_activeViewerId...');
    try {
      final transceivers = await _pc!.getTransceivers();
      debugPrint('[WebRTCHost] Current transceivers: ${transceivers.length}');
      
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      _signalingService!.sendOffer(_activeViewerId!, offer.sdp!);
      _remoteDescriptionSet = false;
    } catch (e) {
      debugPrint('[WebRTCHost] Renegotiation error: $e');
    }
  }

  void _setupSignaling(SignalingService signalingService) {
    // Clear existing handlers to prevent multiple listeners
    void onViewerJoined(Map<String, dynamic> msg) async {
      final realViewerId = msg['from'] as String?;
      
      if (realViewerId == null) {
        debugPrint('[WebRTCHost] WARNING: Received joined event with no "from" ID. Ignoring.');
        return;
      }

      debugPrint('[WebRTCHost] Viewer joined: $realViewerId');
      
      // If it's a new viewer or we don't have a PC yet, create it
      if (_activeViewerId != realViewerId || _pc == null) {
        _activeViewerId = realViewerId;
        await _createPeerConnectionForViewer(signalingService, realViewerId);
      } else {
        debugPrint(
            '[WebRTCHost] Viewer $realViewerId rejoined. Updating tracks...');
        await _updateTracks();
      }
    }

    signalingService.on('viewer_joined', onViewerJoined);
    signalingService.on('connect', onViewerJoined);

    signalingService.on('answer', (msg) async {
      if (_activeViewerId == null || msg['from'] != _activeViewerId || _pc == null) return;
      final sdp = msg['payload'] as String;
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));

      _remoteDescriptionSet = true;
      for (var cand in _remoteIceQueue) {
        await _pc!.addCandidate(cand);
      }
      _remoteIceQueue.clear();

      _viewerCount = 1; // Simplification for now
      notifyListeners();
    });

    signalingService.on('ice', (msg) async {
      if (_activeViewerId == null || msg['from'] != _activeViewerId || _pc == null) return;
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

    signalingService.on('offer', (msg) async {
      if (_activeViewerId == null || msg['from'] != _activeViewerId || _pc == null) return;
      final sdp = msg['payload'] as String;
      debugPrint('[WebRTCHost] Received renegotiation Offer from viewer.');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

      _remoteDescriptionSet = true;
      for (var cand in _remoteIceQueue) {
        await _pc!.addCandidate(cand);
      }
      _remoteIceQueue.clear();

      final answer = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(answer);
      signalingService.sendAnswer(_activeViewerId!, answer.sdp!);
    });
  }

  void _clearRemoteRendererTrack(MediaStreamTrack track) {
    if (track.kind != 'video') return;
    if (_remoteStream != null &&
        _remoteStream!.getVideoTracks().any((t) => t.id == track.id)) {
      debugPrint('[WebRTCHost] Clearing remote renderer because track ended.');
      remoteRenderer.srcObject = null;
      _remoteStream = null;
      notifyListeners();
    }
  }

  Future<void> _createPeerConnectionForViewer(
    SignalingService signalingService,
    String viewerId, {
    bool useTurn = false,
  }) async {
    try {
      _pc = await _webrtcRepo.createPC(useTurn: useTurn);
      _senders.clear();

      _pc!.onTrack = (event) async {
        debugPrint(
            '[WebRTCHost] onTrack from viewer: ${event.track.kind} trackId: ${event.track.id}');

        // Listen for track ending
        event.track.onEnded = () {
          debugPrint('[WebRTCHost] Viewer track ended: ${event.track.id}');
          _clearRemoteRendererTrack(event.track);
        };

        MediaStream? streamToUse;
        if (event.streams.isNotEmpty) {
          streamToUse = event.streams.first;
        } else {
          // Unified Plan fallback
          _remoteStream ??= await createLocalMediaStream('remote_stream_host');
          _remoteStream!.addTrack(event.track);
          streamToUse = _remoteStream;
        }

        _remoteStream = streamToUse;
        remoteRenderer.srcObject = _remoteStream;

        event.track.enabled = true;
        notifyListeners();
      };

      _pc!.onRemoveTrack = (stream, track) {
        debugPrint('[WebRTCHost] onRemoveTrack from viewer: ${track.id}');
        _clearRemoteRendererTrack(track);
      };

      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
          signalingService.sendIce(viewerId, {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
        }
      };

      // ── TURN fallback: watch ICE connection state ─────────────────────────
      _pc!.onIceConnectionState = (RTCIceConnectionState state) async {
        debugPrint('[WebRTCHost] Viewer ICE state changed: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          debugPrint('[WebRTCHost] SUCCESS! Viewer is fully connected at peer level.');
        }

        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed &&
            !useTurn) {
          debugPrint(
              '[WebRTCHost] ICE failed with STUN-only — retrying with TURN relay...');

          await _pc?.close();
          _pc = null;
          _senders.clear();
          _remoteDescriptionSet = false;
          _remoteIceQueue.clear();

          await _createPeerConnectionForViewer(
            signalingService,
            viewerId,
            useTurn: true,
          );
        }
      };

      // Add existing tracks if any are active
      await _updateTracks();

      // ── CRITICAL: Always ensure transceivers exist for Viewer media ──────────────────────
      // To receive the Viewer's camera and mic correctly, the Host's offer MUST contain
      // slots (transceivers) for both Audio and Video. If the Host is only sharing a screen,
      // the offer would only have a Video transceiver, causing the Viewer's Answer to omit Audio.
      final transceivers = await _pc!.getTransceivers();
      bool hasAudio = false;
      bool hasVideo = false;
      for (var t in transceivers) {
        final kind = t.sender.track?.kind ?? t.receiver.track?.kind;
        if (kind == 'audio') hasAudio = true;
        if (kind == 'video') hasVideo = true;
      }
      
      if (!hasAudio) {
        await _pc!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }
      if (!hasVideo) {
        await _pc!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
      }
      await _renegotiate();
    } catch (e) {
      debugPrint('[WebRTCHost] Error creating PC: $e');
    }
  }

  Future<void> stopScreenShare() async {
    if (_screenStream == null) return;

    // Remove screen tracks from the peer connection
    if (_pc != null) {
      final screenTrackIds =
          _screenStream!.getTracks().map((t) => t.id).toSet();
      final sendersToRemove = <String>[];
      for (var entry in _senders.entries) {
        if (screenTrackIds.contains(entry.key)) {
          try {
            await _pc!.removeTrack(entry.value);
          } catch (e) {
            debugPrint('[WebRTCHost] Error removing screen track: $e');
          }
          sendersToRemove.add(entry.key);
        }
      }
      for (var id in sendersToRemove) {
        _senders.remove(id);
      }
    }

    // Clear localRenderer if it was showing the screen
    if (localRenderer.srcObject == _screenStream) {
      localRenderer.srcObject = _cameraStream; // fallback to camera or null
    }

    // Dispose screen stream safely (can deadlock on Android main thread)
    try {
      for (var track in _screenStream!.getTracks()) {
        await track.stop();
      }
      await _screenStream!.dispose();
    } catch (e) {
      debugPrint('[WebRTCHost] Screen stream disposal error (non-fatal): $e');
    }
    _screenStream = null;

    // Stop Android foreground service ONLY if camera is also not active
    if (!isCameraSharing) {
      await _webrtcRepo.stopForegroundService();
    }

    // Renegotiate if we have an active viewer
    if (_pc != null && _activeViewerId != null) {
      await _renegotiate();
    }

    notifyListeners();
  }

  Future<void> stopHosting() async {
    // Notify active viewer that meeting has ended
    if (_activeViewerId != null && _signalingService != null) {
      _signalingService!.sendDisconnect(_activeViewerId!);
      // Give the socket a moment to flush the message
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _setState(HostStreamState.idle);

    // Clear renderers first to stop native processing
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    // Dispose streams safely
    try {
      if (_screenStream != null) {
        for (var track in _screenStream!.getTracks()) {
          await track.stop();
        }
        await _screenStream!.dispose();
      }
    } catch (e) {
      debugPrint('[WebRTCHost] Screen stream disposal error: $e');
    }

    await _cameraStream?.dispose();
    await _remoteStream?.dispose();
    cameraRenderer.srcObject = null;
    await _pc?.close();

    // Stop the Android foreground service notification
    await _webrtcRepo.stopForegroundService();

    _pc = null;
    _screenStream = null;
    _cameraStream = null;
    _remoteStream = null;
    _viewerCount = 0;
    _senders.clear();
    _activeViewerId = null;
  }

  void _setState(HostStreamState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    // Synchronously clear srcObject to avoid race conditions during shutdown
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    // Attempt cleanup (can't await in dispose)
    _screenStream?.dispose();
    _cameraStream?.dispose();
    _remoteStream?.dispose();
    _pc?.close();

    localRenderer.dispose();
    remoteRenderer.dispose();
    cameraRenderer.dispose();
    super.dispose();
  }
}
