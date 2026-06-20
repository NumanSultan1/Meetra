import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../domain/repositories.dart';
import '../data/repositories_impl.dart';

/// Always uses Firebase — mock mode has been removed.
final useFirebaseProvider = Provider<bool>((ref) => true);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseAuthRepository() : MockAuthRepository();
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseUserRepository() : MockUserRepository();
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseGroupRepository() : MockGroupRepository();
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseSessionRepository() : MockSessionRepository();
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseChatRepository() : MockChatRepository();
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseNoteRepository() : MockNoteRepository();
});

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  final useFirebase = ref.watch(useFirebaseProvider);
  return useFirebase ? FirebaseReportRepository() : MockReportRepository();
});

// Auth state stream provider
final authStateProvider = StreamProvider<UserModel?>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return authRepo.onAuthStateChanged;
});

// Selected chat partner / group provider
final currentChatRecipientProvider = StateProvider<String?>((ref) => null);
