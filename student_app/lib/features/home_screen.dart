import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../core/theme.dart';
import '../core/providers.dart';
import '../core/notification_service.dart';
import 'matching_and_groups.dart';
import 'sessions_tab.dart';
import 'notes_sharing.dart';
import 'profile_screen.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'in_app_notification.dart';
import 'group_requests_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final UserModel currentUser;

  const HomeScreen({super.key, required this.currentUser});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final List<String> _titles = [
    'Find Partners',
    'Study Groups',
    'Sessions',
    'Notes Sharing'
  ];

  late final List<Widget> _tabs;

  StreamSubscription? _incomingCallSub;
  StreamSubscription? _incomingMessagesSub;
  StreamSubscription? _groupRequestsSub;
  int _pendingRequestsCount = 0;
  Set<String> _notifiedRequests = {};
  bool _isRequestsInitialLoad = true;
  bool _isCallDialogShowing = false;
  late final DateTime _appStartTime;

  @override
  void initState() {
    super.initState();
    _appStartTime = DateTime.now();
    _tabs = [
      const PartnerMatchingTab(),
      const GroupsTab(),
      const SessionsTab(),
      const NotesSharingTab(),
    ];
    _listenToIncomingCalls();
    _listenToIncomingMessages();
    _listenToGroupRequests();
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    _incomingMessagesSub?.cancel();
    _groupRequestsSub?.cancel();
    super.dispose();
  }

  void _listenToIncomingCalls() {
    _incomingCallSub = FirebaseFirestore.instance
        .collection('calls')
        .where('receiverId', isEqualTo: widget.currentUser.id)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data();
        final callId = doc.id;
        
        if (!_isCallDialogShowing && mounted) {
          final callerName = data['callerName'] ?? 'Student';
          final isVideo = data['isVideo'] == true;
          NotificationService.showNotification(
            id: callId.hashCode,
            title: isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
            body: '$callerName is calling you...',
          );

          _showIncomingCallOverlay(callId, data);
        }
      }
    });
  }

  void _listenToIncomingMessages() {
    _incomingMessagesSub = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: widget.currentUser.id)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
          final doc = change.doc;
          final data = doc.data();
          if (data == null) continue;

          final lastSender = data['lastMessageSenderId'] as String?;
          final lastMessage = data['lastMessage'] as String?;
          final timestampStr = data['lastMessageTimestamp'] as String?;

          if (lastSender == null || lastMessage == null || timestampStr == null) continue;
          if (lastSender == widget.currentUser.id) continue;

          final timestamp = DateTime.tryParse(timestampStr);
          if (timestamp == null || timestamp.isBefore(_appStartTime)) continue;

          // Only notify if we are not actively in that chat room
          if (ChatScreen.activeChatRoomId == doc.id) continue;

          _notifyMessage(doc.id, lastSender, lastMessage);
        }
      }
    });
  }

  Future<void> _notifyMessage(String chatRoomId, String senderId, String messageText) async {
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final senderUser = await userRepo.getUser(senderId);
      
      String displayMessage = messageText;
      if (displayMessage.startsWith('[IMAGE]:')) displayMessage = '📷 Photo';
      if (displayMessage.startsWith('[FILE]:')) displayMessage = '📄 File';
      if (displayMessage.startsWith('[VIDEO]:')) displayMessage = '🎥 Video';
      if (displayMessage.startsWith('[AUDIO]:')) displayMessage = '🎵 Voice Note';

      NotificationService.showNotification(
        id: chatRoomId.hashCode,
        title: senderUser.name,
        body: displayMessage,
      );

      if (mounted) {
        InAppNotificationManager.show(
          context: context,
          title: senderUser.name,
          body: displayMessage,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  receiverId: senderUser.id,
                  receiverName: senderUser.name,
                  isGroup: false,
                ),
              ),
            );
          },
        );
      }
    } catch (_) {}
  }

  void _listenToGroupRequests() {
    _groupRequestsSub = FirebaseFirestore.instance
        .collection('groups')
        .where('createdBy', isEqualTo: widget.currentUser.id)
        .snapshots()
        .listen((snapshot) {
      int count = 0;
      final newNotified = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final groupName = data['name'] ?? 'Group';
        final pending = List<String>.from(data['pendingMembers'] ?? []);
        count += pending.length;

        for (final uid in pending) {
          final reqKey = '${doc.id}_$uid';
          newNotified.add(reqKey);

          // Notify for every key not in the previous snapshot,
          // but skip on the very first snapshot (initial load).
          if (!_isRequestsInitialLoad && !_notifiedRequests.contains(reqKey) && mounted) {
            _notifyNewRequest(groupName);
          }
        }
      }

      if (mounted) {
        setState(() {
          _pendingRequestsCount = count;
          _notifiedRequests = newNotified;
          _isRequestsInitialLoad = false;
        });
      }
    });
  }

  void _notifyNewRequest(String groupName) {
    NotificationService.showNotification(
      id: groupName.hashCode,
      title: 'New Join Request',
      body: 'Someone requested to join your study group: $groupName',
    );
    if (mounted) {
      InAppNotificationManager.show(
        context: context,
        title: 'New Join Request',
        body: 'Someone requested to join your study group: $groupName',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GroupRequestsScreen()),
          );
        },
      );
    }
  }

  void _showIncomingCallOverlay(String callId, Map<String, dynamic> data) {
    setState(() {
      _isCallDialogShowing = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingCallDialog(callId: callId, data: data),
    ).then((_) {
      if (mounted) {
        setState(() {
          _isCallDialogShowing = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _pendingRequestsCount > 0 ? Icons.notifications_active : Icons.notifications_none,
                  color: _pendingRequestsCount > 0 ? Colors.orange : Colors.grey.shade400,
                ),
                if (_pendingRequestsCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        '$_pendingRequestsCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GroupRequestsScreen(),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8.0),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(user: widget.currentUser, isOwnProfile: true),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(
                  widget.currentUser.profileImage.isNotEmpty
                      ? widget.currentUser.profileImage
                      : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
                ),
              ),
            ),
          ),
        ],
      ),
      body: RadialBackground(
        child: IndexedStack(
          index: _currentIndex,
          children: _tabs,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (idx) => setState(() => _currentIndex = idx),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primaryBlue,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'Partners',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.group_work_outlined),
              activeIcon: Icon(Icons.group_work),
              label: 'Groups',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.alarm_on_outlined),
              activeIcon: Icon(Icons.alarm_on),
              label: 'Sessions',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.folder_open_outlined),
              activeIcon: Icon(Icons.folder_open),
              label: 'Notes',
            ),
          ],
        ),
      ),
    );
  }
}

class IncomingCallDialog extends StatefulWidget {
  final String callId;
  final Map<String, dynamic> data;

  const IncomingCallDialog({super.key, required this.callId, required this.data});

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog> {
  StreamSubscription? _callSub;
  late final AudioPlayer _audioPlayer;
  bool _actionTaken = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    
    // Set audio context to force output to speaker or appropriate channels (fixes routing volume issues)
    try {
      final playerContext = AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      );
      _audioPlayer.setAudioContext(playerContext);
    } catch (_) {}

    // Play ringing sound on loop (using a verified working public domain sample URL)
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    try {
      _audioPlayer.play(UrlSource('https://samplelib.com/mp3/sample-9s.mp3'));
    } catch (_) {}

    // Listen to call doc changes
    _callSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snapshot) {
      if (_actionTaken) return;
      if (!snapshot.exists) {
        if (mounted) {
          _actionTaken = true;
          _callSub?.cancel();
          Navigator.of(context).pop();
        }
        return;
      }
      final status = snapshot.data()?['status'];
      if (status != 'ringing') {
        if (mounted) {
          _actionTaken = true;
          _callSub?.cancel();
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _declineCall() async {
    if (_actionTaken) return;
    _actionTaken = true;
    await _callSub?.cancel();

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .update({'status': 'rejected'});

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _acceptCall() async {
    if (_actionTaken) return;
    _actionTaken = true;
    await _callSub?.cancel();

    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .update({'status': 'connected'});
    
    if (mounted) {
      Navigator.of(context).pop(); // Dismiss incoming dialog
      
      // Navigate to CallScreen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            receiverName: widget.data['callerName'] ?? 'Student',
            receiverId: widget.data['callerId'] ?? '',
            isVideo: widget.data['isVideo'] ?? false,
            callId: widget.callId,
            isReceiver: true,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.data['isVideo'] == true;
    final callerName = widget.data['callerName'] ?? 'Unknown';

    return PopScope(
      canPop: false, // Prevent back button dismissal
      child: Dialog(
        backgroundColor: const Color(0xFF1E293B), // Slate 800
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isVideo ? 'INCOMING VIDEO CALL' : 'INCOMING VOICE CALL',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 48,
                backgroundColor: AppTheme.primaryBlue,
                child: Text(
                  callerName.isNotEmpty ? callerName[0].toUpperCase() : 'S',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                callerName,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ringing...',
                style: TextStyle(color: AppTheme.secondaryTeal, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline Button (Red)
                  Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                        child: IconButton(
                          iconSize: 28,
                          icon: const Icon(Icons.call_end, color: Colors.white),
                          onPressed: _declineCall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  // Accept Button (Green)
                  Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                        child: IconButton(
                          iconSize: 28,
                          icon: const Icon(Icons.call, color: Colors.white),
                          onPressed: _acceptCall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('Accept', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
