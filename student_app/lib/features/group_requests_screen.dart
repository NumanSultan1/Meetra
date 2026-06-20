import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/providers.dart';
import '../core/theme.dart';

class GroupRequestsScreen extends ConsumerStatefulWidget {
  const GroupRequestsScreen({super.key});

  @override
  ConsumerState<GroupRequestsScreen> createState() => _GroupRequestsScreenState();
}

class _GroupRequestsScreenState extends ConsumerState<GroupRequestsScreen> {
  bool _isLoading = false;

  Future<void> _approveRequest(String groupId, String userId) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(groupRepositoryProvider).approveJoin(groupId, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User approved and joined the group successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to approve request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectRequest(String groupId, String userId) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(groupRepositoryProvider).rejectJoin(groupId, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request declined.'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reject request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Requests', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: RadialBackground(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('groups')
              .where('createdBy', isEqualTo: currentUserId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error loading requests: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            final groupsWithRequests = docs
                .map((d) => GroupModel.fromMap(d.data() as Map<String, dynamic>, d.id))
                .where((g) => g.pendingMembers.isNotEmpty)
                .toList();

            if (groupsWithRequests.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'No pending join requests.',
                      style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                ListView.builder(
                  itemCount: groupsWithRequests.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final group = groupsWithRequests[index];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    group.name,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondaryTeal.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    group.semester,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.secondaryTeal,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24, color: Colors.white24),
                            ...group.pendingMembers.map((uid) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: _PendingMemberRow(
                                  userId: uid,
                                  onApprove: () => _approveRequest(group.id, uid),
                                  onReject: () => _rejectRequest(group.id, uid),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (_isLoading)
                  Container(
                    color: Colors.black38,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PendingMemberRow extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingMemberRow({
    required this.userId,
    required this.onApprove,
    required this.onReject,
  });

  @override
  ConsumerState<_PendingMemberRow> createState() => _PendingMemberRowState();
}

class _PendingMemberRowState extends ConsumerState<_PendingMemberRow> {
  UserModel? _user;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  Future<void> _fetchUser() async {
    try {
      final user = await ref.read(userRepositoryProvider).getUser(widget.userId);
      if (mounted) {
        setState(() {
          _user = user;
          _loadingUser = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingUser = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const SizedBox(
        height: 48,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_user == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Unknown Student', style: TextStyle(color: Colors.grey)),
          Row(
            children: [
              IconButton(onPressed: widget.onReject, icon: const Icon(Icons.close, color: Colors.redAccent)),
            ],
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(
              _user!.profileImage.isNotEmpty
                  ? _user!.profileImage
                  : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user!.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  _user!.email,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.2),
                  padding: const EdgeInsets.all(6),
                ),
                onPressed: widget.onApprove,
                icon: const Icon(Icons.check, color: Colors.green, size: 18),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                  padding: const EdgeInsets.all(6),
                ),
                onPressed: widget.onReject,
                icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
