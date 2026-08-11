import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import 'package:intl/intl.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../core/notification_service.dart';
import 'meeting_screen.dart';
import 'in_app_notification.dart';

class SessionsTab extends ConsumerStatefulWidget {
  const SessionsTab({super.key});

  @override
  ConsumerState<SessionsTab> createState() => _SessionsTabState();
}

class _AlarmInfo {
  final DateTime date;
  final Timer timer;
  _AlarmInfo({required this.date, required this.timer});
}

class _SessionsTabState extends ConsumerState<SessionsTab> {
  List<SessionModel> _sessions = [];
  bool _isLoading = false;
  Timer? _stateRefreshTimer;
  final Map<String, _AlarmInfo> _scheduledSessionAlarms = {};

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _stateRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _loadSessions(showSpinner: false);
      }
    });
  }

  @override
  void dispose() {
    _stateRefreshTimer?.cancel();
    for (final alarm in _scheduledSessionAlarms.values) {
      alarm.timer.cancel();
    }
    super.dispose();
  }

  Future<void> _loadSessions({bool showSpinner = true}) async {
    if (showSpinner && _sessions.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final list = await ref.read(sessionRepositoryProvider).getSessions();
      if (mounted) {
        final now = DateTime.now();
        // Hide sessions that ended more than 24 hours ago
        final visible = list.where((s) {
          final cutoff = s.date.add(const Duration(hours: 24));
          return now.isBefore(cutoff);
        }).toList();
        setState(() {
          _sessions = visible;
        });
        final currentUserId = ref.read(currentUserProvider)?.id ?? ref.read(authRepositoryProvider).currentUser?.id ?? '';
        _scheduleSessionAlarms(visible, currentUserId);
      }
    } catch (_) {
      // Ignore background errors
    } finally {
      if (mounted && showSpinner) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scheduleSessionAlarms(List<SessionModel> sessions, String currentUserId) {
    final now = DateTime.now();
    final activeSessionIds = <String>{};

    for (final session in sessions) {
      if (session.participants.contains(currentUserId)) {
        activeSessionIds.add(session.id);

        // If an alarm is already scheduled for this session and its date hasn't changed, skip rescheduling
        if (_scheduledSessionAlarms.containsKey(session.id) &&
            _scheduledSessionAlarms[session.id]!.date == session.date) {
          continue;
        }

        // Otherwise, cancel any existing alarm for this session
        if (_scheduledSessionAlarms.containsKey(session.id)) {
          _scheduledSessionAlarms[session.id]!.timer.cancel();
          _scheduledSessionAlarms.remove(session.id);
        }

        // Calculate alarm time (5 minutes before session starts)
        final alarmTime = session.date.subtract(const Duration(minutes: 5));

        if (alarmTime.isAfter(now)) {
          final difference = alarmTime.difference(now);
          final timer = Timer(difference, () {
            if (mounted) {
              _triggerSessionStartNotification(session, minutesBefore: 5);
              setState(() {});
            }
          });
          _scheduledSessionAlarms[session.id] = _AlarmInfo(date: session.date, timer: timer);
        } else if (session.date.isAfter(now)) {
          // Less than 5 minutes remain, fire immediately/soon
          final remainingMinutes = session.date.difference(now).inMinutes;
          final timer = Timer(const Duration(milliseconds: 500), () {
            if (mounted) {
              _triggerSessionStartNotification(session, minutesBefore: remainingMinutes);
              setState(() {});
            }
          });
          _scheduledSessionAlarms[session.id] = _AlarmInfo(date: session.date, timer: timer);
        }
      }
    }

    // Clean up any alarms for sessions that are no longer active
    final removedIds = _scheduledSessionAlarms.keys.where((id) => !activeSessionIds.contains(id)).toList();
    for (final id in removedIds) {
      _scheduledSessionAlarms[id]!.timer.cancel();
      _scheduledSessionAlarms.remove(id);
    }
  }

  void _triggerSessionStartNotification(SessionModel session, {int minutesBefore = 0}) {
    final String bodyText;
    if (minutesBefore > 0) {
      bodyText = 'Your study session "${session.title}" starts in $minutesBefore minutes! Tap to prepare.';
    } else {
      bodyText = 'Your study session "${session.title}" has started! Tap to join the meeting.';
    }

    NotificationService.showNotification(
      id: session.id.hashCode,
      title: 'Study Session Reminder',
      body: bodyText,
    );
    if (mounted) {
      InAppNotificationManager.show(
        context: context,
        title: 'Study Session Reminder',
        body: bodyText,
        onTap: () => _onJoinMeetingPressed(context, session),
      );
    }
  }

  Future<void> _onJoinMeetingPressed(BuildContext context, SessionModel session) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('meetings').doc(session.id).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['isTerminated'] == true) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This meeting has been terminated by the admin.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error checking meeting status: $e');
    }

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingScreen(session: session),
        ),
      );
    }
  }

  Future<void> _joinSession(SessionModel session) async {
    final currentUserId = ref.read(authRepositoryProvider).currentUser?.id ?? '';
    if (session.participants.contains(currentUserId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are already registered for this session.')),
      );
      return;
    }
    await ref.read(sessionRepositoryProvider).joinSession(session.id, currentUserId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Successfully registered for the study session!')),
    );
    _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id ?? '';
    final now = DateTime.now();
    final visibleSessions = _sessions.where((s) {
      final cutoff = s.date.add(const Duration(hours: 24));
      return now.isBefore(cutoff);
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: () => _showScheduleSessionDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : visibleSessions.isEmpty
              ? const Center(child: Text('No study sessions scheduled yet.'))
              : ListView.builder(
                  itemCount: visibleSessions.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, idx) {
                    final session = visibleSessions[idx];
                    final isParticipant = session.participants.contains(currentUserId);

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
                                    session.title,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    session.subject,
                                    style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('EEEE, MMM d • hh:mm a').format(session.date),
                                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${session.participants.length} attending',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                Builder(
                                  builder: (context) {
                                    final now = DateTime.now();
                                    // Joinable from 5 min before start until 24 hours after
                                    final isStartingSoonOrActive =
                                        now.isAfter(session.date.subtract(const Duration(minutes: 5))) &&
                                        now.isBefore(session.date.add(const Duration(hours: 24)));
                                    return isParticipant
                                        ? (isStartingSoonOrActive
                                            ? ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppTheme.secondaryTeal,
                                                  foregroundColor: Colors.white,
                                                  elevation: 2,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                onPressed: () => _onJoinMeetingPressed(context, session),
                                                icon: const Icon(Icons.videocam, size: 18),
                                                label: const Text('Join Meeting', style: TextStyle(fontWeight: FontWeight.bold)),
                                              )
                                            : ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                                  foregroundColor: Colors.white70,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                onPressed: null,
                                                child: const Text('Awaiting Time'),
                                              ))
                                        : ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.primaryBlue,
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            onPressed: () => _joinSession(session),
                                            child: const Text('Join Session'),
                                          );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showScheduleSessionDialog() {
    final titleCtrl = TextEditingController();
    final subCtrl = TextEditingController();
    DateTime selectedDateTime = DateTime.now().add(const Duration(days: 1));

    showDialog(
      context: context,
      builder: (ctx) => PremiumDialog(
        title: 'Schedule Study Session',
        icon: Icons.event,
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Session Title',
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
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
                  labelText: 'Subject (e.g. Physics)',
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppTheme.primaryBlue),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Date & Time: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppTheme.secondaryTeal),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      DateFormat('MMM d, hh:mm a').format(selectedDateTime),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: selectedDateTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) {
                        if (!context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                        );
                        if (time != null) {
                          setDialogState(() {
                            selectedDateTime = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                          });
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
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
              final title = titleCtrl.text.trim();
              final sub = subCtrl.text.trim();
              if (title.isEmpty || sub.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid session title and subject.')),
                );
                return;
              }
              if (title.length > 50 || sub.length > 50) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Title and Subject must be 50 characters or less.')),
                );
                return;
              }
              final currentUserId = ref.read(currentUserProvider)?.id ?? ref.read(authRepositoryProvider).currentUser?.id ?? '';
              final newSession = SessionModel(
                id: '',
                title: title,
                subject: sub,
                date: selectedDateTime,
                createdBy: currentUserId,
                participants: [currentUserId],
              );
              await ref.read(sessionRepositoryProvider).createSession(newSession);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _loadSessions();
            },
            child: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
