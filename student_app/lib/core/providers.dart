import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

// Real-time current user document stream provider (resolves H-3)
final currentUserStreamProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  if (authState == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(authState.id)
      .snapshots()
      .map((doc) {
        if (!doc.exists) return authState;
        if (doc.data()?['suspended'] == true) {
          FirebaseAuth.instance.signOut();
          return null;
        }
        return UserModel.fromMap(doc.data()!, authState.id);
      });
});

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(currentUserStreamProvider).valueOrNull;
});

// Selected chat partner / group provider
final currentChatRecipientProvider = StateProvider<String?>((ref) => null);
