import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../core/metered_service.dart';

class MeetingScreen extends ConsumerStatefulWidget {
  final SessionModel session;

  const MeetingScreen({super.key, required this.session});

  @override
  ConsumerState<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends ConsumerState<MeetingScreen> {
  final _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;

  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;

  late final DocumentReference _meetingRef;
  late final DocumentReference _participantRef;
  StreamSubscription? _meetingSub;
  StreamSubscription? _participantSub;

  List<Map<String, dynamic>> _participants = [];
  StreamSubscription? _participantsSub;
  bool _isKicked = false;

  // WebRTC multi-party mesh maps
  final Map<String, RTCPeerConnection?> _peerConnections = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, List<RTCIceCandidate>> _remoteCandidatesQueues = {};
  final Map<String, bool> _remoteDescriptionsSet = {};

  // FIX: Added TURN server — without this, calls fail on mobile data / different networks
  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _meetingRef = FirebaseFirestore.instance
        .collection('meetings')
        .doc(widget.session.id);
    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    _participantRef = _meetingRef.collection('participants').doc(currentUserId);

    _initMeeting();
  }

  Future<void> _initMeeting() async {
    // Dynamically fetch ICE/TURN servers from Metered.ca
    try {
      final servers = await MeteredService.fetchIceServers();
      _iceConfiguration['iceServers'] = servers;
    } catch (e) {
      debugPrint('Error loading Metered ICE servers: $e');
    }

    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    final currentUser = ref.read(authRepositoryProvider).currentUser;

    // Check if meeting is already terminated
    try {
      final docSnap = await _meetingRef.get();
      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>?;
        if (data != null && data['isTerminated'] == true) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This meeting has been terminated by the admin.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking meeting termination: $e');
    }

    // FIX: Admin cleanup now only runs on FIRST creation, not on every rejoin.
    // Previously, admin joining would delete ALL participants and peer_connections
    // every time, which destroyed all active WebRTC connections.
    final isAdmin = widget.session.createdBy == currentUserId;
    if (isAdmin) {
      try {
        final meetingSnap = await _meetingRef.get();
        final data = meetingSnap.data() as Map<String, dynamic>?;
        final alreadyInitialized = data?['initialized'] == true;

        if (!alreadyInitialized) {
          // Only clean stale data when the meeting is first created
          final participantsSnap = await _meetingRef
              .collection('participants')
              .get();
          for (final doc in participantsSnap.docs) {
            await doc.reference.delete();
          }
          final pcSnap = await _meetingRef.collection('peer_connections').get();
          for (final doc in pcSnap.docs) {
            final callerCands = await doc.reference
                .collection('callerCandidates')
                .get();
            for (final c in callerCands.docs) {
              await c.reference.delete();
            }
            final receiverCands = await doc.reference
                .collection('receiverCandidates')
                .get();
            for (final c in receiverCands.docs) {
              await c.reference.delete();
            }
            await doc.reference.delete();
          }
          // Mark as initialized so cleanup doesn't run again on rejoin
          await _meetingRef.set({'initialized': true}, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('Error cleaning up stale meeting records: $e');
      }
    }

    // 1. Initialize local WebRTC renderers and start local stream FIRST
    // FIX: We must fully await _startLocalStream() before anything else,
    // so _localStream is guaranteed non-null when peer connections are created.
    await _localRenderer.initialize();
    await _startLocalStream();

    // 2. Set/Merge main meeting document
    await _meetingRef.set({
      'id': widget.session.id,
      'kickedUsers': FieldValue.arrayUnion([]),
      'isTerminated': false,
    }, SetOptions(merge: true));

    // 3. Register self as participant
    await _participantRef.set({
      'userId': currentUserId,
      'name': currentUser?.name ?? 'Student',
      'micOn': _isMicOn,
      'cameraOn': _isCameraOn,
      'joinedAt': FieldValue.serverTimestamp(),
      'isKicked': false,
    });

    // 4. Listen to meeting state changes
    _meetingSub = _meetingRef.snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;

      if (data['isTerminated'] == true) {
        _handleMeetingTerminated();
        return;
      }

      final kicked = List<String>.from(data['kickedUsers'] ?? []);
      if (kicked.contains(currentUserId)) {
        _handleKicked();
        return;
      }
    });

    // 5. Listen to own participant document changes (for admin mute/camera off)
    _participantSub = _participantRef.snapshots().listen((snap) {
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>?;
      if (data == null) return;

      if (data['isKicked'] == true) {
        _handleKicked();
        return;
      }

      final remoteMic = data['micOn'] == true;
      final remoteCamera = data['cameraOn'] == true;

      if (remoteMic != _isMicOn) _setMic(remoteMic);
      if (remoteCamera != _isCameraOn) _setCamera(remoteCamera);
    });

    // 6. Listen to all participants & manage peer connections dynamically
    _participantsSub = _meetingRef
        .collection('participants')
        .orderBy('joinedAt', descending: false)
        .snapshots()
        .listen((snapshot) async {
          final list = snapshot.docs.map((d) => d.data()).where((data) {
            final userId = (data['userId'] as String? ?? '').toLowerCase();
            final name = (data['name'] as String? ?? '').toLowerCase();
            final isKicked = data['isKicked'] == true;
            final isMock =
                userId.startsWith('mock') ||
                userId == 'rahul' ||
                userId == 'priya' ||
                name.contains('rahul') ||
                name.contains('priya');
            return !isKicked && !isMock;
          }).toList();

          if (mounted) {
            setState(() {
              _participants = list;
            });
          }

          final activeUserIds = list.map((p) => p['userId'] as String).toSet();

          for (final uid in activeUserIds) {
            if (uid != currentUserId && !_peerConnections.containsKey(uid)) {
              await _startPeerConnection(uid);
            }
          }

          final uidsToDisconnect = _peerConnections.keys
              .where((uid) => !activeUserIds.contains(uid))
              .toList();
          for (final uid in uidsToDisconnect) {
            _removeParticipantConnection(uid);
          }
        });
  }

  Future<void> _startPeerConnection(String otherUserId) async {
    if (_peerConnections.containsKey(otherUserId)) return;
    _peerConnections[otherUserId] = null; // Mark as initializing

    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    final isCaller = currentUserId.compareTo(otherUserId) > 0;

    try {
      // FIX: Ensure local stream is ready before creating peer connection.
      if (_localStream == null) {
        await _startLocalStream();
      }

      _remoteDescriptionsSet[otherUserId] = false;
      _remoteCandidatesQueues[otherUserId] = [];

      final pc = await createPeerConnection(_iceConfiguration);
      _peerConnections[otherUserId] = pc;

      // FIX: _localStream is now guaranteed non-null here
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      pc.onIceCandidate = (candidate) {
        final pcDocId = isCaller
            ? '${currentUserId}_$otherUserId'
            : '${otherUserId}_$currentUserId';
        final pcDoc = _meetingRef.collection('peer_connections').doc(pcDocId);
        pcDoc
            .collection(isCaller ? 'callerCandidates' : 'receiverCandidates')
            .add(candidate.toMap());
      };

      pc.onTrack = (event) async {
        if (event.streams.isNotEmpty) {
          final stream = event.streams[0];
          _remoteStreams[otherUserId] = stream;

          final renderer = RTCVideoRenderer();
          await renderer.initialize();
          renderer.srcObject = stream;

          if (mounted) {
            setState(() {
              _remoteRenderers[otherUserId] = renderer;
            });
          }
        }
      };

      final pcDocId = isCaller
          ? '${currentUserId}_$otherUserId'
          : '${otherUserId}_$currentUserId';
      final pcDoc = _meetingRef.collection('peer_connections').doc(pcDocId);

      if (isCaller) {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await pcDoc.set({
          'offer': {'sdp': offer.sdp, 'type': offer.type},
          'callerId': currentUserId,
          'receiverId': otherUserId,
        }, SetOptions(merge: true));

        bool answerProcessed = false;
        pcDoc.snapshots().listen((snap) async {
          if (!snap.exists) return;
          final data = snap.data();
          if (data != null && data['answer'] != null && !answerProcessed) {
            answerProcessed = true;
            final answerMap = data['answer'] as Map<String, dynamic>;
            final answer = RTCSessionDescription(
              answerMap['sdp'],
              answerMap['type'],
            );
            await pc.setRemoteDescription(answer);

            _remoteDescriptionsSet[otherUserId] = true;
            final queue = _remoteCandidatesQueues[otherUserId] ?? [];
            for (final candidate in queue) {
              try {
                await pc.addCandidate(candidate);
              } catch (e) {
                debugPrint('Error adding queued remote candidate: $e');
              }
            }
            _remoteCandidatesQueues[otherUserId]?.clear();

            final candidatesCol = pcDoc.collection('receiverCandidates');
            final candSnap = await candidatesCol.get();
            for (final d in candSnap.docs) {
              final map = d.data();
              final c = RTCIceCandidate(
                map['candidate'],
                map['sdpMid'],
                map['sdpMLineIndex'],
              );
              if (_remoteDescriptionsSet[otherUserId] == true) {
                await pc.addCandidate(c);
              } else {
                _remoteCandidatesQueues[otherUserId]?.add(c);
              }
            }

            candidatesCol.snapshots().listen((snap) async {
              for (final change in snap.docChanges) {
                if (change.type == DocumentChangeType.added) {
                  final map = change.doc.data();
                  if (map != null) {
                    final c = RTCIceCandidate(
                      map['candidate'],
                      map['sdpMid'],
                      map['sdpMLineIndex'],
                    );
                    if (_remoteDescriptionsSet[otherUserId] == true) {
                      await pc.addCandidate(c);
                    } else {
                      _remoteCandidatesQueues[otherUserId]?.add(c);
                    }
                  }
                }
              }
            });
          }
        });
      } else {
        bool offerProcessed = false;
        pcDoc.snapshots().listen((snap) async {
          if (!snap.exists) return;
          final data = snap.data();
          if (data != null && data['offer'] != null && !offerProcessed) {
            offerProcessed = true;
            final offerMap = data['offer'] as Map<String, dynamic>;
            final offer = RTCSessionDescription(
              offerMap['sdp'],
              offerMap['type'],
            );
            await pc.setRemoteDescription(offer);

            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            await pcDoc.update({
              'answer': {'sdp': answer.sdp, 'type': answer.type},
            });

            _remoteDescriptionsSet[otherUserId] = true;
            final queue = _remoteCandidatesQueues[otherUserId] ?? [];
            for (final candidate in queue) {
              try {
                await pc.addCandidate(candidate);
              } catch (e) {
                debugPrint('Error adding queued remote candidate: $e');
              }
            }
            _remoteCandidatesQueues[otherUserId]?.clear();

            final candidatesCol = pcDoc.collection('callerCandidates');
            final candSnap = await candidatesCol.get();
            for (final d in candSnap.docs) {
              final map = d.data();
              final c = RTCIceCandidate(
                map['candidate'],
                map['sdpMid'],
                map['sdpMLineIndex'],
              );
              if (_remoteDescriptionsSet[otherUserId] == true) {
                await pc.addCandidate(c);
              } else {
                _remoteCandidatesQueues[otherUserId]?.add(c);
              }
            }

            candidatesCol.snapshots().listen((snap) async {
              for (final change in snap.docChanges) {
                if (change.type == DocumentChangeType.added) {
                  final map = change.doc.data();
                  if (map != null) {
                    final c = RTCIceCandidate(
                      map['candidate'],
                      map['sdpMid'],
                      map['sdpMLineIndex'],
                    );
                    if (_remoteDescriptionsSet[otherUserId] == true) {
                      await pc.addCandidate(c);
                    } else {
                      _remoteCandidatesQueues[otherUserId]?.add(c);
                    }
                  }
                }
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error starting peer connection: $e');
      // Remove the null placeholder so it can be retried
      _peerConnections.remove(otherUserId);
      _remoteCandidatesQueues.remove(otherUserId);
      _remoteDescriptionsSet.remove(otherUserId);
    }
  }

  void _removeParticipantConnection(String userId) {
    final pc = _peerConnections.remove(userId);
    pc?.close();
    _remoteStreams.remove(userId)?.dispose();
    final renderer = _remoteRenderers.remove(userId);
    renderer?.dispose();
    _remoteCandidatesQueues.remove(userId);
    _remoteDescriptionsSet.remove(userId);
    if (mounted) setState(() {});
  }

  Future<void> _startLocalStream() async {
    try {
      final Map<String, dynamic> constraints = {
        'audio': true,
        'video': {'facingMode': _isFrontCamera ? 'user' : 'environment'},
      };
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream = stream;
      _localRenderer.srcObject = stream;

      // Apply current mic/camera state to the new stream
      stream.getAudioTracks().forEach((t) => t.enabled = _isMicOn);
      stream.getVideoTracks().forEach((t) => t.enabled = _isCameraOn);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error getting local user media: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access camera/mic. Check permissions: $e'),
          ),
        );
      }
    }
  }

  void _setMic(bool value) {
    setState(() => _isMicOn = value);
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = value;
    });
  }

  void _setCamera(bool value) {
    setState(() => _isCameraOn = value);
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = value;
    });
  }

  Future<void> _toggleMic() async {
    final newVal = !_isMicOn;
    _setMic(newVal);
    await _participantRef.update({'micOn': newVal});
  }

  Future<void> _toggleCamera() async {
    final newVal = !_isCameraOn;
    _setCamera(newVal);
    await _participantRef.update({'cameraOn': newVal});
  }

  // FIX: _toggleSpeaker was empty before — it toggled state but never
  // actually switched the audio route. Now calls Helper.setSpeakerphoneOn.
  Future<void> _toggleSpeaker() async {
    final newVal = !_isSpeakerOn;
    setState(() => _isSpeakerOn = newVal);
    try {
      await Helper.setSpeakerphoneOn(newVal);
    } catch (e) {
      debugPrint('Speaker toggle error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_localStream != null) {
      _isFrontCamera = !_isFrontCamera;
      try {
        await Helper.switchCamera(_localStream!.getVideoTracks().first);
        setState(() {});
      } catch (_) {
        _localStream?.dispose();
        await _startLocalStream();
      }
    }
  }

  void _handleKicked() {
    if (_isKicked) return;
    _isKicked = true;
    _cleanup();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have been removed from the session by the admin.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleMeetingTerminated() {
    _cleanup();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The admin has terminated this meeting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _leaveMeeting() {
    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    final isAdmin = widget.session.createdBy == currentUserId;

    if (isAdmin) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'End Meeting',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Would you like to just leave the meeting, or terminate it for all participants?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _justLeave();
              },
              child: const Text(
                'Leave Only',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _terminateMeeting();
              },
              child: const Text(
                'Terminate Meeting',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } else {
      _justLeave();
    }
  }

  void _justLeave() {
    _cleanup();
    Navigator.of(context).pop();
  }

  Future<void> _terminateMeeting() async {
    await _meetingRef.update({'isTerminated': true});
    _cleanup();
    if (mounted) Navigator.of(context).pop();
  }

  void _cleanup() {
    _meetingSub?.cancel();
    _participantSub?.cancel();
    _participantsSub?.cancel();
    _participantRef.delete().catchError((_) {});

    for (final pc in _peerConnections.values) {
      pc?.close();
    }
    _peerConnections.clear();

    _localStream?.dispose();
    for (final stream in _remoteStreams.values) {
      stream.dispose();
    }
    _remoteStreams.clear();

    _localRenderer.dispose();
    for (final renderer in _remoteRenderers.values) {
      renderer.dispose();
    }
    _remoteRenderers.clear();
    _remoteCandidatesQueues.clear();
    _remoteDescriptionsSet.clear();
  }

  Future<void> _adminMuteUser(String userId) async {
    await _meetingRef.collection('participants').doc(userId).update({
      'micOn': false,
    });
  }

  Future<void> _adminDisableUserVideo(String userId) async {
    await _meetingRef.collection('participants').doc(userId).update({
      'cameraOn': false,
    });
  }

  Future<void> _adminKickUser(String userId) async {
    await _meetingRef.collection('participants').doc(userId).update({
      'isKicked': true,
    });
    await _meetingRef.update({
      'kickedUsers': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> _adminMuteAll() async {
    final snap = await _meetingRef.collection('participants').get();
    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    for (final doc in snap.docs) {
      if (doc.id != currentUserId) {
        await doc.reference.update({'micOn': false});
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Muted all participants.')));
    }
  }

  Future<void> _adminDisableAllVideo() async {
    final snap = await _meetingRef.collection('participants').get();
    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    for (final doc in snap.docs) {
      if (doc.id != currentUserId) {
        await doc.reference.update({'cameraOn': false});
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turned off video for all participants.')),
      );
    }
  }

  void _showAdminControlPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setInnerState) => Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Admin Controls',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.2,
                        ),
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: () {
                        _adminMuteAll();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.mic_off),
                      label: const Text('Mute All'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.2,
                        ),
                        foregroundColor: Colors.redAccent,
                      ),
                      onPressed: () {
                        _adminDisableAllVideo();
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.videocam_off),
                      label: const Text('Stop All Video'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              const Divider(color: Colors.white24),
              const Text(
                'Attendants List',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: _participants
                      .where(
                        (p) =>
                            p['userId'] !=
                            (ref.read(authRepositoryProvider).currentUser?.id ??
                                ''),
                      )
                      .map((p) {
                        final uid = p['userId'] as String;
                        final mic = p['micOn'] == true;
                        final video = p['cameraOn'] == true;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryBlue,
                            child: Text(
                              p['name']?[0]?.toUpperCase() ?? 'S',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            p['name'] ?? 'Student',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  mic ? Icons.mic : Icons.mic_off,
                                  color: mic ? Colors.green : Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: mic
                                    ? () => _adminMuteUser(uid)
                                    : null,
                                tooltip: mic
                                    ? 'Mute attendant'
                                    : 'Attendant is muted',
                              ),
                              IconButton(
                                icon: Icon(
                                  video ? Icons.videocam : Icons.videocam_off,
                                  color: video
                                      ? Colors.green
                                      : Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: video
                                    ? () => _adminDisableUserVideo(uid)
                                    : null,
                                tooltip: video
                                    ? 'Stop attendant video'
                                    : 'Video is turned off',
                              ),

                              IconButton(
                                icon: const Icon(
                                  Icons.person_remove,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: () {
                                  _adminKickUser(uid);
                                  Navigator.pop(ctx);
                                },
                                tooltip: 'Remove attendant',
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCell(Map<String, dynamic> p, bool isLocal) {
    final cameraOn = p['cameraOn'] == true;
    final micOn = p['micOn'] == true;
    final name = p['name'] ?? 'Student';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: micOn
              ? AppTheme.secondaryTeal.withValues(alpha: 0.6)
              : Colors.white12,
          width: micOn ? 3.0 : 1.0,
        ),
        boxShadow: micOn
            ? [
                BoxShadow(
                  color: AppTheme.secondaryTeal.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (cameraOn)
              Positioned.fill(
                child: isLocal
                    ? RTCVideoView(
                        _localRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : (_remoteRenderers[p['userId']] != null
                          ? RTCVideoView(
                              _remoteRenderers[p['userId']]!,
                              objectFit: RTCVideoViewObjectFit
                                  .RTCVideoViewObjectFitCover,
                            )
                          : Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF0F172A),
                                    Color(0xFF1E293B),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 32,
                                      backgroundColor: AppTheme.primaryBlue
                                          .withValues(alpha: 0.2),
                                      child: const Icon(
                                        Icons.person,
                                        size: 36,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.secondaryTeal,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Connecting stream...',
                                          style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            )),
              )
            else
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF0F172A),
                  child: Center(
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: AppTheme.primaryBlue,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'S',
                        style: const TextStyle(
                          fontSize: 28,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: [
                  if (!micOn)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_off,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 4),
                  if (!cameraOn)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.videocam_off,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),

            Positioned(
              bottom: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isLocal ? '$name (You)' : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId =
        ref.watch(authRepositoryProvider).currentUser?.id ?? '';
    final isAdmin = widget.session.createdBy == currentUserId;

    final localUserMap = _participants.firstWhere(
      (p) => p['userId'] == currentUserId,
      orElse: () => {
        'userId': currentUserId,
        'name': 'You',
        'micOn': _isMicOn,
        'cameraOn': _isCameraOn,
      },
    );

    final otherParticipants = _participants
        .where((p) => p['userId'] != currentUserId)
        .toList();
    final allGridItems = [localUserMap, ...otherParticipants];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.session.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_participants.length} Active Participants',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(
                Icons.admin_panel_settings,
                color: AppTheme.secondaryTeal,
                size: 26,
              ),
              onPressed: _showAdminControlPanel,
              tooltip: 'Admin Settings Panel',
            ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.white),
            onPressed: _isCameraOn ? _switchCamera : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: GridView.builder(
                  itemCount: allGridItems.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemBuilder: (context, index) {
                    final p = allGridItems[index];
                    final isLocal = p['userId'] == currentUserId;
                    return _buildVideoCell(p, isLocal);
                  },
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ControlButton(
                    isActive: _isMicOn,
                    activeIcon: Icons.mic,
                    inactiveIcon: Icons.mic_off,
                    onTap: _toggleMic,
                  ),
                  _ControlButton(
                    isActive: _isCameraOn,
                    activeIcon: Icons.videocam,
                    inactiveIcon: Icons.videocam_off,
                    onTap: _toggleCamera,
                  ),
                  _ControlButton(
                    isActive: _isSpeakerOn,
                    activeIcon: Icons.volume_up,
                    inactiveIcon: Icons.volume_off,
                    onTap: _toggleSpeaker,
                  ),

                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.redAccent,
                    ),
                    child: IconButton(
                      iconSize: 28,
                      icon: const Icon(Icons.call_end, color: Colors.white),
                      onPressed: _leaveMeeting,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final bool isActive;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.isActive,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = Colors.white.withValues(alpha: 0.1);
    final inactiveBg = Colors.redAccent.withValues(alpha: 0.15);

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? activeBg : inactiveBg,
      ),
      child: IconButton(
        iconSize: 24,
        icon: Icon(
          isActive ? activeIcon : inactiveIcon,
          color: isActive ? Colors.white : Colors.redAccent,
        ),
        onPressed: onTap,
      ),
    );
  }
}
