import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_finder_shared/study_finder_shared.dart';

// ─── Auth State Stream ────────────────────────────────────────────────────────

/// Reactive stream of the currently signed-in Firebase user.
final adminAuthStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// ─── Admin Auth Service ───────────────────────────────────────────────────────

class AdminAuthService {
  final _auth = FirebaseAuth.instance;

  Future<void> login(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
}

final adminAuthServiceProvider = Provider<AdminAuthService>(
  (ref) => AdminAuthService(),
);

// ─── Admin Firestore Service ──────────────────────────────────────────────────

class AdminService {
  final _db = FirebaseFirestore.instance;

  // ── Counts ──────────────────────────────────────────────────────────────────

  Future<int> getUserCount() async {
    final snap = await _db.collection('users').count().get();
    return snap.count ?? 0;
  }

  Future<int> getGroupCount() async {
    final snap = await _db.collection('groups').count().get();
    return snap.count ?? 0;
  }

  Future<int> getSessionCount() async {
    final snap = await _db.collection('sessions').count().get();
    return snap.count ?? 0;
  }

  Future<int> getNoteCount() async {
    final snap = await _db.collection('notes').count().get();
    return snap.count ?? 0;
  }

  // ── Reads ───────────────────────────────────────────────────────────────────

  Future<List<UserModel>> getUsers() async {
    final snap = await _db
        .collection('users')
        .orderBy('name')
        .get();
    return snap.docs
        .map((d) => UserModel.fromMap(d.data(), d.id))
        .toList();
  }

  Future<List<GroupModel>> getGroups() async {
    final snap = await _db
        .collection('groups')
        .orderBy('name')
        .get();
    return snap.docs
        .map((d) => GroupModel.fromMap(d.data(), d.id))
        .toList();
  }

  Future<List<ReportModel>> getReports() async {
    final snap = await _db
        .collection('reports')
        .orderBy('status')
        .get();
    return snap.docs
        .map((d) => ReportModel.fromMap(d.data(), d.id))
        .toList();
  }

  Future<List<NoteModel>> getNotes() async {
    final snap = await _db
        .collection('notes')
        .get();
    
    final notes = snap.docs.map((doc) => NoteModel.fromMap(doc.data(), doc.id)).toList();
    notes.sort((a, b) => (b.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    return notes;
  }

  Future<List<SessionModel>> getSessions() async {
    final snap = await _db.collection('sessions').get();
    return snap.docs
        .map((d) => SessionModel.fromMap(d.data(), d.id))
        .toList();
  }

  Future<List<MessageModel>> getMessages(String chatRoomId) async {
    final snap = await _db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((d) => MessageModel.fromMap(d.data(), d.id))
        .toList();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  /// Deletes a group document from Firestore.
  Future<void> deleteGroup(String groupId) async {
    await _db.collection('groups').doc(groupId).delete();
  }

  /// Marks a user as suspended by writing a 'suspended' field,
  /// preserving the document so audit trails remain intact.
  Future<void> suspendUser(String userId) async {
    await _db.collection('users').doc(userId).update({
      'suspended': true,
      'suspendedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sets a report's status to 'resolved'.
  Future<void> resolveReport(String reportId) async {
    await _db.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    await logAdminAction('RESOLVE_REPORT', 'Resolved report $reportId');
  }

  /// Suspend/Ban a user
  Future<void> banUser(String userId, String banType, {String? reason, String? evidenceUrl}) async {
    final updateData = <String, dynamic>{
      'suspended': true,
      'banType': banType,
      'banReason': reason ?? 'Violation of terms',
      'suspendedAt': FieldValue.serverTimestamp(),
    };
    if (evidenceUrl != null && evidenceUrl.isNotEmpty) {
      updateData['banEvidence'] = evidenceUrl;
    }
    
    if (banType == 'temporary') {
      updateData['suspendedUntil'] =
          DateTime.now().add(const Duration(days: 7)).toIso8601String();
    }
    
    await _db.collection('users').doc(userId).update(updateData);
    await logAdminAction('BAN_USER', 'Banned user $userId ($banType) - ${reason ?? ''}');
  }

  /// Temporarily ban a user
  Future<void> tempBanUser(String userId, int hours) async {
    await _db.collection('users').doc(userId).update({
      'suspended': true,
      'banType': 'temporary',
      'suspendedUntil': DateTime.now().add(Duration(hours: hours)).toIso8601String(),
      'suspendedAt': FieldValue.serverTimestamp(),
    });
    await logAdminAction('TEMP_BAN_USER', 'Temporarily banned user $userId for $hours hours');
  }

  /// Unban a user
  Future<void> unbanUser(String userId) async {
    await _db.collection('users').doc(userId).update({
      'suspended': false,
      'banType': FieldValue.delete(),
      'suspendedUntil': FieldValue.delete(),
    });
    await logAdminAction('UNBAN_USER', 'Unbanned user $userId');
  }

  /// Warn a user
  Future<void> warnUser(String userId, {String? reason, String? evidenceUrl}) async {
    await _db.collection('users').doc(userId).update({
      'warnings': FieldValue.arrayUnion([{
        'date': DateTime.now().toIso8601String(),
        'reason': reason ?? 'System Warning',
        'evidenceUrl': evidenceUrl ?? '',
      }]),
    });
    await logAdminAction('WARN_USER', 'Warned user $userId - ${reason ?? ''}');
  }

  /// Reject a report and warn the reporter
  Future<void> rejectReportAndWarn(String reportId, String reporterId) async {
    // delete the report
    await _db.collection('reports').doc(reportId).delete();
    // warn the reporter
    await warnUser(reporterId, reason: 'Filing an inappropriate/false report.');
    await logAdminAction('REJECT_REPORT', 'Rejected report $reportId and warned reporter $reporterId');
  }

  /// Delete a note
  Future<void> deleteNote(String noteId) async {
    await _db.collection('notes').doc(noteId).delete();
    await logAdminAction('DELETE_NOTE', 'Deleted note $noteId');
  }

  /// Terminate a live session
  Future<void> terminateSession(String sessionId) async {
    await _db.collection('sessions').doc(sessionId).delete();
    await logAdminAction('TERMINATE_SESSION', 'Terminated session $sessionId');
  }

  /// Force delete a chat message across the system
  Future<void> deleteMessage(String chatRoomId, String messageId) async {
    await _db.collection('chats').doc(chatRoomId).collection('messages').doc(messageId).delete();
    await logAdminAction('DELETE_MESSAGE', 'Deleted message $messageId in chat $chatRoomId');
  }

  /// Broadcast a message to all group chats
  Future<void> broadcastMessage(String text) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    final groups = await getGroups();
    
    final message = MessageModel(
      id: '',
      senderId: currentUser.uid,
      receiverId: '', 
      message: text,
      timestamp: DateTime.now(),
      deletedFor: [],
    );

    for (final g in groups) {
      final msg = message.copyWith(receiverId: g.id);
      await _db.collection('chats').doc(g.id).collection('messages').add(msg.toMap());
    }
    
    await logAdminAction('BROADCAST_MESSAGE', 'Broadcasted: $text');
  }

  /// Write to the audit log
  Future<void> logAdminAction(String action, String details) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_admin';
    await _db.collection('admin_logs').add({
      'adminId': uid,
      'action': action,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final adminServiceProvider = Provider<AdminService>((ref) => AdminService());
