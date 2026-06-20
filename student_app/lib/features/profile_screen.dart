import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../core/cloudinary_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final bool isOwnProfile;

  const ProfileScreen({super.key, required this.user, this.isOwnProfile = true});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _universityController;
  late TextEditingController _semesterController;
  late TextEditingController _goalsController;
  late List<String> _subjects;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String _profileImageUrl = '';

  // Availability schedule state
  final Map<String, bool> _selectedDays = {
    'Mon': false, 'Tue': false, 'Wed': false,
    'Thu': false, 'Fri': false, 'Sat': false, 'Sun': false,
  };
  TimeOfDay _fromTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _toTime = const TimeOfDay(hour: 14, minute: 0);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _universityController = TextEditingController(text: widget.user.university);
    _semesterController = TextEditingController(text: widget.user.semester);
    _goalsController = TextEditingController(text: widget.user.studyGoals);
    _subjects = List<String>.from(widget.user.subjects);
    _profileImageUrl = widget.user.profileImage;
    _parseAvailability(widget.user.availability);
  }

  // Parse existing availability string back into days/times
  void _parseAvailability(String availability) {
    // e.g. "Mon, Wed, Fri: 10:00 AM – 2:00 PM"
    try {
      if (availability.contains(':')) {
        final parts = availability.split(':');
        final days = parts[0].split(',').map((d) => d.trim()).toList();
        for (final day in days) {
          if (_selectedDays.containsKey(day)) {
            _selectedDays[day] = true;
          }
        }
      }
    } catch (_) {}
  }

  String _buildAvailabilityString() {
    final days = _selectedDays.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (days.isEmpty) return 'Not set';
    final from = _fromTime.format(context);
    final to = _toTime.format(context);
    return '${days.join(', ')}: $from – $to';
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    XFile? picked;

    if (kIsWeb) {
      picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
        maxHeight: 800,
      );
    } else {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      picked = await picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 800,
        maxHeight: 800,
      );
    }

    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      String downloadUrl;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        downloadUrl = await CloudinaryService.uploadImage(bytes);
      } else {
        downloadUrl = await CloudinaryService.uploadImage(File(picked.path));
      }

      // Save to Firestore immediately
      final updatedUser = widget.user.copyWith(profileImage: downloadUrl);
      await ref.read(userRepositoryProvider).updateUser(updatedUser);

      setState(() => _profileImageUrl = downloadUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _pickFromTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _fromTime,
      helpText: 'Select Start Time',
    );
    if (picked != null) setState(() => _fromTime = picked);
  }

  Future<void> _pickToTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTime,
      helpText: 'Select End Time',
    );
    if (picked != null) setState(() => _toTime = picked);
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final updatedUser = widget.user.copyWith(
      name: _nameController.text.trim(),
      university: _universityController.text.trim(),
      semester: _semesterController.text.trim(),
      studyGoals: _goalsController.text.trim(),
      availability: _buildAvailabilityString(),
      subjects: _subjects,
      profileImage: _profileImageUrl,
    );
    try {
      await ref.read(userRepositoryProvider).updateUser(updatedUser);
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RadialBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!widget.isOwnProfile)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    )
                  else
                    const SizedBox(width: 48),
                  Text(
                    widget.isOwnProfile ? 'My Profile' : widget.user.name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (widget.isOwnProfile)
                    IconButton(
                      icon: Icon(_isEditing ? Icons.close : Icons.edit),
                      onPressed: () => setState(() => _isEditing = !_isEditing),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 24),

              // Profile Picture
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _isUploadingPhoto
                      ? const CircleAvatar(
                          radius: 64,
                          child: CircularProgressIndicator(),
                        )
                      : CircleAvatar(
                          radius: 64,
                          backgroundImage: NetworkImage(
                            _profileImageUrl.isNotEmpty
                                ? _profileImageUrl
                                : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
                          ),
                        ),
                  if (_isEditing)
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryBlue,
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                        onPressed: _isUploadingPhoto ? null : _pickAndUploadPhoto,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Profile Fields
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField(
                      label: 'Full Name',
                      controller: _nameController,
                      enabled: _isEditing,
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      label: 'University',
                      controller: _universityController,
                      enabled: _isEditing,
                      icon: Icons.school_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      label: 'Semester / Year',
                      controller: _semesterController,
                      enabled: _isEditing,
                      icon: Icons.calendar_today_outlined,
                    ),
                    const SizedBox(height: 16),

                    // ── Availability Schedule ──
                    const Text(
                      'Availability Schedule',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (!_isEditing)
                      Row(
                        children: [
                          const Icon(Icons.access_time_outlined, size: 20, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _buildAvailabilityString(),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      // Day selector
                      Wrap(
                        spacing: 6,
                        children: _selectedDays.keys.map((day) {
                          final selected = _selectedDays[day]!;
                          return FilterChip(
                            label: Text(day),
                            selected: selected,
                            onSelected: (val) => setState(() => _selectedDays[day] = val),
                            selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      // Time range picker
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.schedule, size: 18),
                              label: Text('From: ${_fromTime.format(context)}'),
                              onPressed: _pickFromTime,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.schedule, size: 18),
                              label: Text('To: ${_toTime.format(context)}'),
                              onPressed: _pickToTime,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Preview: ${_buildAvailabilityString()}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],

                    const SizedBox(height: 16),
                    _buildField(
                      label: 'Study Goals',
                      controller: _goalsController,
                      enabled: _isEditing,
                      icon: Icons.track_changes_outlined,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // Subjects
                    const Text(
                      'Subjects of Interest',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._subjects.map((sub) => Chip(
                              label: Text(sub),
                              onDeleted: _isEditing
                                  ? () => setState(() => _subjects.remove(sub))
                                  : null,
                            )),
                        if (_isEditing)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Add Subject'),
                            onPressed: _showAddSubjectDialog,
                          ),
                      ],
                    ),

                    if (_isEditing) ...[
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isSaving ? null : _saveProfile,
                          child: _isSaving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Logout
              if (widget.isOwnProfile) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                  ),
                  onPressed: () async {
                    await ref.read(authRepositoryProvider).logout();
                    if (context.mounted) {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: !enabled,
        fillColor: Colors.transparent,
      ),
    );
  }

  void _showAddSubjectDialog() {
    final subCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Subject'),
        content: TextField(
          controller: subCtrl,
          decoration: const InputDecoration(hintText: 'e.g. Linear Algebra'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (subCtrl.text.isNotEmpty) {
                setState(() => _subjects.add(subCtrl.text.trim()));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}