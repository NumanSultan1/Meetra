import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/dashboard.dart';
import 'core/providers.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    const ProviderScope(
      child: StudyFinderAdminApp(),
    ),
  );
}

class StudyFinderAdminApp extends StatelessWidget {
  const StudyFinderAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StudyFinder - Admin Portal',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AdminAuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Watches Firebase Auth state and routes to login or dashboard.
class AdminAuthGate extends ConsumerWidget {
  const AdminAuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(adminAuthStateProvider);
    return authState.when(
      data: (user) =>
          user != null ? const AdminDashboard() : const AdminLoginScreen(),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Auth error: $e')),
      ),
    );
  }
}
