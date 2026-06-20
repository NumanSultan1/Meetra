import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../core/cloudinary_service.dart';
import '../core/theme.dart';
import 'package:intl/intl.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/providers.dart';
import '../core/theme.dart';

// ─── Admin Login Screen ───────────────────────────────────────────────────────
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(adminAuthServiceProvider).login(email, pass);
      // AdminAuthGate in main.dart watches auth state and navigates automatically.
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RadialBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.admin_panel_settings,
                    size: 72, color: AppTheme.primaryBlue),
                const SizedBox(height: 16),
                const Text('Admin Console',
                    style: TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold)),
                const Text('StudyFinder Management Portal',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 40),
                GlassCard(
                  child: Column(
                    children: [
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Admin Email',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onSubmitted: (_) => _login(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13)),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _loading ? null : _login,
                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Text('Login to Admin Console',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Admin Dashboard ──────────────────────────────────────────────────────────
class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});

  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  int _selectedIndex = 0;
  bool _isLoading = false;

  int _totalUsers = 0;
  int _totalGroups = 0;
  int _totalSessions = 0;

  List<UserModel> _users = [];
  List<GroupModel> _groups = [];
  List<ReportModel> _reports = [];
  List<NoteModel> _notes = [];
  List<SessionModel> _sessions = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final svc = ref.read(adminServiceProvider);
    final results = await Future.wait([
      svc.getUserCount(),
      svc.getGroupCount(),
      svc.getSessionCount(),
      svc.getUsers(),
      svc.getGroups(),
      svc.getReports(),
      svc.getNotes(),
      svc.getSessions(),
    ]);
    if (!mounted) return;
    setState(() {
      _totalUsers = results[0] as int;
      _totalGroups = results[1] as int;
      _totalSessions = results[2] as int;
      _users = results[3] as List<UserModel>;
      _groups = results[4] as List<GroupModel>;
      _reports = results[5] as List<ReportModel>;
      _notes = results[6] as List<NoteModel>;
      _sessions = results[7] as List<SessionModel>;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StudyFinder Admin Console',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(adminAuthServiceProvider).logout();
              // AdminAuthGate watches auth state and navigates back to login automatically.
            },
          ),
        ],
      ),
      body: RadialBackground(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              return isWide
                  ? _buildWideLayout()
                  : _buildNarrowLayout();
            },
          ),
        ),
      ),
    );
  }

  // ── Wide layout: sidebar + content panel ──────────────────────────────────
  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NavigationRail(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          labelType: NavigationRailLabelType.all,
          backgroundColor: Colors.transparent,
          selectedIconTheme:
              const IconThemeData(color: AppTheme.primaryBlue),
          unselectedIconTheme: const IconThemeData(color: Colors.grey),
          destinations: _navDestinations,
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  // ── Narrow layout: bottom nav + content ───────────────────────────────────
  Widget _buildNarrowLayout() {
    return Column(
      children: [
        Expanded(child: _buildContent()),
        BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppTheme.primaryBlue,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined), label: 'Stats'),
            BottomNavigationBarItem(
                icon: Icon(Icons.people_outline), label: 'Users'),
            BottomNavigationBarItem(
                icon: Icon(Icons.groups_outlined), label: 'Groups'),
            BottomNavigationBarItem(
                icon: Icon(Icons.description_outlined), label: 'Notes'),
            BottomNavigationBarItem(
                icon: Icon(Icons.timer_outlined), label: 'Sessions'),
            BottomNavigationBarItem(
                icon: Icon(Icons.chat_outlined), label: 'Global Chat'),
            BottomNavigationBarItem(
                icon: Icon(Icons.report_problem_outlined), label: 'Reports'),
          ],
        ),
      ],
    );
  }

  List<NavigationRailDestination> get _navDestinations => const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Stats'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Users'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups),
          label: Text('Groups'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: Text('Notes'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.timer_outlined),
          selectedIcon: Icon(Icons.timer),
          label: Text('Sessions'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.chat_outlined),
          selectedIcon: Icon(Icons.chat),
          label: Text('Global Chat'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.report_problem_outlined),
          selectedIcon: Icon(Icons.report_problem),
          label: Text('Reports'),
        ),
      ];

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return IndexedStack(
      index: _selectedIndex,
      children: [
        _buildStatsTab(),
        _buildUsersTab(),
        _buildGroupsTab(),
        _buildNotesTab(),
        _buildSessionsTab(),
        _buildGlobalChatTab(),
        _buildReportsTab(),
      ],
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────
  Widget _buildStatsTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Platform Overview',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metricCard('Total Users', '$_totalUsers',
                  Icons.person, Colors.blue),
              _metricCard('Study Groups', '$_totalGroups',
                  Icons.group_work, Colors.teal),
              _metricCard('Sessions Scheduled', '$_totalSessions',
                  Icons.calendar_today, Colors.indigo),
              _metricCard('Pending Reports',
                  '${_reports.where((r) => r.status == 'pending').length}',
                  Icons.report_problem, Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
      String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 160,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }


  // ── Users ─────────────────────────────────────────────────────────────────
  Widget _buildUsersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('User Management',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: _users.isEmpty
              ? const Center(child: Text('No users found.'))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (ctx, i) {
                    final user = _users[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 16,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage: NetworkImage(
                                user.profileImage.isNotEmpty
                                    ? user.profileImage
                                    : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(user.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  Text(user.email,
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                  Text(user.university,
                                      style: const TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (user.suspended ?? false)
                                      ? Colors.red.withValues(alpha: 0.1)
                                      : Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text((user.suspended ?? false) ? 'Banned' : 'Active',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: (user.suspended ?? false) ? Colors.red : Colors.green,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 8),
                                PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'unban') {
                                      final svc = ref.read(adminServiceProvider);
                                      svc.unbanUser(user.id).then((_) {
                                        _refresh();
                                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unbanned ${user.name}.')));
                                      });
                                    } else {
                                      _showActionDialog(user.id, action, userName: user.name);
                                    }
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Action "$action" applied to ${user.name}.')));
                                  },
                                  itemBuilder: (context) => [
                                    if (!(user.suspended ?? false)) ...[
                                      const PopupMenuItem(value: 'warn', child: Text('Send Warning')),
                                      const PopupMenuItem(value: 'temp_ban', child: Text('Temp Ban (24h)')),
                                      const PopupMenuItem(value: 'ban', child: Text('Permanent Ban')),
                                    ] else ...[
                                      const PopupMenuItem(value: 'unban', child: Text('Unban User')),
                                    ],
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('Actions', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 12)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Groups ────────────────────────────────────────────────────────────────
  Widget _buildGroupsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Group Moderation',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: _groups.isEmpty
              ? const Center(child: Text('No groups to moderate.'))
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (ctx, i) {
                    final grp = _groups[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 16,
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.group_work,
                                  color: AppTheme.primaryBlue),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(grp.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  Text(grp.subject,
                                      style: const TextStyle(
                                          color: AppTheme.secondaryTeal,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      '${grp.members.length} members • Created by ${grp.createdBy}',
                                      style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () async {
                                await ref
                                    .read(adminServiceProvider)
                                    .deleteGroup(grp.id);
                                await _refresh();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                        content:
                                            Text('Group deleted.')));
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Reports ───────────────────────────────────────────────────────────────
  Widget _buildReportsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('User Reports',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: _reports.isEmpty
              ? const Center(child: Text('No reports to review.'))
              : ListView.builder(
                  itemCount: _reports.length,
                  itemBuilder: (ctx, i) {
                    final r = _reports[i];
                    final isPending = r.status == 'pending';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Icon(Icons.report_problem,
                                          color: isPending
                                              ? Colors.orange
                                              : Colors.green,
                                          size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('Report #${r.id}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (isPending
                                            ? Colors.orange
                                            : Colors.green)
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    r.status.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isPending
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Reported User ID: ${r.reportedUser}',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.grey)),
                            if (r.reportedUserName != null)
                              Text('Name: ${r.reportedUserName}',
                                  style: const TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(r.reason,
                                style: const TextStyle(fontSize: 14)),
                            if (r.evidenceUrl != null) ...[
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => launchUrl(Uri.parse(r.evidenceUrl!)),
                                child: const Text('View Evidence Screenshot', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                              ),
                            ],
                            if (isPending) ...[
                              const SizedBox(height: 12),
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      if (r.reportedBy != null && r.reportedBy!.isNotEmpty) {
                                        await ref.read(adminServiceProvider).rejectReportAndWarn(r.id, r.reportedBy!);
                                      } else {
                                        await ref.read(adminServiceProvider).resolveReport(r.id);
                                      }
                                      await _refresh();
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report rejected & reporter warned.')));
                                    },
                                    child: const Text('Reject & Warn', style: TextStyle(color: Colors.red)),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      await ref.read(adminServiceProvider).resolveReport(r.id);
                                      await _refresh();
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report resolved.')));
                                    },
                                    child: const Text('Mark Resolved'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryBlue,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () async {
                                      _showActionDialog(r.reportedUser, 'ban', userName: r.reportedUserName ?? r.reportedUser);
                                      await ref.read(adminServiceProvider).resolveReport(r.id);
                                      await _refresh();
                                    },
                                    child: const Text('Take Action'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Notes & Files ─────────────────────────────────────────────────────────
  Widget _buildNotesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Notes & Files Moderation',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: _notes.isEmpty
              ? const Center(child: Text('No notes uploaded.'))
              : ListView.builder(
                  itemCount: _notes.length,
                  itemBuilder: (ctx, i) {
                    final note = _notes[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 16,
                        child: Row(
                          children: [
                            const Icon(Icons.description, color: AppTheme.primaryBlue, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('${note.subject} • ${note.semester}', style: const TextStyle(color: AppTheme.secondaryTeal, fontSize: 12)),
                                  Text('Uploaded by: ${note.uploadedBy}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () async {
                                await ref.read(adminServiceProvider).deleteNote(note.id);
                                await _refresh();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note deleted.')));
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Sessions ──────────────────────────────────────────────────────────────
  Widget _buildSessionsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Active Study Sessions',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Expanded(
          child: _sessions.isEmpty
              ? const Center(child: Text('No active sessions.'))
              : ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (ctx, i) {
                    final session = _sessions[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 16,
                        child: Row(
                          children: [
                            const Icon(Icons.video_call, color: AppTheme.primaryBlue, size: 40),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(session.subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('${session.participants.length} participants', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                              onPressed: () async {
                                await ref.read(adminServiceProvider).terminateSession(session.id);
                                await _refresh();
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session terminated.')));
                              },
                              child: const Text('Terminate'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Global Chat ───────────────────────────────────────────────────────────
  Widget _buildGlobalChatTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Global Chat Moderation', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              icon: const Icon(Icons.campaign),
              label: const Text('Broadcast Announcement'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
              onPressed: () async {
                final controller = TextEditingController();
                final result = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Broadcast Announcement'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(hintText: 'Enter announcement message...'),
                      maxLines: 3,
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Send')),
                    ],
                  ),
                );
                if (result != null && result.trim().isNotEmpty) {
                  await ref.read(adminServiceProvider).broadcastMessage('[ADMIN]: ${result.trim()}');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Broadcast sent.')));
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _groups.isEmpty
              ? const Center(child: Text('No groups available for chat monitoring.'))
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (ctx, i) {
                    final group = _groups[i];
                    return ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${group.members.length} members'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        // For a real app, this would push a new route to show the chat messages for this group.
                        // For this implementation, we will show a dialog with recent messages.
                        _showChatMessagesDialog(group);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showChatMessagesDialog(GroupModel group) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Chat: ${group.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<MessageModel>>(
                  future: ref.read(adminServiceProvider).getMessages(group.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    final msgs = snapshot.data ?? [];
                    if (msgs.isEmpty) return const Center(child: Text('No messages.'));
                    return ListView.builder(
                      itemCount: msgs.length,
                      itemBuilder: (context, idx) {
                        final m = msgs[idx];
                        String senderName = m.senderId;
                        try {
                          final userObj = _users.firstWhere((u) => u.id == m.senderId);
                          senderName = userObj.name;
                        } catch (_) {}
                        return ListTile(
                          title: Text(m.message),
                          subtitle: Text('Sender: $senderName • ${m.timestamp.toString()}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              await ref.read(adminServiceProvider).deleteMessage(group.id, m.id);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message deleted. Refresh chat view to see.')));
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
        ),
      ),
    );
  }

  void _showActionDialog(String userId, String action, {String userName = ''}) {
    final reasonCtrl = TextEditingController();
    String? evidenceUrl;
    bool isUploading = false;
    String actionLabel = 'Take Action';
    IconData actionIcon = Icons.gavel;
    if (action == 'warn') { actionLabel = 'Warn User'; actionIcon = Icons.warning; }
    else if (action == 'temp_ban') { actionLabel = 'Temp Ban (24h)'; actionIcon = Icons.timer_off; }
    else if (action == 'ban') { actionLabel = 'Permanent Ban'; actionIcon = Icons.block; }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => PremiumDialog(
          title: '$actionLabel: $userName',
          icon: actionIcon,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason / Description',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              if (evidenceUrl != null)
                const Text('Evidence attached.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
              else if (isUploading)
                const Center(child: CircularProgressIndicator())
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Attach Evidence (Optional)'),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(type: FileType.image);
                    if (result != null && result.files.single.bytes != null) {
                      setDialogState(() => isUploading = true);
                      try {
                        final url = await CloudinaryService.uploadFile(result.files.single.bytes!, result.files.single.name);
                        setDialogState(() {
                          evidenceUrl = url;
                          isUploading = false;
                        });
                      } catch (e) {
                        setDialogState(() => isUploading = false);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
                      }
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final svc = ref.read(adminServiceProvider);
                if (action == 'warn') {
                  await svc.warnUser(userId, reason: reasonCtrl.text, evidenceUrl: evidenceUrl);
                } else if (action == 'temp_ban') {
                  await svc.banUser(userId, 'temporary', reason: reasonCtrl.text, evidenceUrl: evidenceUrl);
                } else if (action == 'ban') {
                  await svc.banUser(userId, 'permanent', reason: reasonCtrl.text, evidenceUrl: evidenceUrl);
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _refresh();
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action $action taken successfully.')));
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
