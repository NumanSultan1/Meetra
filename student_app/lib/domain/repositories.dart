import 'package:study_finder_shared/study_finder_shared.dart';

abstract class AuthRepository {
  Stream<UserModel?> get onAuthStateChanged;
  UserModel? get currentUser;
  Future<UserModel> login(String email, String password);
  Future<UserModel> register(String email, String password, String name);
  Future<void> logout();
  Future<void> sendPasswordResetEmail(String email);
  Future<void> verifyEmail();
}

abstract class UserRepository {
  Future<UserModel> getUser(String id);
  Future<void> updateUser(UserModel user);
  Future<List<UserModel>> searchUsers({String? query, String? semester, String? subject});
  Future<List<UserModel>> getMatchingPartners(UserModel user);
}

abstract class GroupRepository {
  Future<GroupModel> createGroup(GroupModel group);
  Future<List<GroupModel>> getGroups({String? subject});
  Future<GroupModel> getGroupById(String id);
  Future<void> joinGroup(String groupId, String userId);
  Future<void> leaveGroup(String groupId, String userId);
  Future<List<UserModel>> getGroupMembers(String groupId);
  Future<void> requestJoin(String groupId, String userId);
  Future<void> approveJoin(String groupId, String userId);
  Future<void> rejectJoin(String groupId, String userId);
  Future<void> deleteGroup(String groupId);
}

abstract class SessionRepository {
  Future<SessionModel> createSession(SessionModel session);
  Future<List<SessionModel>> getSessions({String? subject});
  Future<void> joinSession(String sessionId, String userId);
  Future<List<UserModel>> getSessionParticipants(String sessionId);
}

abstract class ChatRepository {
  Stream<List<MessageModel>> getMessages(String receiverId);
  Future<void> sendMessage(MessageModel message);
  Future<void> deleteMessage(String chatRoomId, String messageId);
  Future<void> deleteMessageForMe(String chatRoomId, String messageId, String userId);
}

abstract class NoteRepository {
  Future<NoteModel> uploadNote(NoteModel note);
  Future<List<NoteModel>> getNotes({String? subject, String? semester, String? query});
  Future<void> deleteNote(String noteId);
}

abstract class ReportRepository {
  Future<void> submitReport(ReportModel report);
}
