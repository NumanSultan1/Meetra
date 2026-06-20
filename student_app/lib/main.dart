import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'core/providers.dart';
import 'core/notification_service.dart';
import 'firebase_options.dart';
import 'core/theme.dart';
import 'features/auth_screens.dart';
import 'features/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Failed to initialize NotificationService: $e');
  }

  Widget app;
  try {
    // Avoid duplicate initialization when a default app already exists.
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        debugPrint('Firebase already initialized; skipping initializeApp.');
      }
    } on FirebaseException catch (fe) {
      final code = fe.code;
      final msg = fe.message ?? '';
      if (code.contains('duplicate') || msg.contains('duplicate')) {
        debugPrint('Ignored duplicate Firebase app error: $fe');
      } else {
        rethrow;
      }
    }
    app = const ProviderScope(
      child: StudyFinderStudentApp(),
    );
  } catch (e, st) {
    debugPrint('Firebase initialization error: $e\n$st');
    app = MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Initialization error: $e'),
        ),
      ),
    );
  }

  runApp(app);
}

class StudyFinderStudentApp extends ConsumerWidget {
  const StudyFinderStudentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Meetra',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// AuthGate is a reactive widget that lives as the root route (/).
/// It watches authStateProvider and conditionally renders
/// HomeScreen or OnboardingScreen. Because it's a ConsumerWidget
/// inside the Navigator route (not at the MaterialApp.home level),
/// it rebuilds properly when the auth state changes.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          return HomeScreen(key: ValueKey('home_${user.id}'), currentUser: user);
        }
        return const OnboardingScreen();
      },
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, stack) => Scaffold(
        body: Center(
          child: Text('An error occurred: $err'),
        ),
      ),
    );
  }
}
