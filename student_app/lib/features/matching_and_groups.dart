import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../data/repositories_impl.dart';
import 'profile_screen.dart';
import 'chat_screen.dart';

// ==========================================
// STUDY PARTNER MATCHING
// ==========================================
class PartnerMatchingTab extends ConsumerStatefulWidget {
  const PartnerMatchingTab({super.key});
  @override
  ConsumerState<PartnerMatchingTab> createState() => _PartnerMatchingTabState();
}

class _PartnerMatchingTabState extends ConsumerState<PartnerMatchingTab> {
  final _searchController = TextEditingController();
  String _selectedSemester = '';
  String _selectedSubject = '';
  List<UserModel> _partners = [];
  bool _isLoading = false;

  StreamSubscription? _chatsSubscription;
  Map<String, Map<String, dynamic>> _chatMetadata = {};

  @override
  void initState() {
    super.initState();
    _loadPartners();
    _listenToChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatsSubscription?.cancel();
    super.dispose();
  }

  void _listenToChats() {
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (currentUser == null) return;

    _chatsSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUser.id)
        .snapshots()
        .listen((snapshot) {
      final Map<String, Map<String, dynamic>> tempMetadata = {};
      for (final doc in snapshot.docs) {
        tempMetadata[doc.id] = doc.data();
      }
      if (mounted) {
        setState(() {
          _chatMetadata = tempMetadata;
          _sortPartners();
        });
      }
    });
  }

  void _sortPartners() {
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (currentUser == null) return;
    final currentUserId = currentUser.id;

    setState(() {
      _partners.sort((a, b) {
        final idsA = [currentUserId, a.id]..sort();
        final roomA = '${idsA[0]}_${idsA[1]}';
        
        final idsB = [currentUserId, b.id]..sort();
        final roomB = '${idsB[0]}_${idsB[1]}';

        final metaA = _chatMetadata[roomA];
        final metaB = _chatMetadata[roomB];

        final timeAStr = metaA?['lastMessageTimestamp'];
        final timeBStr = metaB?['lastMessageTimestamp'];

        final timeA = timeAStr != null ? DateTime.tryParse(timeAStr) : null;
        final timeB = timeBStr != null ? DateTime.tryParse(timeBStr) : null;

        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // b is newer, so b comes first
        if (timeB == null) return -1; // a is newer, so a comes first
        return timeB.compareTo(timeA); // descending (newest first)
      });
    });
  }

  Future<void> _loadPartners() async {
    setState(() => _isLoading = true);
    try {
      final userRepo = ref.read(userRepositoryProvider);
      final currentUser = ref.read(authRepositoryProvider).currentUser;
      if (currentUser != null) {
        try {
          final full = await userRepo.getUser(currentUser.id);
          _partners = await userRepo.getMatchingPartners(full);
        } catch (_) {
          _partners = await userRepo.searchUsers();
        }
      } else {
        _partners = await userRepo.searchUsers();
      }
      _sortPartners();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _applyFilters() async {
    setState(() => _isLoading = true);
    try {
      _partners = await ref.read(userRepositoryProvider).searchUsers(
        query: _searchController.text.trim(),
        semester: _selectedSemester.isEmpty ? null : _selectedSemester,
        subject: _selectedSubject.isEmpty ? null : _selectedSubject,
      );
      _sortPartners();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search partners by name or university...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.tune), onPressed: _showFilterBottomSheet),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onChanged: (_) => _applyFilters(),
        ),
      ),
      Expanded(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _partners.isEmpty
                ? const Center(child: Text('No partners found.'))
                : ListView.builder(
                    itemCount: _partners.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, idx) {
                      final partner = _partners[idx];
                      final currentUser = ref.read(authRepositoryProvider).currentUser;
                      final currentUserId = currentUser?.id ?? '';
                      final ids = [currentUserId, partner.id]..sort();
                      final roomDocId = '${ids[0]}_${ids[1]}';
                      final meta = _chatMetadata[roomDocId];
                      final unreadCount = meta?['unread_$currentUserId'] ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            CircleAvatar(radius: 30,
                              backgroundImage: NetworkImage(partner.profileImage.isNotEmpty
                                ? partner.profileImage
                                : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150')),
                            const SizedBox(width: 16),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(partner.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text(partner.university, style: const TextStyle(fontSize: 14, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Wrap(spacing: 4, runSpacing: 4,
                                children: partner.subjects.take(2).map((s) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                  child: Text(s, style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue)),
                                )).toList()),
                            ])),
                            Column(children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.primaryBlue),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => ChatScreen(receiverId: partner.id, receiverName: partner.name, isGroup: false)))),
                                  if (unreadCount > 0)
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$unreadCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline, color: Colors.grey),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ProfileScreen(user: partner, isOwnProfile: false)))),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Filter Study Partners', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('Semester', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            initialValue: _selectedSemester.isEmpty ? null : _selectedSemester,
            items: const [
              DropdownMenuItem(value: 'Fall 2026', child: Text('Fall 2026')),
              DropdownMenuItem(value: 'Spring 2026', child: Text('Spring 2026')),
              DropdownMenuItem(value: 'Summer 2026', child: Text('Summer 2026')),
            ],
            onChanged: (val) => setState(() => _selectedSemester = val ?? ''),
          ),
          const SizedBox(height: 16),
          const Text('Subject Area', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(hintText: 'e.g. Chemistry', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onChanged: (val) => _selectedSubject = val,
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { Navigator.pop(context); _applyFilters(); },
              child: const Text('Apply Filters'),
            )),
        ]),
      ),
    );
  }
}

// ==========================================
// STUDY GROUPS
// ==========================================
class GroupsTab extends ConsumerStatefulWidget {
  const GroupsTab({super.key});
  @override
  ConsumerState<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<GroupsTab> {
  List<GroupModel> _groups = [];
  bool _isLoading = false;

  @override
  void initState() { super.initState(); _loadGroups(); }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      _groups = await ref.read(groupRepositoryProvider).getGroups();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestJoin(GroupModel group) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
    // Use Firebase method if available
    final repo = ref.read(groupRepositoryProvider);
    if (repo is FirebaseGroupRepository) {
      await repo.requestJoin(group.id, currentUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join request sent! Waiting for admin approval.'), backgroundColor: Colors.orange));
    } else {
      await repo.joinGroup(group.id, currentUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Joined group!')));
    }
    _loadGroups();
  }

  Future<void> _leaveGroup(GroupModel group) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
    await ref.read(groupRepositoryProvider).leaveGroup(group.id, currentUserId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Left group.')));
    _loadGroups();
  }

  Future<void> _deleteGroup(GroupModel group) async {
    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Group', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${group.name}"? This will permanently remove the group and all its data.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(groupRepositoryProvider).deleteGroup(group.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group deleted.'), backgroundColor: Colors.orange),
        );
        _loadGroups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  void _showGroupOptions(GroupModel group) {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
    final isAdmin = group.createdBy == currentUserId;
    final isMember = group.members.contains(currentUserId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(group.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${group.subject} · ${group.semester}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 20),
                if (isMember && !isAdmin) ...[  
                  _groupOptionTile(
                    icon: Icons.exit_to_app,
                    iconColor: Colors.orange,
                    label: 'Leave Group',
                    subtitle: 'Remove yourself from this group',
                    onTap: () {
                      Navigator.pop(ctx);
                      _leaveGroup(group);
                    },
                  ),
                ],
                if (isAdmin) ...[  
                  _groupOptionTile(
                    icon: Icons.delete_outline,
                    iconColor: Colors.redAccent,
                    label: 'Delete Group',
                    subtitle: 'Permanently delete this group (admin only)',
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteGroup(group);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupOptionTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id ?? '';

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: _showCreateGroupDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('No study groups yet.'))
              : ListView.builder(
                  itemCount: _groups.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, idx) {
                    final group = _groups[idx];
                    final isMember = group.members.contains(currentUserId);
                    final isAdmin = group.createdBy == currentUserId;
                    final pendingMembers = (group.toMap()['pendingMembers'] as List?)?.cast<String>() ?? [];
                    final hasPendingRequest = pendingMembers.contains(currentUserId);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: GestureDetector(
                        onLongPress: () => _showGroupOptions(group),
                        child: GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Expanded(child: Text(group.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondaryTeal.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6)),
                                    child: Text(group.subject,
                                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryTeal, fontWeight: FontWeight.bold))),
                                  if (group.semester.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6)),
                                      child: Text(group.semester,
                                        style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold))),
                                  ],
                                ],
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Text(group.description, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                            const SizedBox(height: 12),

                            // Admin: show pending requests
                            if (isAdmin && pendingMembers.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${pendingMembers.length} pending request(s)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                                  const SizedBox(height: 6),
                                  ...pendingMembers.map((uid) => _PendingMemberTile(
                                    userId: uid,
                                    onApprove: () async {
                                      final repo = ref.read(groupRepositoryProvider);
                                      if (repo is FirebaseGroupRepository) {
                                        await repo.approveJoin(group.id, uid);
                                      }
                                      _loadGroups();
                                    },
                                    onReject: () async {
                                      final repo = ref.read(groupRepositoryProvider);
                                      if (repo is FirebaseGroupRepository) {
                                        await repo.rejectJoin(group.id, uid);
                                      }
                                      _loadGroups();
                                    },
                                  )),
                                ]),
                              ),
                              const SizedBox(height: 8),
                            ],

                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text('${group.members.length} members',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              Row(children: [
                                if (isMember)
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_outline, color: AppTheme.primaryBlue),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => ChatScreen(receiverId: group.id, receiverName: group.name, isGroup: true)))),
                                if (!isMember && !isAdmin)
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: hasPendingRequest ? Colors.orange[100] : AppTheme.primaryBlue,
                                      foregroundColor: hasPendingRequest ? Colors.orange : Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                    onPressed: hasPendingRequest ? null : () => _requestJoin(group),
                                    child: Text(hasPendingRequest ? 'Pending...' : 'Request Join'),
                                  ),
                                if (isMember && !isAdmin)
                                  TextButton(
                                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                                    onPressed: () => _leaveGroup(group),
                                    child: const Text('Leave'),
                                  ),
                                if (isAdmin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8)),
                                    child: const Text('Admin', style: TextStyle(color: AppTheme.primaryBlue, fontSize: 12, fontWeight: FontWeight.bold))),
                              ]),
                            ]),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showCreateGroupDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final subCtrl = TextEditingController();
    final semesters = ['Semester 1', 'Semester 2', 'Semester 3', 'Semester 4', 'Semester 5', 'Semester 6', 'Semester 7', 'Semester 8'];
    String chosenSemester = 'Semester 1';

    showDialog(
      context: context,
      builder: (ctx) => PremiumDialog(
        title: 'Create Study Group',
        icon: Icons.groups,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Group Name',
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryBlue),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description',
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryBlue),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: subCtrl,
              decoration: InputDecoration(
                labelText: 'Subject (e.g. Chemistry)',
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppTheme.primaryBlue),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (ctx, setInner) => Theme(
                data: Theme.of(ctx).copyWith(canvasColor: const Color(0xFF1E293B)),
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Semester',
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: AppTheme.primaryBlue),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  dropdownColor: const Color(0xFF1E293B),
                  value: chosenSemester,
                  items: semesters.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setInner(() => chosenSemester = val);
                    }
                  },
                ),
              ),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () async {
              if (nameCtrl.text.isEmpty || subCtrl.text.isEmpty) return;
              final currentUserId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
              final group = GroupModel(
                id: '',
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim(),
                subject: subCtrl.text.trim(),
                semester: chosenSemester,
                createdBy: currentUserId,
                members: [currentUserId],
              );
              await ref.read(groupRepositoryProvider).createGroup(group);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadGroups();
            },
            child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// Helper widget for pending member approval
class _PendingMemberTile extends ConsumerWidget {
  final String userId;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingMemberTile({required this.userId, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<UserModel>(
      future: ref.read(userRepositoryProvider).getUser(userId),
      builder: (ctx, snap) {
        final name = snap.data?.name ?? 'Loading...';
        return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(name, style: const TextStyle(fontSize: 13)),
          Row(children: [
            IconButton(icon: const Icon(Icons.check_circle, color: Colors.green, size: 20), onPressed: onApprove, tooltip: 'Approve'),
            IconButton(icon: const Icon(Icons.cancel, color: Colors.red, size: 20), onPressed: onReject, tooltip: 'Reject'),
          ]),
        ]);
      },
    );
  }
}