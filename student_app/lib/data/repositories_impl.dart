import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../domain/repositories.dart';

// ==========================================
// IN-MEMORY MOCK DATABASE
// ==========================================
class MockDatabase {
  static final MockDatabase instance = MockDatabase._();
  MockDatabase._() { _initMockData(); }

  UserModel? currentUser;
  final List<UserModel> users = [];
  final List<GroupModel> groups = [];
  final List<SessionModel> sessions = [];
  final List<MessageModel> messages = [];
  final List<NoteModel> notes = [];
  final List<ReportModel> reports = [];

  final _authStreamController = StreamController<UserModel?>.broadcast();
  final _messageStreamControllers = <String, StreamController<List<MessageModel>>>{};

  void _initMockData() {
    Timer.run(() => _authStreamController.add(currentUser));
    // No seed data — mock database starts empty.
  }

  void notifyMessageListeners(String chatRoomId) {
    if (_messageStreamControllers.containsKey(chatRoomId)) {
      final msgs = messages.where((m) => m.receiverId == chatRoomId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _messageStreamControllers[chatRoomId]!.add(msgs);
    }
  }

  Stream<List<MessageModel>> getMessagesStream(String chatRoomId) {
    final controller = _messageStreamControllers.putIfAbsent(
      chatRoomId, () => StreamController<List<MessageModel>>.broadcast());
    final msgs = messages.where((m) => m.receiverId == chatRoomId).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    Timer.run(() => controller.add(msgs));
    return controller.stream;
  }
}

// ==========================================
// MOCK REPOSITORIES
// ==========================================
class MockAuthRepository implements AuthRepository {
  final _db = MockDatabase.instance;
  @override
  Stream<UserModel?> get onAuthStateChanged => _db._authStreamController.stream;
  @override
  UserModel? get currentUser => _db.currentUser;
  @override
  Future<UserModel> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final user = _db.users.firstWhere(
      (u) => u.email.toLowerCase() == email.toLowerCase(),
      orElse: () => throw Exception('User not found'),
    );
    _db.currentUser = user;
    _db._authStreamController.add(user);
    return user;
  }
  @override
  Future<UserModel> register(String email, String password, String name) async {
    await Future.delayed(const Duration(milliseconds: 800));
    final u = UserModel(
      id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email,
      university: '',
      semester: '',
      subjects: [],
      profileImage: '',
      studyGoals: '',
      availability: '',
    );
    _db.users.add(u);
    _db.currentUser = u;
    _db._authStreamController.add(u);
    return u;
  }
  @override Future<void> logout() async { _db.currentUser = null; _db._authStreamController.add(null); }
  @override Future<void> sendPasswordResetEmail(String email) async {}
  @override Future<void> verifyEmail() async {}
}

class MockUserRepository implements UserRepository {
  final _db = MockDatabase.instance;
  @override Future<UserModel> getUser(String id) async =>
    _db.users.firstWhere((u) => u.id == id, orElse: () => throw Exception('Not found'));
  @override Future<void> updateUser(UserModel user) async {
    final idx = _db.users.indexWhere((u) => u.id == user.id);
    if (idx != -1) {
      _db.users[idx] = user;
    } else {
      _db.users.add(user);
    }
    if (_db.currentUser?.id == user.id) { _db.currentUser = user; _db._authStreamController.add(user); }
  }
  @override Future<List<UserModel>> searchUsers({String? query, String? semester, String? subject}) async {
    Iterable<UserModel> r = _db.users.where((u) => u.id != _db.currentUser?.id);
    if (query?.isNotEmpty == true) r = r.where((u) => u.name.toLowerCase().contains(query!.toLowerCase()));
    if (semester?.isNotEmpty == true) r = r.where((u) => u.semester == semester);
    if (subject?.isNotEmpty == true) r = r.where((u) => u.subjects.any((s) => s.toLowerCase().contains(subject!.toLowerCase())));
    return r.toList();
  }
  @override Future<List<UserModel>> getMatchingPartners(UserModel user) async {
    final cs = user.subjects.map((s) => s.toLowerCase()).toSet();
    final list = _db.users.where((u) => u.id != user.id).toList();
    list.sort((a, b) => b.subjects.map((s) => s.toLowerCase()).toSet().intersection(cs).length
      .compareTo(a.subjects.map((s) => s.toLowerCase()).toSet().intersection(cs).length));
    return list;
  }
}

class MockGroupRepository implements GroupRepository {
  final _db = MockDatabase.instance;
  @override Future<GroupModel> createGroup(GroupModel group) async {
    final g = group.copyWith(id: 'group_${DateTime.now().millisecondsSinceEpoch}');
    _db.groups.add(g); return g;
  }
  @override Future<List<GroupModel>> getGroups({String? subject}) async =>
    subject?.isNotEmpty == true ? _db.groups.where((g) => g.subject.toLowerCase().contains(subject!.toLowerCase())).toList() : _db.groups;
  @override Future<GroupModel> getGroupById(String id) async =>
    _db.groups.firstWhere((g) => g.id == id, orElse: () => throw Exception('Not found'));
  @override Future<void> joinGroup(String groupId, String userId) async {
    final idx = _db.groups.indexWhere((g) => g.id == groupId);
    if (idx != -1 && !_db.groups[idx].members.contains(userId)) {
      _db.groups[idx] = _db.groups[idx].copyWith(members: [..._db.groups[idx].members, userId]);
    }
  }
  @override Future<void> leaveGroup(String groupId, String userId) async {
    final idx = _db.groups.indexWhere((g) => g.id == groupId);
    if (idx != -1) {
      _db.groups[idx] = _db.groups[idx].copyWith(
        members: List<String>.from(_db.groups[idx].members)..remove(userId));
    }
  }
  @override Future<List<UserModel>> getGroupMembers(String groupId) async {
    final g = await getGroupById(groupId);
    return _db.users.where((u) => g.members.contains(u.id)).toList();
  }
  // Approval (mock: auto-approve)
  @override Future<void> requestJoin(String groupId, String userId) => joinGroup(groupId, userId);
  @override Future<void> approveJoin(String groupId, String userId) => joinGroup(groupId, userId);
  @override Future<void> rejectJoin(String groupId, String userId) async {}
  @override Future<void> deleteGroup(String groupId) async {
    _db.groups.removeWhere((g) => g.id == groupId);
  }
}

class MockSessionRepository implements SessionRepository {
  final _db = MockDatabase.instance;
  @override Future<SessionModel> createSession(SessionModel session) async {
    final s = session.copyWith(id: 'session_${DateTime.now().millisecondsSinceEpoch}');
    _db.sessions.add(s); return s;
  }
  @override Future<List<SessionModel>> getSessions({String? subject}) async =>
    subject?.isNotEmpty == true ? _db.sessions.where((s) => s.subject.toLowerCase().contains(subject!.toLowerCase())).toList() : _db.sessions;
  @override Future<void> joinSession(String sessionId, String userId) async {
    final idx = _db.sessions.indexWhere((s) => s.id == sessionId);
    if (idx != -1 && !_db.sessions[idx].participants.contains(userId)) {
      _db.sessions[idx] = _db.sessions[idx].copyWith(participants: [..._db.sessions[idx].participants, userId]);
    }
  }
  @override Future<List<UserModel>> getSessionParticipants(String sessionId) async {
    final s = _db.sessions.firstWhere((s) => s.id == sessionId);
    return _db.users.where((u) => s.participants.contains(u.id)).toList();
  }
}

class MockChatRepository implements ChatRepository {
  final _db = MockDatabase.instance;
  @override Stream<List<MessageModel>> getMessages(String chatRoomId) => _db.getMessagesStream(chatRoomId);
  @override Future<void> sendMessage(MessageModel message) async {
    final m = message.copyWith(id: 'msg_${DateTime.now().millisecondsSinceEpoch}');
    _db.messages.add(m); _db.notifyMessageListeners(message.receiverId);
  }
  @override Future<void> deleteMessage(String chatRoomId, String messageId) async {
    _db.messages.removeWhere((m) => m.id == messageId);
    _db.notifyMessageListeners(chatRoomId);
  }

  @override Future<void> deleteMessageForMe(String chatRoomId, String messageId, String userId) async {
    final idx = _db.messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final m = _db.messages[idx];
      _db.messages[idx] = m.copyWith(deletedFor: [...m.deletedFor, userId]);
      _db.notifyMessageListeners(chatRoomId);
    }
  }
}

class MockNoteRepository implements NoteRepository {
  final _db = MockDatabase.instance;
  @override Future<NoteModel> uploadNote(NoteModel note) async {
    final n = note.copyWith(id: 'note_${DateTime.now().millisecondsSinceEpoch}');
    _db.notes.add(n); return n;
  }
  @override Future<List<NoteModel>> getNotes({String? subject, String? semester, String? query}) async {
    Iterable<NoteModel> r = _db.notes;
    if (subject?.isNotEmpty == true) r = r.where((n) => n.subject.toLowerCase() == subject!.toLowerCase());
    if (semester?.isNotEmpty == true) r = r.where((n) => n.semester.toLowerCase() == semester!.toLowerCase());
    if (query?.isNotEmpty == true) r = r.where((n) => n.title.toLowerCase().contains(query!.toLowerCase()));
    return r.toList();
  }
  @override Future<void> deleteNote(String noteId) async {
    _db.notes.removeWhere((n) => n.id == noteId);
  }
}

class MockReportRepository implements ReportRepository {
  final _db = MockDatabase.instance;
  @override Future<void> submitReport(ReportModel report) async {
    _db.reports.add(report.copyWith(id: 'report_${DateTime.now().millisecondsSinceEpoch}'));
  }
}

// ==========================================
// FIREBASE REPOSITORIES
// ==========================================

// ==========================================
// FIREBASE REPOSITORIES
// ==========================================

class FirebaseAuthRepository implements AuthRepository {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  Stream<UserModel?> get onAuthStateChanged {
    return _auth.authStateChanges().asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;
      try {
        final doc = await _firestore.collection('users').doc(firebaseUser.uid).get();
        if (!doc.exists) {
          return UserModel(id: firebaseUser.uid, name: firebaseUser.displayName ?? '',
            email: firebaseUser.email ?? '', university: '', semester: '', subjects: [],
            profileImage: firebaseUser.photoURL ?? '', studyGoals: '', availability: '');
        }
        // Enforce admin suspension — sign out immediately if suspended
        if (doc.data()?['suspended'] == true) {
          await _auth.signOut();
          return null;
        }
        return UserModel.fromMap(doc.data()!, firebaseUser.uid);
      } catch (_) { return null; }
    });
  }

  @override
  UserModel? get currentUser {
    final u = _auth.currentUser;
    if (u == null) return null;
    return UserModel(id: u.uid, name: u.displayName ?? '', email: u.email ?? '',
      university: '', semester: '', subjects: [], profileImage: u.photoURL ?? '',
      studyGoals: '', availability: '');
  }

  @override
  Future<UserModel> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final doc = await _firestore.collection('users').doc(cred.user!.uid).get();

      // Enforce admin suspension — block login if suspended
      if (doc.exists && doc.data()?['suspended'] == true) {
        await _auth.signOut();
        throw Exception('Your account has been suspended. Please contact support.');
      }

      if (doc.exists) return UserModel.fromMap(doc.data()!, cred.user!.uid);
      return UserModel(id: cred.user!.uid, name: cred.user!.displayName ?? email.split('@').first,
        email: email, university: '', semester: '', subjects: [],
        profileImage: cred.user!.photoURL ?? '', studyGoals: '', availability: '');
    } catch (e) {
      if (e is FirebaseAuthException) throw Exception('Auth error: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  @override
  Future<UserModel> register(String email, String password, String name) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await cred.user!.updateDisplayName(name);
      final user = UserModel(id: cred.user!.uid, name: name, email: email,
        university: '', semester: '', subjects: [], profileImage: '', studyGoals: '', availability: '');
      await _firestore.collection('users').doc(user.id).set(user.toMap());
      return user;
    } catch (e) {
      if (e is FirebaseAuthException) throw Exception('Auth error: ${e.code} - ${e.message}');
      throw Exception('Register failed: $e');
    }
  }

  @override Future<void> logout() async => _auth.signOut();
  @override Future<void> sendPasswordResetEmail(String email) async => _auth.sendPasswordResetEmail(email: email);
  @override Future<void> verifyEmail() async => _auth.currentUser?.sendEmailVerification();
}

class FirebaseUserRepository implements UserRepository {
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<UserModel> getUser(String id) async {
    final doc = await _firestore.collection('users').doc(id).get();
    if (!doc.exists) throw Exception('User not found');
    return UserModel.fromMap(doc.data()!, id);
  }

  @override
  Future<void> updateUser(UserModel user) async =>
    _firestore.collection('users').doc(user.id).set(user.toMap());

  @override
  Future<List<UserModel>> searchUsers({String? query, String? semester, String? subject}) async {
    Query q = _firestore.collection('users');
    if (semester?.isNotEmpty == true) q = q.where('semester', isEqualTo: semester);
    final snap = await q.get();
    Iterable<UserModel> results = snap.docs.map((d) => UserModel.fromMap(d.data() as Map<String, dynamic>, d.id));
    if (query?.isNotEmpty == true) results = results.where((u) => u.name.toLowerCase().contains(query!.toLowerCase()) || u.university.toLowerCase().contains(query.toLowerCase()));
    if (subject?.isNotEmpty == true) results = results.where((u) => u.subjects.any((s) => s.toLowerCase().contains(subject!.toLowerCase())));
    return results.toList();
  }

  @override
  Future<List<UserModel>> getMatchingPartners(UserModel user) async {
    final snap = await _firestore.collection('users').get();
    final list = snap.docs.map((d) => UserModel.fromMap(d.data(), d.id)).where((u) => u.id != user.id).toList();
    final cs = user.subjects.map((s) => s.toLowerCase()).toSet();
    list.sort((a, b) => b.subjects.map((s) => s.toLowerCase()).toSet().intersection(cs).length
      .compareTo(a.subjects.map((s) => s.toLowerCase()).toSet().intersection(cs).length));
    return list;
  }
}

class FirebaseGroupRepository implements GroupRepository {
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<GroupModel> createGroup(GroupModel group) async {
    final ref = _firestore.collection('groups').doc();
    final newGroup = group.copyWith(id: ref.id);
    await ref.set(newGroup.toMap());
    return newGroup;
  }

  // Real-time stream for groups
  Stream<List<GroupModel>> getGroupsStream() {
    return _firestore.collection('groups').snapshots().map((snap) =>
      snap.docs.map((d) => GroupModel.fromMap(d.data(), d.id)).toList());
  }

  @override
  Future<List<GroupModel>> getGroups({String? subject}) async {
    Query q = _firestore.collection('groups');
    if (subject?.isNotEmpty == true) q = q.where('subject', isEqualTo: subject);
    final snap = await q.get();
    return snap.docs.map((d) => GroupModel.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
  }

  @override
  Future<GroupModel> getGroupById(String id) async {
    final doc = await _firestore.collection('groups').doc(id).get();
    if (!doc.exists) throw Exception('Group not found');
    return GroupModel.fromMap(doc.data()!, id);
  }

  // Request to join — adds to pendingMembers list, NOT members
  @override
  Future<void> requestJoin(String groupId, String userId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'pendingMembers': FieldValue.arrayUnion([userId])
    });
  }

  // Admin approves join request
  @override
  Future<void> approveJoin(String groupId, String userId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([userId]),
      'pendingMembers': FieldValue.arrayRemove([userId]),
    });
  }

  // Admin rejects join request
  @override
  Future<void> rejectJoin(String groupId, String userId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'pendingMembers': FieldValue.arrayRemove([userId]),
    });
  }

  @override
  Future<void> joinGroup(String groupId, String userId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([userId])
    });
  }

  @override
  Future<void> leaveGroup(String groupId, String userId) async {
    await _firestore.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([userId])
    });
  }

  @override
  Future<List<UserModel>> getGroupMembers(String groupId) async {
    final grp = await getGroupById(groupId);
    if (grp.members.isEmpty) return [];
    final snap = await _firestore.collection('users').where(FieldPath.documentId, whereIn: grp.members).get();
    return snap.docs.map((d) => UserModel.fromMap(d.data(), d.id)).toList();
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await _firestore.collection('groups').doc(groupId).delete();
  }
}

class FirebaseSessionRepository implements SessionRepository {
  final _firestore = FirebaseFirestore.instance;

  // Real-time stream for sessions
  Stream<List<SessionModel>> getSessionsStream() {
    return _firestore.collection('sessions').snapshots().map((snap) =>
      snap.docs.map((d) => SessionModel.fromMap(d.data(), d.id)).toList());
  }

  @override
  Future<SessionModel> createSession(SessionModel session) async {
    final ref = _firestore.collection('sessions').doc();
    final newSession = session.copyWith(id: ref.id);
    await ref.set(newSession.toMap());
    return newSession;
  }

  @override
  Future<List<SessionModel>> getSessions({String? subject}) async {
    Query q = _firestore.collection('sessions');
    if (subject?.isNotEmpty == true) q = q.where('subject', isEqualTo: subject);
    final snap = await q.get();
    return snap.docs.map((d) => SessionModel.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
  }

  @override
  Future<void> joinSession(String sessionId, String userId) async {
    await _firestore.collection('sessions').doc(sessionId).update({
      'participants': FieldValue.arrayUnion([userId])
    });
  }

  @override
  Future<List<UserModel>> getSessionParticipants(String sessionId) async {
    final doc = await _firestore.collection('sessions').doc(sessionId).get();
    final sess = SessionModel.fromMap(doc.data()!, sessionId);
    if (sess.participants.isEmpty) return [];
    final snap = await _firestore.collection('users').where(FieldPath.documentId, whereIn: sess.participants).get();
    return snap.docs.map((d) => UserModel.fromMap(d.data(), d.id)).toList();
  }
}

class FirebaseChatRepository implements ChatRepository {
  final _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<MessageModel>> getMessages(String chatRoomId) {
    return _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MessageModel.fromMap(d.data(), d.id)).toList());
  }

  @override
  Future<void> sendMessage(MessageModel message) async {
    final chatRoomId = message.receiverId;
    final messagesRef = _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc();
    
    final batch = _firestore.batch();
    
    // 1. Add the message document
    final newMsg = message.copyWith(id: messagesRef.id);
    batch.set(messagesRef, newMsg.toMap());
    
    // 2. Update parent chat room document metadata
    final chatRoomRef = _firestore.collection('chats').doc(chatRoomId);
    
    final isGroup = !chatRoomId.contains('_');
    final Map<String, dynamic> updateData = {
      'lastMessage': message.message,
      'lastMessageTimestamp': message.timestamp.toIso8601String(),
      'lastMessageSenderId': message.senderId,
    };
    
    if (!isGroup) {
      final participants = chatRoomId.split('_');
      final otherUserId = participants.firstWhere((id) => id != message.senderId, orElse: () => '');
      updateData['participants'] = participants;
      if (otherUserId.isNotEmpty) {
        updateData['unread_$otherUserId'] = FieldValue.increment(1);
      }
    } else {
      updateData['participants'] = FieldValue.arrayUnion([message.senderId]);
      updateData['isGroup'] = true;
    }
    
    batch.set(chatRoomRef, updateData, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<void> deleteMessage(String chatRoomId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  @override
  Future<void> deleteMessageForMe(String chatRoomId, String messageId, String userId) async {
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId)
        .update({
      'deletedFor': FieldValue.arrayUnion([userId]),
    });
  }
}

class FirebaseNoteRepository implements NoteRepository {
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<NoteModel> uploadNote(NoteModel note) async {
    final ref = _firestore.collection('notes').doc();
    final newNote = note.copyWith(id: ref.id);
    await ref.set(newNote.toMap());
    return newNote;
  }

  @override
  Future<List<NoteModel>> getNotes({String? subject, String? semester, String? query}) async {
    Query q = _firestore.collection('notes');
    if (subject?.isNotEmpty == true) q = q.where('subject', isEqualTo: subject);
    if (semester?.isNotEmpty == true) q = q.where('semester', isEqualTo: semester);
    final snap = await q.get();
    Iterable<NoteModel> results = snap.docs.map((d) => NoteModel.fromMap(d.data() as Map<String, dynamic>, d.id));
    if (query?.isNotEmpty == true) results = results.where((n) => n.title.toLowerCase().contains(query!.toLowerCase()));
    return results.toList();
  }

  @override
  Future<void> deleteNote(String noteId) async {
    await _firestore.collection('notes').doc(noteId).delete();
  }
}

class FirebaseReportRepository implements ReportRepository {
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<void> submitReport(ReportModel report) async {
    final ref = _firestore.collection('reports').doc();
    await ref.set(report.copyWith(id: ref.id).toMap());
  }
}