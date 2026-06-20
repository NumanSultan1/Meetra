import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import '../core/providers.dart';
import '../core/theme.dart';
import '../core/cloudinary_service.dart';
import 'call_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String receiverId; // for DM: other userId | for group: groupId
  final String receiverName;
  final bool isGroup;

  static String? activeChatRoomId;

  const ChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
    required this.isGroup,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  bool _isUploading = false;
  bool _isTextEmpty = true;

  // Multi-message selection state
  final Set<String> _selectedMessageIds = {};
  final List<MessageModel> _selectedMessages = [];

  // Real voice recording state
  late final AudioRecorder _audioRecorder;
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Emoji picker state
  bool _showEmojiPicker = false;

  // Chat room ID: for DM = sorted userIds, for group = groupId
  late String _chatRoomId;
  late String _currentUserId;

  // Stable stream of messages and scroll tracker to prevent layout jumping
  late final Stream<List<MessageModel>> _messagesStream;
  String? _lastMessageId;
  StreamSubscription<List<MessageModel>>? _messagesSub;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _currentUserId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
    if (widget.isGroup) {
      _chatRoomId = widget.receiverId;
    } else {
      final ids = [_currentUserId, widget.receiverId]..sort();
      _chatRoomId = '${ids[0]}_${ids[1]}';
    }

    ChatScreen.activeChatRoomId = _chatRoomId;
    _resetUnreadCount();

    _messagesStream = ref.read(chatRepositoryProvider).getMessages(_chatRoomId);

    _messagesSub = _messagesStream.listen((msgs) {
      if (msgs.isNotEmpty) {
        final lastMsg = msgs.last;
        if (lastMsg.senderId != _currentUserId) {
          _resetUnreadCount();
        }
      }
    });

    _messageController.addListener(() {
      final val = _messageController.text.trim().isEmpty;
      if (val != _isTextEmpty) {
        setState(() {
          _isTextEmpty = val;
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _messagesSub?.cancel();
    if (ChatScreen.activeChatRoomId == _chatRoomId) {
      ChatScreen.activeChatRoomId = null;
    }
    super.dispose();
  }

  Future<void> _resetUnreadCount() async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(_chatRoomId).set(
        {'unread_$_currentUserId': 0},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    // Unfocus text field and close emoji picker to ensure clean state before recording starts
    FocusScope.of(context).unfocus();
    setState(() {
      _showEmojiPicker = false;
    });

    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

        // Start recording
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordingSeconds++;
          });
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission is required to record voice notes.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
    });
  }

  Future<void> _sendVoiceMessage() async {
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      _isUploading = true;
    });

    try {
      final path = await _audioRecorder.stop();
      if (path == null) {
        throw Exception('Audio recording stopped, but path was null');
      }

      final file = File(path);
      if (!await file.exists()) {
        throw Exception('Recorded audio file not found');
      }

      final fileName = path.split(RegExp(r'[/\\]')).last;
      // Upload audio file as raw file to Cloudinary
      final downloadUrl = await CloudinaryService.uploadFile(file, fileName);

      await _sendMessage(fileUrl: downloadUrl, fileType: 'AUDIO');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload/send voice message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _sendMessage({
    String? text,
    String? fileUrl,
    String? fileType,
  }) async {
    final content = text ?? fileUrl ?? '';
    if (content.isEmpty) return;

    setState(() => _isSending = true);
    try {
      final message = MessageModel(
        id: '',
        senderId: _currentUserId,
        receiverId: _chatRoomId,
        message: fileUrl != null ? '[$fileType]: $fileUrl' : content,
        timestamp: DateTime.now(),
      );
      await ref.read(chatRepositoryProvider).sendMessage(message);
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    XFile? picked;
    if (kIsWeb) {
      picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } else {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      picked = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    }
    if (picked == null) return;

    setState(() => _isUploading = true);
    try {
      String url;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        url = await CloudinaryService.uploadImage(bytes);
      } else {
        url = await CloudinaryService.uploadImage(File(picked.path));
      }
      final ext = picked.path.split('.').last.toLowerCase();
      url = '$url#ext=$ext';
      await _sendMessage(fileUrl: url, fileType: 'IMAGE');
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    setState(() => _isUploading = true);
    try {
      String url;
      if (kIsWeb) {
        url = await CloudinaryService.uploadFile(file.bytes!, file.name);
      } else {
        url = await CloudinaryService.uploadFile(File(file.path!), file.name);
      }
      final ext = file.name.split('.').last.toLowerCase();
      url = '$url#ext=$ext';
      String fileType = 'FILE';
      if (['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'].contains(ext)) {
        fileType = 'VIDEO';
      } else if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
        fileType = 'IMAGE';
      }
      await _sendMessage(fileUrl: url, fileType: fileType);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('File upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Get sender user from Firestore cache
  Future<UserModel?> _getSenderUser(String senderId) async {
    try {
      final user = await ref.read(userRepositoryProvider).getUser(senderId);
      return user;
    } catch (_) {
      return null;
    }
  }

  // Message multi-selection actions
  void _toggleMessageSelection(MessageModel m) {
    setState(() {
      if (_selectedMessageIds.contains(m.id)) {
        _selectedMessageIds.remove(m.id);
        _selectedMessages.removeWhere((msg) => msg.id == m.id);
      } else {
        _selectedMessageIds.add(m.id);
        _selectedMessages.add(m);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMessageIds.clear();
      _selectedMessages.clear();
    });
  }

  Future<void> _deleteSelectedMessages() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Message(s)?'),
        content: Text(
          'Are you sure you want to delete ${_selectedMessageIds.length} message(s)? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final msgsToDelete = List<MessageModel>.from(_selectedMessages);
    _clearSelection();

    try {
      for (final m in msgsToDelete) {
        if (m.senderId == _currentUserId) {
          // Hard delete for everyone if I am the sender
          await ref
              .read(chatRepositoryProvider)
              .deleteMessage(_chatRoomId, m.id);
        } else {
          // Soft delete for me if I am the receiver
          await ref
              .read(chatRepositoryProvider)
              .deleteMessageForMe(_chatRoomId, m.id, _currentUserId);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message(s) deleted successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  void _copySelectedMessages() {
    final buffer = StringBuffer();
    for (final m in _selectedMessages) {
      String cleanMsg = m.message;
      if (cleanMsg.startsWith('[IMAGE]:')) cleanMsg = '[Photo]';
      if (cleanMsg.startsWith('[FILE]:')) cleanMsg = '[File]';
      if (cleanMsg.startsWith('[VIDEO]:')) cleanMsg = '[Video]';
      if (cleanMsg.startsWith('[AUDIO]:')) cleanMsg = '[Voice Note]';
      buffer.writeln(cleanMsg);
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messages copied to clipboard.')),
    );
  }

  void _shareSelectedMessages() {
    if (_selectedMessages.isEmpty) return;
    _showForwardingSheet();
  }

  void _showForwardingSheet() {
    final messagesToForward = List<MessageModel>.from(_selectedMessages);
    _clearSelection();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                'Forward to...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder(
                  future: Future.wait([
                    FirebaseFirestore.instance.collection('users').get(),
                    FirebaseFirestore.instance.collection('groups').where('members', arrayContains: _currentUserId).get(),
                  ]),
                  builder: (ctx, AsyncSnapshot<List<QuerySnapshot>> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: Text('Error loading contacts'));
                    }

                    final userDocs = snapshot.data![0].docs;
                    final groupDocs = snapshot.data![1].docs;

                    final users = userDocs.map((d) => UserModel.fromMap(d.data() as Map<String, dynamic>, d.id)).where((u) => u.id != _currentUserId).toList();
                    final groups = groupDocs.map((d) => GroupModel.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();

                    final items = [...groups, ...users];

                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        String title;
                        String subtitle;
                        IconData icon;
                        bool isGroup = false;
                        String itemId;

                        if (item is GroupModel) {
                          title = item.name;
                          subtitle = '${item.members.length} members';
                          icon = Icons.group;
                          isGroup = true;
                          itemId = item.id;
                        } else if (item is UserModel) {
                          title = item.name;
                          subtitle = item.email;
                          icon = Icons.person;
                          itemId = item.id;
                        } else {
                          return const SizedBox();
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            child: Icon(icon, color: AppTheme.primaryBlue),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.send, color: AppTheme.primaryBlue),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _forwardMessages(messagesToForward, itemId, isGroup);
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _forwardMessages(List<MessageModel> msgs, String targetId, bool isGroup) async {
    final chatRepo = ref.read(chatRepositoryProvider);

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Forwarding messages...')));
    
    // Sort original messages by timestamp so they appear in correct order
    msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (final m in msgs) {
      final newMessage = MessageModel(
        id: FirebaseFirestore.instance.collection('chats').doc().id,
        senderId: _currentUserId,
        receiverId: targetId,
        message: m.message,
        timestamp: DateTime.now(),
      );
      await chatRepo.sendMessage(newMessage);
      // add slight delay to preserve ordering
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messages forwarded successfully!')));
    }
  }

  Future<void> _navigateToCallScreen(bool isVideo) async {
    try {
      final callRef = FirebaseFirestore.instance.collection('calls').doc();
      await callRef.set({
        'id': callRef.id,
        'callerId': _currentUserId,
        'callerName':
            ref.read(authRepositoryProvider).currentUser?.name ?? 'Student',
        'receiverId': widget.receiverId,
        'isVideo': isVideo,
        'status': 'ringing',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              receiverName: widget.receiverName,
              receiverId: widget.receiverId,
              isVideo: isVideo,
              callId: callRef.id,
              isReceiver: false,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to initiate call: $e')));
      }
    }
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (selection.start == -1 || selection.end == -1) {
      _messageController.text = text + emoji;
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
      return;
    }
    final newText = text.replaceRange(selection.start, selection.end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + emoji.length,
      ),
    );
  }

  Widget _buildEmojiPicker() {
    final emojis = [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '😂',
      '🤣',
      '😊',
      '😇',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😝',
      '😜',
      '🤪',
      '🤨',
      '🧐',
      '🤓',
      '😎',
      '🤩',
      '🥳',
      '😏',
      '😒',
      '😞',
      '😔',
      '😟',
      '😕',
      '🙁',
      '☹️',
      '😣',
      '😖',
      '😫',
      '😩',
      '🥺',
      '😢',
      '😭',
      '😤',
      '😠',
      '😡',
      '🤬',
      '🤯',
      '👍',
      '👎',
      '👌',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '👇',
      '☝️',
      '✋',
      '🤚',
      '👋',
      '💪',
      '🙏',
      '🤝',
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '📚',
      '📖',
      '✏️',
      '📝',
      '🎓',
      '🏫',
      '🎒',
      '💻',
      '💡',
      '🧠',
      '🎯',
      '🧪',
      '🧬',
      '🔬',
      '🔭',
      '🧮',
      '📅',
      '🗑️',
      '🔔',
      '📢',
    ];

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.emoji_emotions_outlined,
                  size: 18,
                  color: AppTheme.primaryBlue,
                ),
                SizedBox(width: 8),
                Text(
                  'Emojis',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, idx) {
                final emoji = emojis[idx];
                return InkWell(
                  onTap: () => _insertEmoji(emoji),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(
                        fontSize: 26,
                        fontFamily: 'sans-serif',
                        fontFamilyFallback: [
                          'Apple Color Emoji',
                          'Noto Color Emoji',
                          'Segoe UI Emoji',
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = _selectedMessageIds.isNotEmpty;

    return Scaffold(
      appBar: isSelectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: RadialBackground(
        child: Column(
          children: [
            // Upload progress
            if (_isUploading)
              const LinearProgressIndicator(color: AppTheme.primaryBlue),

            // Messages list
            Expanded(
              child: StreamBuilder<List<MessageModel>>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final msgs = (snapshot.data ?? [])
                      .where((m) => !m.deletedFor.contains(_currentUserId))
                      .toList();
                  if (msgs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            '💬',
                            style: TextStyle(
                              fontSize: 48,
                              fontFamily: 'sans-serif',
                              fontFamilyFallback: [
                                'Apple Color Emoji',
                                'Noto Color Emoji',
                                'Segoe UI Emoji',
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No messages yet.\nStart the conversation!',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  // Scroll to bottom only when a new message is received/sent to avoid jump loops during rebuilds
                  final newestId = msgs.last.id;
                  if (_lastMessageId != newestId) {
                    _lastMessageId = newestId;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToBottom(),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: msgs.length,
                    itemBuilder: (context, idx) {
                      final m = msgs[idx];
                      final isMe = m.senderId == _currentUserId;
                      final isSelected = _selectedMessageIds.contains(m.id);
                      return _MessageBubble(
                        message: m,
                        isMe: isMe,
                        isGroup: widget.isGroup,
                        isSelected: isSelected,
                        getSenderUser: _getSenderUser,
                        onLongPress: () => _toggleMessageSelection(m),
                        onTap: () {
                          if (isSelectionMode) {
                            _toggleMessageSelection(m);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),

            // Bottom Input Bar (WhatsApp Layout with smooth transition)
            _buildWhatsAppInputBar(),

            // Emoji Picker Panel (Animated transition)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.fastOutSlowIn,
              height: _showEmojiPicker ? 250 : 0,
              child: _buildEmojiPicker(),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
            child: Text(
              widget.receiverName[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.receiverName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'online',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!widget.isGroup) ...[
          IconButton(
            icon: const Icon(Icons.phone_outlined, color: AppTheme.primaryBlue),
            onPressed: () => _navigateToCallScreen(false),
            tooltip: 'Voice Call',
          ),
          IconButton(
            icon: const Icon(
              Icons.videocam_outlined,
              color: AppTheme.primaryBlue,
            ),
            onPressed: () => _navigateToCallScreen(true),
            tooltip: 'Video Call',
          ),
        ],
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.primaryBlue),
          onSelected: (val) {
            if (val == 'report') {
              if (widget.isGroup) {
                _showReportParticipantDialog(context);
              } else {
                _showReportDialog(context);
              }
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'report', child: Text(widget.isGroup ? 'Report Participant' : 'Report User')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _clearSelection,
      ),
      title: Text(
        '${_selectedMessageIds.length} Selected',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy),
          onPressed: _copySelectedMessages,
          tooltip: 'Copy',
        ),
        IconButton(
          icon: const Icon(Icons.share),
          onPressed: _shareSelectedMessages,
          tooltip: 'Share',
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: _deleteSelectedMessages,
          tooltip: 'Delete',
        ),
        PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'deselect') _clearSelection();
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'deselect',
              child: Text('Cancel Selection'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecordingContents() {
    final durationString =
        '${(_recordingSeconds ~/ 60)}:${(_recordingSeconds % 60).toString().padLeft(2, '0')}';
    return Row(
      key: const ValueKey('recording_contents'),
      children: [
        const SizedBox(width: 16),
        const Icon(Icons.mic, color: Colors.redAccent, size: 22),
        const SizedBox(width: 8),
        const _BlinkingRecordDot(),
        const SizedBox(width: 8),
        Text(
          durationString,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Center(child: _AudioWaveSimulator(isSmall: true)),
        ),
        TextButton(
          onPressed: _cancelRecording,
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildInputContents() {
    return Row(
      key: const ValueKey('input_contents'),
      children: [
        IconButton(
          icon: Icon(
            _showEmojiPicker
                ? Icons.keyboard
                : Icons.sentiment_satisfied_alt_outlined,
            color: Colors.grey[500],
          ),
          onPressed: () {
            setState(() {
              _showEmojiPicker = !_showEmojiPicker;
              if (_showEmojiPicker) {
                FocusScope.of(context).unfocus();
              }
            });
          },
        ),
        Expanded(
          child: TextField(
            controller: _messageController,
            keyboardType: TextInputType.multiline,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'Message',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onTap: () {
              setState(() {
                _showEmojiPicker = false;
              });
            },
          ),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.attach_file, color: Colors.grey[500]),
          onSelected: (val) {
            if (val == 'image') _pickAndSendImage();
            if (val == 'file') _pickAndSendFile();
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'image',
              child: Row(
                children: [
                  Icon(Icons.image, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Photo / Video'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'file',
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('File / Document'),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          icon: Icon(Icons.camera_alt, color: Colors.grey[500]),
          onPressed: _pickAndSendImage,
        ),
      ],
    );
  }

  Widget _buildRightButton() {
    if (_isRecording) {
      return IconButton(
        key: const ValueKey('send_voice_btn'),
        icon: const Icon(Icons.send, color: Colors.white, size: 22),
        onPressed: _sendVoiceMessage,
      );
    }

    if (_isSending) {
      return const Center(
        key: ValueKey('sending_indicator'),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    return IconButton(
      key: const ValueKey('action_btn'),
      icon: Icon(
        _isTextEmpty ? Icons.mic : Icons.send,
        color: Colors.white,
        size: 22,
      ),
      onPressed: _isTextEmpty
          ? _startRecording
          : () => _sendMessage(text: _messageController.text.trim()),
    );
  }

  Widget _buildWhatsAppInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeInOut,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: _isRecording
                        ? _buildRecordingContents()
                        : _buildInputContents(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording
                  ? AppTheme.secondaryTeal
                  : AppTheme.primaryBlue,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _buildRightButton(),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report User'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(hintText: 'Reason for report'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (reasonCtrl.text.isNotEmpty) {
                await ref
                    .read(reportRepositoryProvider)
                    .submitReport(
                      ReportModel(
                        id: '',
                        reportedUser: widget.receiverId,
                        reason: reasonCtrl.text,
                        status: 'pending',
                      ),
                    );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Report submitted.')),
                );
              }
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  void _showReportParticipantDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ReportParticipantDialog(groupId: widget.receiverId),
    );
  }
}

class _BlinkingRecordDot extends StatefulWidget {
  const _BlinkingRecordDot();

  @override
  State<_BlinkingRecordDot> createState() => _BlinkingRecordDotState();
}

class _BlinkingRecordDotState extends State<_BlinkingRecordDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Icon(Icons.circle, color: Colors.red, size: 12),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final bool isSelected;
  final Future<UserModel?> Function(String) getSenderUser;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.isGroup,
    required this.isSelected,
    required this.getSenderUser,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  UserModel? _senderUser;

  // Real Audio player state
  late final AudioPlayer _audioPlayer;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;

  StreamSubscription? _durationSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _playerCompleteSubscription;

  @override
  void initState() {
    super.initState();
    if (!widget.isMe) {
      widget.getSenderUser(widget.message.senderId).then((user) {
        if (mounted) setState(() => _senderUser = user);
      });
    }

    if (_isAudioUrl) {
      _audioPlayer = AudioPlayer();
      _durationSubscription = _audioPlayer.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });
      _positionSubscription = _audioPlayer.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
        state,
      ) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });
      _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    if (_isAudioUrl) {
      _durationSubscription?.cancel();
      _positionSubscription?.cancel();
      _playerStateSubscription?.cancel();
      _playerCompleteSubscription?.cancel();
      _audioPlayer.dispose();
    }
    super.dispose();
  }

  bool get _isImageUrl {
    final msg = widget.message.message;
    return msg.startsWith('[IMAGE]:');
  }

  bool get _isFileUrl {
    final msg = widget.message.message;
    return msg.startsWith('[FILE]:') || msg.startsWith('[VIDEO]:');
  }

  bool get _isAudioUrl {
    final msg = widget.message.message;
    return msg.startsWith('[AUDIO]:');
  }

  bool get _isCallLog {
    final msg = widget.message.message;
    return msg.startsWith('📞') || msg.startsWith('📹');
  }

  String get _extractedUrl {
    final msg = widget.message.message;
    final colonIdx = msg.indexOf(']: ');
    if (colonIdx == -1) return '';
    return msg.substring(colonIdx + 3).trim();
  }

  String get _fileLabel {
    final msg = widget.message.message;
    if (msg.startsWith('[IMAGE]:')) return '🖼 Image';
    if (msg.startsWith('[VIDEO]:')) return '🎥 Video';
    if (msg.startsWith('[FILE]:')) return '📄 File';
    return 'File';
  }

  Future<void> _toggleAudioPlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_position == Duration.zero) {
          await _audioPlayer.play(UrlSource(_extractedUrl));
        } else if (_position >= _duration) {
          await _audioPlayer.seek(Duration.zero);
          await _audioPlayer.play(UrlSource(_extractedUrl));
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Playback failed: $e')));
      }
    }
  }

  Future<void> _cyclePlaybackSpeed() async {
    double newSpeed;
    if (_playbackSpeed == 1.0) {
      newSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      newSpeed = 2.0;
    } else {
      newSpeed = 1.0;
    }

    try {
      await _audioPlayer.setPlaybackRate(newSpeed);
      setState(() {
        _playbackSpeed = newSpeed;
      });
    } catch (_) {}
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final remainingSeconds = d.inSeconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  double get _playbackProgress {
    if (_duration.inMilliseconds == 0) return 0.0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  @override
  Widget build(BuildContext context) {
    final timeString = DateFormat('hh:mm a').format(widget.message.timestamp);

    return GestureDetector(
      onLongPress: widget.onLongPress,
      onTap: widget.onTap,
      child: Container(
        color: widget.isSelected
            ? AppTheme.primaryBlue.withValues(alpha: 0.15)
            : Colors.transparent,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Align(
          alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!widget.isMe) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.grey[300],
                  backgroundImage:
                      _senderUser != null &&
                          _senderUser!.profileImage.isNotEmpty
                      ? NetworkImage(_senderUser!.profileImage)
                      : null,
                  child:
                      _senderUser == null || _senderUser!.profileImage.isEmpty
                      ? const Icon(Icons.person, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: _isAudioUrl
                      ? const EdgeInsets.fromLTRB(8, 8, 12, 6)
                      : const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                  decoration: BoxDecoration(
                    color: widget.isMe
                        ? (widget.isSelected
                              ? AppTheme.primaryBlue.withValues(alpha: 0.8)
                              : AppTheme.primaryBlue)
                        : (widget.isSelected
                              ? Colors.grey[300]
                              : Colors.grey[200]),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: widget.isMe
                          ? const Radius.circular(16)
                          : Radius.zero,
                      bottomRight: widget.isMe
                          ? Radius.zero
                          : const Radius.circular(16),
                    ),
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.isMe &&
                          _senderUser != null &&
                          _senderUser!.name.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _senderUser!.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                        ),

                      if (_isImageUrl) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => FullScreenImageViewer(
                                  imageUrl: _extractedUrl,
                                  title: 'Photo',
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _extractedUrl,
                              width: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Text('Image failed to load'),
                            ),
                          ),
                        ),
                      ] else if (_isFileUrl) ...[
                        GestureDetector(
                          onTap: () {
                            final fileName = _extractedUrl
                                .split('/')
                                .last
                                .split('?')
                                .first;
                            openFilePreview(context, _extractedUrl, fileName);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new,
                                size: 16,
                                color: widget.isMe
                                    ? Colors.white70
                                    : AppTheme.primaryBlue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _fileLabel,
                                style: TextStyle(
                                  color: widget.isMe
                                      ? Colors.white
                                      : AppTheme.primaryBlue,
                                  decoration: TextDecoration.underline,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_isAudioUrl) ...[
                        _buildAudioBubbleLayout(),
                      ] else if (_isCallLog) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.message.message.contains('📹')
                                  ? Icons.videocam
                                  : Icons.phone,
                              color: widget.message.message.contains('Missed')
                                  ? Colors.redAccent
                                  : (widget.isMe
                                        ? Colors.white70
                                        : Colors.black54),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.message.message,
                              style: TextStyle(
                                color: widget.isMe
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          widget.message.message,
                          style: TextStyle(
                            color: widget.isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                            fontFamilyFallback: const [
                              'Apple Color Emoji',
                              'Noto Color Emoji',
                              'Segoe UI Emoji',
                            ],
                          ),
                        ),
                      ],

                      if (!_isAudioUrl) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeString,
                              style: TextStyle(
                                fontSize: 9,
                                color: widget.isMe
                                    ? Colors.white70
                                    : Colors.black54,
                              ),
                            ),
                            if (widget.isMe) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.done_all,
                                size: 12,
                                color: Colors.white70,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildAudioBubbleLayout() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: widget.isMe
                  ? Colors.white24
                  : AppTheme.primaryBlue.withValues(alpha: 0.15),
              child: Icon(
                Icons.person,
                color: widget.isMe ? Colors.white70 : AppTheme.primaryBlue,
                size: 22,
              ),
            ),
            const CircleAvatar(
              radius: 7,
              backgroundColor: AppTheme.secondaryTeal,
              child: Icon(Icons.mic, color: Colors.white, size: 9),
            ),
          ],
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            color: widget.isMe ? Colors.white : AppTheme.primaryBlue,
            size: 26,
          ),
          onPressed: _toggleAudioPlayback,
        ),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Real progress bar with slider representation
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.0,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5.0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 8.0,
                  ),
                  activeTrackColor: widget.isMe
                      ? Colors.white
                      : AppTheme.primaryBlue,
                  inactiveTrackColor: widget.isMe
                      ? Colors.white30
                      : Colors.grey[400],
                  thumbColor: widget.isMe ? Colors.white : AppTheme.primaryBlue,
                ),
                child: Slider(
                  value: _position.inMilliseconds.toDouble().clamp(
                    0.0,
                    _duration.inMilliseconds.toDouble() == 0.0
                        ? 1.0
                        : _duration.inMilliseconds.toDouble(),
                  ),
                  max: _duration.inMilliseconds.toDouble() == 0.0
                      ? 1.0
                      : _duration.inMilliseconds.toDouble(),
                  onChanged: (val) async {
                    await _audioPlayer.seek(
                      Duration(milliseconds: val.toInt()),
                    );
                  },
                ),
              ),
              // Visual mock wave underneath matching player progress
              _AudioWaveSimulator(
                isSmall: false,
                progress: _playbackProgress,
                isMe: widget.isMe,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                    style: TextStyle(
                      fontSize: 9,
                      color: widget.isMe ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        DateFormat('hh:mm a').format(widget.message.timestamp),
                        style: TextStyle(
                          fontSize: 9,
                          color: widget.isMe ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      if (widget.isMe) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.done_all,
                          size: 12,
                          color: AppTheme.secondaryTeal,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: _cyclePlaybackSpeed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: widget.isMe ? Colors.white24 : Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_playbackSpeed.toStringAsFixed(1).replaceAll('.0', '')}x',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: widget.isMe ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioWaveSimulator extends StatelessWidget {
  final bool isSmall;
  final double progress;
  final bool isMe;

  const _AudioWaveSimulator({
    this.isSmall = false,
    this.progress = 0.0,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final waveCount = isSmall ? 8 : 15;
    final waveHeights = [
      8,
      14,
      22,
      12,
      18,
      6,
      26,
      16,
      10,
      24,
      8,
      14,
      18,
      10,
      6,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(waveCount, (index) {
        final double height = waveHeights[index % waveHeights.length]
            .toDouble();
        final threshold = index / waveCount;
        final isPlayed = progress >= threshold;

        return Container(
          width: isSmall ? 2.5 : 3.0,
          height: isSmall ? height * 0.7 : height,
          margin: const EdgeInsets.symmetric(horizontal: 1.0),
          decoration: BoxDecoration(
            color: isPlayed
                ? (isMe ? AppTheme.secondaryTeal : AppTheme.primaryBlue)
                : (isMe ? Colors.white38 : Colors.grey[400]),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ==========================================
// MEDIA PREVIEW & LAUNCHING HELPERS
// ==========================================
Future<void> _showFileOptionsDialog(
  BuildContext context,
  String fileUrl,
  String fileName,
) async {
  final cleanUrl = fileUrl.replaceFirst(RegExp(r'^http://'), 'https://');
  final ext = _extFromUrl(cleanUrl, fileName);

  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  const Color(0xFF1E293B).withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'File Options',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  fileName,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                // Preview Option
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.remove_red_eye_outlined,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  title: const Text(
                    'Preview / Open',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Open locally on your device',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _downloadAndOpenFile(context, cleanUrl, fileName, ext);
                  },
                ),
                const Divider(color: Colors.white12, height: 20),
                // Download Option
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryTeal.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.download_outlined,
                      color: AppTheme.secondaryTeal,
                    ),
                  ),
                  title: const Text(
                    'Download to Device',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Save a permanent copy of the file',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _downloadFileToDevice(context, cleanUrl, fileName);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Directory> getAppDownloadsDirectory() async {
  Directory? dir;
  try {
    if (Platform.isAndroid) {
      dir = await getDownloadsDirectory();
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    }
  } catch (e) {
    debugPrint('Error getting downloads directory: $e');
  }
  dir ??= await getExternalStorageDirectory();
  dir ??= await getApplicationDocumentsDirectory();
  return dir;
}

Future<String> _getUniqueFilePath(
  Directory directory,
  String fileName,
  String ext,
) async {
  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;

  String filePath = '${directory.path}/$baseName.$ext';
  int counter = 1;
  while (await File(filePath).exists()) {
    filePath = '${directory.path}/$baseName ($counter).$ext';
    counter++;
  }
  return filePath;
}

Future<void> _downloadFileToDevice(
  BuildContext context,
  String fileUrl,
  String fileName,
) async {
  final httpsUrl = fileUrl.replaceFirst(RegExp(r'^http://'), 'https://');
  final urlFileName = Uri.parse(httpsUrl).path.split('/').last;
  final ext = _extFromUrl(
    httpsUrl,
    urlFileName.isNotEmpty ? urlFileName : fileName,
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text('Downloading file...'),
          ],
        ),
        duration: Duration(seconds: 15),
      ),
    );
  }

  try {
    final response = await http.get(Uri.parse(httpsUrl).removeFragment());
    if (response.statusCode != 200) {
      if (response.statusCode == 401 && httpsUrl.contains('cloudinary.com')) {
        throw Exception(
          'Cloudinary is blocking PDF downloads (401). Please go to Cloudinary Console -> Settings -> Security -> Restricted media types, and uncheck PDF.',
        );
      }
      throw Exception('Download failed: ${response.statusCode}');
    }

    final downloadsDir = await getAppDownloadsDirectory();
    final safeFileName = fileName.contains('.') ? fileName : '$fileName.$ext';
    final filePath = await _getUniqueFilePath(downloadsDir, safeFileName, ext);

    await File(filePath).writeAsBytes(response.bodyBytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppTheme.secondaryTeal),
              SizedBox(width: 8),
              Text('Download Complete', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'The file has been saved to your device:\n\n${filePath.split('/').last}',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
              ),
              onPressed: () async {
                Navigator.pop(dCtx);
                final result = await OpenFilex.open(filePath);
                if (result.type != ResultType.done && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cannot open file: ${result.message}'),
                    ),
                  );
                }
              },
              child: const Text(
                'Open File',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

void openFilePreview(BuildContext context, String rawUrl, String fileName) {
  // Force https so Android cleartext-traffic policy doesn't block http URLs
  final fileUrl = rawUrl.replaceFirst(RegExp(r'^http://'), 'https://');
  final ext = _extFromUrl(fileUrl, fileName);

  // Images → in-app full-screen viewer directly
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FullScreenImageViewer(imageUrl: fileUrl, title: fileName),
      ),
    );
    return;
  }

  // Everything else → show file options dialog
  _showFileOptionsDialog(context, fileUrl, fileName);
}

Future<void> _downloadAndOpenFile(
  BuildContext context,
  String fileUrl,
  String fileName,
  String ext,
) async {
  if (kIsWeb) {
    try {
      launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
    return;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 12),
            Text('Opening file...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );
  }

  try {
    final response = await http.get(Uri.parse(fileUrl).removeFragment());
    if (response.statusCode != 200) {
      if (response.statusCode == 401 && fileUrl.contains('cloudinary.com')) {
        throw Exception(
          'Cloudinary is blocking PDF downloads (401). Please go to Cloudinary Console -> Settings -> Security -> Restricted media types, and uncheck PDF.',
        );
      }
      throw Exception('Download failed: ${response.statusCode}');
    }
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory();
    }
    baseDir ??= await getTemporaryDirectory();

    final safeFileName = fileName.contains('.') ? fileName : '$fileName.$ext';
    final filePath = '${baseDir.path}/$safeFileName';
    await File(filePath).writeAsBytes(response.bodyBytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Unsupported File',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'No local app found to open this $ext file. Would you like to open it in a web browser?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text(
                'Open Browser',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await launchUrl(
          Uri.parse(fileUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error opening file: $e')));
    }
  }
}

String _extFromUrl(String url, String fileName) {
  // 1. Try fragment parameter first (looks like #ext=pdf)
  try {
    final uri = Uri.parse(url);
    final frag = uri.fragment;
    if (frag.startsWith('ext=')) {
      return frag.substring(4).toLowerCase();
    }
    if (frag.isNotEmpty && !frag.contains('=')) {
      return frag.toLowerCase();
    }
  } catch (_) {}

  // 2. Try query parameter 'ext'
  try {
    final uri = Uri.parse(url);
    final extParam = uri.queryParameters['ext'];
    if (extParam != null && extParam.isNotEmpty) {
      return extParam.toLowerCase();
    }
  } catch (_) {}

  // 3. Try filename parameter
  final nameParts = fileName.split('.');
  if (nameParts.length > 1) {
    final possibleExt = nameParts.last.toLowerCase();
    if (possibleExt.length >= 2 && possibleExt.length <= 5) {
      return possibleExt;
    }
  }

  // 4. Try URL path extension
  try {
    final urlPath = Uri.parse(url).path;
    final pathParts = urlPath.split('.');
    if (pathParts.length > 1)
      return pathParts.last.split('?').first.toLowerCase();
  } catch (_) {}

  return 'bin';
}

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String title;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final uri = Uri.parse(imageUrl);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReportParticipantDialog extends ConsumerStatefulWidget {
  final String groupId;
  const _ReportParticipantDialog({required this.groupId});

  @override
  ConsumerState<_ReportParticipantDialog> createState() => _ReportParticipantDialogState();
}

class _ReportParticipantDialogState extends ConsumerState<_ReportParticipantDialog> {
  final _reasonCtrl = TextEditingController();
  List<UserModel> _members = [];
  UserModel? _selectedUser;
  File? _evidenceFile;
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      final db = FirebaseFirestore.instance;
      final groupDoc = await db.collection('groups').doc(widget.groupId).get();
      if (!groupDoc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final group = GroupModel.fromMap(groupDoc.data()!, groupDoc.id);
      
      final currentUserId = ref.read(authRepositoryProvider).currentUser?.id;
      final memberIds = group.members.where((id) => id != currentUserId).toList();

      List<UserModel> users = [];
      for (final id in memberIds) {
        final userDoc = await db.collection('users').doc(id).get();
        if (userDoc.exists) {
          users.add(UserModel.fromMap(userDoc.data()!, userDoc.id));
        }
      }
      if (mounted) {
        setState(() {
          _members = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _evidenceFile = File(picked.path);
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedUser == null || _reasonCtrl.text.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      String? evidenceUrl;
      if (_evidenceFile != null) {
        evidenceUrl = await CloudinaryService.uploadImage(_evidenceFile!);
      }
      
      final report = ReportModel(
        id: '',
        reportedUser: _selectedUser!.id,
        reportedUserName: _selectedUser!.name,
        reason: _reasonCtrl.text,
        status: 'pending',
        evidenceUrl: evidenceUrl,
      );
      
      await ref.read(reportRepositoryProvider).submitReport(report);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted successfully.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Participant'),
      content: _isLoading 
        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
        : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_members.isEmpty) const Text('No other members found.'),
                if (_members.isNotEmpty) DropdownButtonFormField<UserModel>(
                  decoration: const InputDecoration(labelText: 'Select Participant'),
                  items: _members.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                  onChanged: (val) => setState(() => _selectedUser = val),
                  value: _selectedUser,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(labelText: 'Reason for report', border: OutlineInputBorder()),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(_evidenceFile == null ? 'No evidence attached.' : 'Evidence attached.', style: const TextStyle(fontSize: 12)),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Screenshot'),
                      onPressed: _pickImage,
                    ),
                  ],
                ),
              ],
            ),
          ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (!_isLoading) ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit'),
        ),
      ],
    );
  }
}
