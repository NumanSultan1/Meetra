import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/theme.dart';
import '../core/metered_service.dart';

class CallScreen extends StatefulWidget {
  final String receiverName;
  final String receiverId;
  final bool isVideo;
  final String? callId;
  final bool isReceiver;

  const CallScreen({
    super.key,
    required this.receiverName,
    required this.receiverId,
    required this.isVideo,
    this.callId,
    this.isReceiver = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _isConnected = false;
  int _secondsElapsed = 0;
  Timer? _callTimer;
  Timer? _connectionTimer;
  Timer? _ringingTimeoutTimer;

  // WebRTC & Audio player states
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  late final AudioPlayer _ringTonePlayer;

  // Firestore Subscriptions
  StreamSubscription? _callDocSubscription;
  StreamSubscription? _callerCandidatesSubscription;
  StreamSubscription? _receiverCandidatesSubscription;

  bool _isCleanedUp = false;

  // WebRTC Candidate Queuing State to avoid early candidate crashes
  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _remoteCandidatesQueue = [];

  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      }
    ],
    'sdpSemantics': 'unified-plan',
  };

  String _statusLabel = 'Calling...';
  bool _hasLoggedCallHistory = false;

  @override
  void initState() {
    super.initState();
    _isCameraOn = widget.isVideo;
    _ringTonePlayer = AudioPlayer();
    _statusLabel = widget.isReceiver ? 'Connecting...' : 'Calling...';

    // Pulse animation for sound waves (Voice call)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    if (!widget.isVideo) {
      _pulseController.repeat();
    }

    _initializeCalling();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _initializeCalling() async {
    // Fetch dynamic ICE/TURN servers from Metered.ca
    try {
      final servers = await MeteredService.fetchIceServers();
      _iceConfiguration['iceServers'] = servers;
    } catch (e) {
      debugPrint('Error loading Metered ICE servers: $e');
    }

    try {
      if (widget.isVideo) {
        await [Permission.microphone, Permission.camera].request();
      } else {
        await Permission.microphone.request();
      }
    } catch (e) {
      debugPrint('Error requesting permissions at runtime: $e');
    }

    await _initRenderers();

    // Set audio context to force output to speaker or appropriate channels (fixes routing volume issues)
    try {
      final playerContext = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      );
      await _ringTonePlayer.setAudioContext(playerContext);
    } catch (_) {}

    // Play ringing audio loops
    if (widget.isReceiver) {
      // Receiver connects call, no ringback needed
    } else {
      // Caller: play ringback beep (using a verified working public domain sample URL)
      _ringTonePlayer.setReleaseMode(ReleaseMode.loop);
      try {
        await _ringTonePlayer.play(UrlSource('https://samplelib.com/mp3/sample-3s.mp3'));
      } catch (_) {}
    }

    // Initialize peer connection
    try {
      _peerConnection = await createPeerConnection(_iceConfiguration);

      _peerConnection!.onIceCandidate = (candidate) {
        if (widget.callId == null) return;
        final candidatesCol = FirebaseFirestore.instance
            .collection('calls')
            .doc(widget.callId)
            .collection(widget.isReceiver ? 'receiverCandidates' : 'callerCandidates');
        candidatesCol.add(candidate.toMap());
      };

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          event.streams[0].getTracks().forEach((track) {
            track.enabled = true;
          });
          setState(() {
            _remoteStream = event.streams[0];
            _remoteRenderer.srcObject = _remoteStream;
          });
        }
      };

      // Logging connection and handshake states for diagnostics
      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('WebRTC ICE Connection State: $state');
      };
      _peerConnection!.onConnectionState = (state) {
        debugPrint('WebRTC Peer Connection State: $state');
      };
      _peerConnection!.onSignalingState = (state) {
        debugPrint('WebRTC Signaling State: $state');
      };

      // Get camera and mic stream
      // 1. Detect front camera deviceId
      String? frontCameraId;
      try {
        final devices = await navigator.mediaDevices.enumerateDevices();
        for (final device in devices) {
          if (device.kind == 'videoinput') {
            final label = device.label.toLowerCase();
            if (label.contains('front') || label.contains('user')) {
              frontCameraId = device.deviceId;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error detecting front camera device: $e');
      }

      final mediaConstraints = {
        'audio': true,
        'video': widget.isVideo
            ? {
                if (frontCameraId != null) 'deviceId': frontCameraId else 'facingMode': 'user',
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
                'optional': [],
              }
            : false,
      };

      try {
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        debugPrint('Failed to get media stream with specific constraints: $e. Retrying with basic constraints...');
        final fallbackConstraints = {
          'audio': true,
          'video': widget.isVideo ? {'facingMode': 'user'} : false,
        };
        _localStream = await navigator.mediaDevices.getUserMedia(fallbackConstraints);
      }

      setState(() {
        _localRenderer.srcObject = _localStream;
      });

      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Force sound output to speakerphone by default
      try {
        await Helper.setSpeakerphoneOn(_isSpeakerOn);
      } catch (e) {
        debugPrint('Error setting speakerphone initially: $e');
      }
    } catch (e) {
      debugPrint('WebRTC initialization error: $e');
    }

    if (widget.callId != null) {
      _listenToCallDoc();
      
      if (widget.isReceiver) {
        await _joinCall();
      } else {
        await _createCall();
      }
    } else {
      // Fallback fallback simulated delayed connection
      _connectionTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isConnected = true;
          });
          _startTimer();
        }
      });
    }
  }

  Future<void> _createCall() async {
    if (_peerConnection == null) return;

    final RTCSessionDescription offer = await _peerConnection!.createOffer({
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': widget.isVideo,
      },
      'optional': [],
    });
    await _peerConnection!.setLocalDescription(offer);

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .update({
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      }
    });

    _receiverCandidatesSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .collection('receiverCandidates')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && _peerConnection != null) {
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            if (_isRemoteDescriptionSet) {
              try {
                _peerConnection!.addCandidate(candidate);
              } catch (e) {
                debugPrint('Error adding remote candidate directly: $e');
              }
            } else {
              _remoteCandidatesQueue.add(candidate);
            }
          }
        }
      }
    });

    _ringingTimeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (!_isConnected && mounted) {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(widget.callId)
            .update({'status': 'ended'});
        _endCallLocally(message: 'No answer');
      }
    });
  }

  Future<void> _joinCall() async {
    if (_peerConnection == null) return;

    DocumentSnapshot<Map<String, dynamic>> callDoc = await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .get();

    // Wait for the caller's offer to be written to Firestore if it is not available yet
    if (callDoc.data()?['offer'] == null) {
      debugPrint('Receiver: Offer not found yet. Waiting for offer to be written...');
      final completer = Completer<void>();
      StreamSubscription? tempSubscription;
      tempSubscription = FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .snapshots()
          .listen((snapshot) {
        final data = snapshot.data();
        if (data != null && data['offer'] != null) {
          tempSubscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      });

      try {
        await completer.future.timeout(const Duration(seconds: 10));
        callDoc = await FirebaseFirestore.instance
            .collection('calls')
            .doc(widget.callId)
            .get();
      } catch (e) {
        debugPrint('Receiver: Timeout waiting for offer: $e');
        _endCallLocally(message: 'Connection timeout (no offer received)');
        return;
      }
    }

    final callData = callDoc.data();
    if (callData == null || callData['offer'] == null) return;

    final offerMap = callData['offer'];
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await _peerConnection!.setRemoteDescription(offer);

    final RTCSessionDescription answer = await _peerConnection!.createAnswer({
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': widget.isVideo,
      },
      'optional': [],
    });
    await _peerConnection!.setLocalDescription(answer);

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .update({
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      }
    });

    // Mark remote description set, and apply queued caller candidates if any
    _isRemoteDescriptionSet = true;
    for (final candidate in _remoteCandidatesQueue) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        debugPrint('Error adding queued remote candidate: $e');
      }
    }
    _remoteCandidatesQueue.clear();

    _callerCandidatesSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .collection('callerCandidates')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && _peerConnection != null) {
            final candidate = RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            );
            if (_isRemoteDescriptionSet) {
              try {
                _peerConnection!.addCandidate(candidate);
              } catch (e) {
                debugPrint('Error adding remote candidate directly: $e');
              }
            } else {
              _remoteCandidatesQueue.add(candidate);
            }
          }
        }
      }
    });
  }

  void _listenToCallDoc() {
    _callDocSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        _endCallLocally();
        return;
      }
      final data = snapshot.data();
      if (data != null) {
        final status = data['status'];

        if (status == 'ringing' && !widget.isReceiver) {
          setState(() {
            _statusLabel = 'Ringing...';
          });
        }
        
        if (status == 'connected' && !_isConnected) {
          _ringTonePlayer.stop();
          setState(() {
            _isConnected = true;
          });
          _startTimer();
        } else if (status == 'rejected') {
          _endCallLocally(message: 'Call declined');
        } else if (status == 'ended') {
          _endCallLocally(message: 'Call ended');
        }

        if (!widget.isReceiver && status == 'connected' && data['answer'] != null) {
          final answerMap = data['answer'];
          final answer = RTCSessionDescription(answerMap['sdp'], answerMap['type']);
          if (_peerConnection != null && _peerConnection!.signalingState != RTCSignalingState.RTCSignalingStateStable) {
            await _peerConnection!.setRemoteDescription(answer);
            _isRemoteDescriptionSet = true;
            for (final candidate in _remoteCandidatesQueue) {
              try {
                await _peerConnection!.addCandidate(candidate);
              } catch (e) {
                debugPrint('Error adding queued remote candidate: $e');
              }
            }
            _remoteCandidatesQueue.clear();
          }
        }
      }
    });
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _hangUp() async {
    if (widget.callId != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('calls').doc(widget.callId).get();
        if (doc.exists) {
          final currentStatus = doc.data()?['status'];
          final nextStatus = (_isConnected || currentStatus == 'connected') ? 'ended' : 'rejected';
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(widget.callId)
              .update({'status': nextStatus});
        }
      } catch (_) {}
    }
    _endCallLocally();
  }

  void _endCallLocally({String? message}) {
    if (!widget.isReceiver && !_hasLoggedCallHistory) {
      _hasLoggedCallHistory = true;
      _writeCallHistory();
    }
    _cleanupCalling();
    if (mounted) {
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _writeCallHistory() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      final ids = [currentUserId, widget.receiverId]..sort();
      final chatRoomId = '${ids[0]}_${ids[1]}';

      String messageText;
      if (_isConnected) {
        final durationStr = _formatDuration(_secondsElapsed);
        messageText = widget.isVideo
            ? '📹 Video call ($durationStr)'
            : '📞 Voice call ($durationStr)';
      } else {
        messageText = widget.isVideo
            ? '📹 Missed video call'
            : '📞 Missed voice call';
      }

      final docRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .doc();

      await docRef.set({
        'id': docRef.id,
        'senderId': currentUserId,
        'receiverId': widget.receiverId,
        'message': messageText,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Failed to log call history to chat: $e');
    }
  }

  void _cleanupCalling() {
    if (_isCleanedUp) return;
    _isCleanedUp = true;

    _ringTonePlayer.stop();
    _ringTonePlayer.dispose();
    _ringingTimeoutTimer?.cancel();
    _callTimer?.cancel();
    _connectionTimer?.cancel();
    _callDocSubscription?.cancel();
    _callerCandidatesSubscription?.cancel();
    _receiverCandidatesSubscription?.cancel();

    try {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
    } catch (_) {}

    try {
      _peerConnection?.close();
      _peerConnection?.dispose();
    } catch (_) {}

    _localRenderer.dispose();
    _remoteRenderer.dispose();
  }

  void _toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final currentEnabled = audioTracks[0].enabled;
        audioTracks[0].enabled = !currentEnabled;
        setState(() {
          _isMuted = !currentEnabled;
        });
      }
    }
  }

  void _toggleCamera() {
    if (_localStream != null && widget.isVideo) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final currentEnabled = videoTracks[0].enabled;
        videoTracks[0].enabled = !currentEnabled;
        setState(() {
          _isCameraOn = !currentEnabled;
        });
      }
    }
  }

  void _flipCamera() async {
    if (_localStream != null && widget.isVideo) {
      final videoTrack = _localStream!.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        try {
          await Helper.switchCamera(videoTrack);
          setState(() {
            _isFrontCamera = !_isFrontCamera;
          });
        } catch (_) {}
      }
    }
  }

  void _toggleSpeaker() async {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    try {
      await Helper.setSpeakerphoneOn(_isSpeakerOn);
    } catch (_) {}
  }

  @override
  void dispose() {
    _cleanupCalling();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Stack(
        children: [
          if (widget.isVideo && _isCameraOn)
            _buildVideoBackground()
          else
            _buildVoiceBackground(),

          if (widget.isVideo && _isCameraOn)
            Positioned(
              top: 50,
              right: 20,
              child: _buildLocalPipView(),
            ),

          Positioned(
            top: widget.isVideo ? 60 : 120,
            left: 20,
            right: 20,
            child: _buildHeaderView(),
          ),

          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: _buildControlsBar(),
          ),
        ],
      ),
    ));
  }

  Widget _buildVideoBackground() {
    if (_remoteStream == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.secondaryTeal, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.secondaryTeal.withValues(alpha: 0.3),
                      blurRadius: 32,
                      spreadRadius: 8,
                    )
                  ],
                ),
                child: CircleAvatar(
                  radius: 66,
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                  child: Text(
                    widget.receiverName[0].toUpperCase(),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Waiting for ${widget.receiverName}\'s video...',
                style: const TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 0.5),
              ),
            ],
          ),
        ),
      );
    }

    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildVoiceBackground() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 150 + (100 * _pulseController.value),
                    height: 150 + (100 * _pulseController.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryBlue.withValues(
                        alpha: 0.15 * (1.0 - _pulseController.value),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 120 + (60 * _pulseController.value),
                    height: 120 + (60 * _pulseController.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.secondaryTeal.withValues(
                        alpha: 0.25 * (1.0 - _pulseController.value),
                      ),
                    ),
                  );
                },
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: CircleAvatar(
                  radius: 70,
                  backgroundColor: AppTheme.primaryBlue,
                  child: Text(
                    widget.receiverName[0].toUpperCase(),
                    style: const TextStyle(fontSize: 54, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocalPipView() {
    return Container(
      width: 100,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white30, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(2, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _localStream == null
            ? const Center(child: CircularProgressIndicator())
            : RTCVideoView(
                _localRenderer,
                mirror: _isFrontCamera,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
      ),
    );
  }

  Widget _buildHeaderView() {
    return Column(
      children: [
        if (widget.isVideo)
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.videocam, color: Colors.white54, size: 20),
              SizedBox(width: 6),
              Text(
                'STUDYSYNC VIDEO CALL',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ],
          )
        else
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phone, color: Colors.white54, size: 18),
              SizedBox(width: 6),
              Text(
                'STUDYSYNC VOICE CALL',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          widget.receiverName,
          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _isConnected ? _formatDuration(_secondsElapsed) : _statusLabel,
          style: TextStyle(
            color: _isConnected ? AppTheme.secondaryTeal : Colors.white60,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildControlsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(
              _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              color: _isSpeakerOn ? AppTheme.secondaryTeal : Colors.white70,
              size: 26,
            ),
            onPressed: _toggleSpeaker,
            tooltip: 'Speaker',
          ),

          if (widget.isVideo)
            IconButton(
              icon: Icon(
                _isCameraOn ? Icons.videocam : Icons.videocam_off,
                color: _isCameraOn ? AppTheme.secondaryTeal : Colors.white70,
                size: 26,
              ),
              onPressed: _toggleCamera,
              tooltip: 'Camera Toggle',
            ),

          IconButton(
            icon: Icon(
              _isMuted ? Icons.mic_off : Icons.mic,
              color: _isMuted ? Colors.redAccent : Colors.white70,
              size: 26,
            ),
            onPressed: _toggleMute,
            tooltip: 'Mute',
          ),

          if (widget.isVideo && _isCameraOn)
            IconButton(
              icon: const Icon(
                Icons.flip_camera_ios_outlined,
                color: Colors.white70,
                size: 26,
              ),
              onPressed: _flipCamera,
              tooltip: 'Switch Camera',
            ),

          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent,
              boxShadow: [
                BoxShadow(color: Colors.redAccent, blurRadius: 16, spreadRadius: 1)
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
              onPressed: _hangUp,
              tooltip: 'End Call',
            ),
          ),
        ],
      ),
    );
  }
}
