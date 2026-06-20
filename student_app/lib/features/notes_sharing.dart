import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:study_finder_shared/study_finder_shared.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../core/cloudinary_service.dart';
import 'chat_screen.dart' show FullScreenImageViewer;

// ─────────────────────────────────────────────
// FILE OPTIONS DIALOG
// ─────────────────────────────────────────────
Future<void> _showFileOptionsDialog(
    BuildContext context, String fileUrl, String fileName) async {
  final cleanUrl = fileUrl.replaceFirst(RegExp(r'^http://'), 'https://');

  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  const Color(0xFF1E293B).withValues(alpha: 0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'File Options',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  fileName,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.remove_red_eye_outlined,
                        color: AppTheme.primaryBlue),
                  ),
                  title: const Text('Preview / Open',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Open locally on your device',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _launchFileDirectly(context, cleanUrl, fileName);
                  },
                ),
                const Divider(color: Colors.white12, height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppTheme.secondaryTeal.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.download_outlined,
                        color: AppTheme.secondaryTeal),
                  ),
                  title: const Text('Download to Device',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Save a permanent copy of the file',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _downloadFileToDevice(context, cleanUrl, fileName);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Directory> getAppDownloadsDirectory() async {
  Directory? dir;
  try {
    if (Platform.isAndroid) {
      dir = await getDownloadsDirectory();
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    }
  } catch (e) {
    debugPrint('Error getting downloads directory: $e');
  }
  dir ??= await getExternalStorageDirectory();
  dir ??= await getApplicationDocumentsDirectory();
  return dir;
}

Future<String> _getUniqueFilePath(Directory directory, String fileName, String ext) async {
  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
  
  String filePath = '${directory.path}/$baseName.$ext';
  int counter = 1;
  while (await File(filePath).exists()) {
    filePath = '${directory.path}/$baseName ($counter).$ext';
    counter++;
  }
  return filePath;
}

Future<void> _downloadFileToDevice(
    BuildContext context, String fileUrl, String fileName) async {
  final httpsUrl = fileUrl.replaceFirst(RegExp(r'^http://'), 'https://');
  final urlFileName = Uri.parse(httpsUrl).path.split('/').last;
  final ext = _extFromUrl(httpsUrl, urlFileName.isNotEmpty ? urlFileName : fileName);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Downloading file...'),
          ],
        ),
        duration: Duration(seconds: 15),
      ),
    );
  }

  try {
    final response = await http.get(Uri.parse(httpsUrl).removeFragment());
    if (response.statusCode != 200) {
      if (response.statusCode == 401 && httpsUrl.contains('cloudinary.com')) {
        throw Exception('Cloudinary is blocking PDF downloads (401). Please go to Cloudinary Console -> Settings -> Security -> Restricted media types, and uncheck PDF.');
      }
      throw Exception('Download failed: ${response.statusCode}');
    }

    final downloadsDir = await getAppDownloadsDirectory();
    final safeFileName = fileName.contains('.') ? fileName : '$fileName.$ext';
    final filePath = await _getUniqueFilePath(downloadsDir, safeFileName, ext);
    
    await File(filePath).writeAsBytes(response.bodyBytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      
      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppTheme.secondaryTeal),
              SizedBox(width: 8),
              Text('Download Complete', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            'The file has been saved to your device:\n\n${filePath.split('/').last}',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              onPressed: () async {
                Navigator.pop(dCtx);
                final result = await OpenFilex.open(filePath);
                if (result.type != ResultType.done && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Cannot open file: ${result.message}')),
                  );
                }
              },
              child: const Text('Open File', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

Future<void> _launchFileDirectly(
    BuildContext context, String rawUrl, String fileName) async {
  final httpsUrl = rawUrl.replaceFirst(RegExp(r'^http://'), 'https://');

  // FIX: Extract extension from the actual URL path, not just the display title.
  // Previously _extFromUrl(url, note.title) was called with the note title like
  // "Physics Chapter 3" which has no extension, so it always returned 'bin'.
  // Now we get the real filename from the URL path first.
  final urlFileName = Uri.parse(httpsUrl).path.split('/').last;
  final ext = _extFromUrl(httpsUrl, urlFileName.isNotEmpty ? urlFileName : fileName);

  // Images → in-app full-screen viewer
  if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)) {
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FullScreenImageViewer(imageUrl: httpsUrl, title: fileName),
        ),
      );
    }
    return;
  }

  // Web: open via browser
  if (kIsWeb) {
    try {
      await launchUrl(Uri.parse(httpsUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    return;
  }

  // Mobile: download to temp directory, then open with OpenFilex
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Opening file...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );
  }

  try {
    final response = await http.get(Uri.parse(httpsUrl).removeFragment());
    if (response.statusCode != 200) {
      if (response.statusCode == 401 && httpsUrl.contains('cloudinary.com')) {
        throw Exception('Cloudinary is blocking PDF downloads (401). Please go to Cloudinary Console -> Settings -> Security -> Restricted media types, and uncheck PDF.');
      }
      throw Exception('Download failed: ${response.statusCode}');
    }

    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory();
    }
    baseDir ??= await getTemporaryDirectory();

    // FIX: Use the real filename with extension for OpenFilex to detect MIME type correctly.
    // If the display fileName has no extension, append the extracted ext.
    final safeFileName =
        fileName.contains('.') ? fileName : '$fileName.$ext';
    final filePath = '${baseDir.path}/$safeFileName';
    await File(filePath).writeAsBytes(response.bodyBytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Unsupported File',
              style: TextStyle(color: Colors.white)),
          content: Text(
            'No local app found to open this $ext file. Would you like to open it in a web browser?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue),
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Open Browser',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await launchUrl(Uri.parse(httpsUrl),
            mode: LaunchMode.externalApplication);
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file: $e')),
      );
    }
  }
}

/// Extract file extension — checks URL fragment, query param, filename, URL path.
/// FIX: Now also strips Cloudinary transformation segments and version prefixes
/// so that URLs like https://res.cloudinary.com/demo/image/upload/v1234/myfile.pdf
/// correctly return 'pdf'.
String _extFromUrl(String url, String fileName) {
  // 1. Fragment parameter (#ext=pdf)
  try {
    final uri = Uri.parse(url);
    final frag = uri.fragment;
    if (frag.startsWith('ext=')) return frag.substring(4).toLowerCase();
    if (frag.isNotEmpty && !frag.contains('=')) return frag.toLowerCase();
  } catch (_) {}

  // 2. Query parameter 'ext'
  try {
    final uri = Uri.parse(url);
    final extParam = uri.queryParameters['ext'];
    if (extParam != null && extParam.isNotEmpty) return extParam.toLowerCase();
  } catch (_) {}

  // 3. Filename extension (from the passed fileName, e.g. the URL's last path segment)
  final nameParts = fileName.split('.');
  if (nameParts.length > 1) {
    final possibleExt = nameParts.last.toLowerCase().split('?').first;
    if (possibleExt.length >= 2 && possibleExt.length <= 5) {
      return possibleExt;
    }
  }

  // 4. URL path extension
  try {
    final urlPath = Uri.parse(url).path;
    final pathParts = urlPath.split('.');
    if (pathParts.length > 1) {
      return pathParts.last.split('?').first.toLowerCase();
    }
  } catch (_) {}

  return 'bin';
}

// ─────────────────────────────────────────────
// MAIN WIDGET
// ─────────────────────────────────────────────
class NotesSharingTab extends ConsumerStatefulWidget {
  const NotesSharingTab({super.key});

  @override
  ConsumerState<NotesSharingTab> createState() => _NotesSharingTabState();
}

class _NotesSharingTabState extends ConsumerState<NotesSharingTab> {
  final _searchController = TextEditingController();
  List<NoteModel> _notes = [];
  bool _isLoading = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String _selectedSemester = 'Semester 1';

  String? _selectedSubject;

  final List<String> _semesters = [
    'Semester 1',
    'Semester 2',
    'Semester 3',
    'Semester 4',
    'Semester 5',
    'Semester 6',
    'Semester 7',
    'Semester 8',
  ];

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    try {
      final results = await ref.read(noteRepositoryProvider).getNotes(
            semester: _selectedSemester,
            query: _searchController.text.trim().isEmpty
                ? null
                : _searchController.text.trim(),
          );
      setState(() => _notes = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load notes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, int> get _subjectFolders {
    final map = <String, int>{};
    for (final n in _notes) {
      if (n.subject.isNotEmpty) {
        map[n.subject] = (map[n.subject] ?? 0) + 1;
      }
    }
    return map;
  }

  List<NoteModel> get _notesInSelectedSubject {
    if (_selectedSubject == null) return [];
    return _notes
        .where((n) =>
            n.subject.toLowerCase() == _selectedSubject!.toLowerCase())
        .toList();
  }

  Future<void> _pickAndUploadNote() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: kIsWeb);
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final pickedFile = result.files.first;
    final fileName = pickedFile.name;
    final sizeInBytes = pickedFile.size;
    final sizeInMB = sizeInBytes / (1024 * 1024);
    final sizeString = sizeInMB >= 1.0
        ? '${sizeInMB.toStringAsFixed(1)} MB'
        : '${(sizeInBytes / 1024).toStringAsFixed(0)} KB';

    final titleCtrl = TextEditingController(
        text: fileName.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final subjectCtrl =
        TextEditingController(text: _selectedSubject ?? '');
    final teacherCtrl = TextEditingController();
    String chosenSemester = _selectedSemester;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => PremiumDialog(
        title: 'Upload Note',
        icon: Icons.upload_file,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insert_drive_file, color: Colors.redAccent, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$fileName ($sizeString)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (sizeInMB > 15.0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Large file. Upload may take a while.',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade300),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _glassField(titleCtrl, 'Note Title'),
            const SizedBox(height: 12),
            _glassField(subjectCtrl, 'Subject Name (e.g. Physics)'),
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
                  items: _semesters
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setInner(() => chosenSemester = val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            _glassField(teacherCtrl, 'Teacher Name *'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
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
            onPressed: () {
              if (titleCtrl.text.trim().isNotEmpty &&
                  subjectCtrl.text.trim().isNotEmpty &&
                  teacherCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields (Title, Subject, Teacher)')),
                );
              }
            },
            child: const Text('Upload', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      String downloadUrl;
      if (kIsWeb) {
        final bytes = pickedFile.bytes!;
        setState(() => _uploadProgress = 0.3);
        downloadUrl =
            await CloudinaryService.uploadFile(bytes, fileName);
      } else {
        final file = File(pickedFile.path!);
        setState(() => _uploadProgress = 0.3);
        downloadUrl =
            await CloudinaryService.uploadFile(file, fileName);
      }

      setState(() => _uploadProgress = 0.7);

      final ext = fileName.split('.').last.toLowerCase();
      downloadUrl = '$downloadUrl#ext=$ext';

      final currentUser = ref.read(authStateProvider).value;
      final currentUserId = currentUser?.id ?? '';
      final currentUserName = currentUser?.name.isNotEmpty == true
          ? currentUser!.name
          : (currentUser?.email.split('@').first ?? 'Unknown');

      final note = NoteModel(
        id: '',
        uploadedBy: currentUserId,
        uploaderName: currentUserName,
        title: titleCtrl.text.trim(),
        fileUrl: downloadUrl,
        subject: subjectCtrl.text.trim(),
        semester: chosenSemester,
        teacher: teacherCtrl.text.trim(),
        groupId: '',
        uploadedAt: DateTime.now(),
      );

      await ref.read(noteRepositoryProvider).uploadNote(note);
      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note uploaded successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _selectedSemester = chosenSemester;
          _selectedSubject = subjectCtrl.text.trim();
        });
        _loadNotes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showNoteOptions(NoteModel note) {
    final currentUserId =
        ref.read(authRepositoryProvider).currentUser?.id ?? '';
    final isOwner = note.uploadedBy == currentUserId;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color:
                  const Color(0xFF1E293B).withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  note.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${note.subject} · ${note.semester}',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                _optionTile(
                  icon: Icons.link,
                  iconColor: AppTheme.primaryBlue,
                  label: 'Copy Secure Link',
                  subtitle: 'Share the file URL with others',
                  onTap: () {
                    final httpsUrl = note.fileUrl
                        .replaceFirst(RegExp(r'^http://'), 'https://');
                    Clipboard.setData(ClipboardData(text: httpsUrl));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Link copied to clipboard!')),
                    );
                  },
                ),
                if (isOwner) ...[
                  const Divider(color: Colors.white12, height: 24),
                  _optionTile(
                    icon: Icons.delete_outline,
                    iconColor: Colors.redAccent,
                    label: 'Delete Note',
                    subtitle: 'Permanently remove this note',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E293B),
                          title: const Text('Delete Note',
                              style: TextStyle(color: Colors.white)),
                          content: const Text(
                            'Are you sure you want to delete this note? This cannot be undone.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dCtx, false),
                              child: const Text('Cancel',
                                  style:
                                      TextStyle(color: Colors.white70)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent),
                              onPressed: () =>
                                  Navigator.pop(dCtx, true),
                              child: const Text('Delete',
                                  style:
                                      TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        try {
                          await ref
                              .read(noteRepositoryProvider)
                              .deleteNote(note.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Note deleted.'),
                                  backgroundColor: Colors.orange),
                            );
                            _loadNotes();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Delete failed: $e')),
                            );
                          }
                        }
                      }
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

  Widget _glassField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide:
              const BorderSide(color: AppTheme.primaryBlue),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _optionTile({
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
              width: 42,
              height: 42,
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
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  IconData _iconForExt(String ext) {
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Icons.image;
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Icons.videocam;
    if (['mp3', 'wav', 'aac'].contains(ext)) return Icons.audiotrack;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Color _colorForExt(String ext) {
    if (ext == 'pdf') return Colors.redAccent;
    if (['doc', 'docx'].contains(ext)) return const Color(0xFF2B7CF4);
    if (['ppt', 'pptx'].contains(ext)) return Colors.deepOrange;
    if (['xls', 'xlsx'].contains(ext)) return Colors.green;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Colors.purple;
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Colors.teal;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        onPressed: _isUploading ? null : _pickAndUploadNote,
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.upload_file),
        label: Text(_isUploading ? 'Uploading...' : 'Upload Note'),
      ),
      body: Column(
        children: [
          if (_isUploading)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Uploading file...',
                      style:
                          TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.white12,
                    color: AppTheme.primaryBlue,
                  ),
                ],
              ),
            ),

          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _semesters.length,
              itemBuilder: (context, idx) {
                final sem = _semesters[idx];
                final isSelected = _selectedSemester == sem;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(sem),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryBlue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedSemester = sem;
                        _selectedSubject = null;
                      });
                      _loadNotes();
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedSubject == null
                    ? _buildFolderView()
                    : _buildNotesListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderView() {
    final folders = _subjectFolders;

    if (folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open,
                size: 72, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              'No notes in $_selectedSemester yet.\nTap + to upload the first one!',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
      ),
      itemCount: folders.length,
      itemBuilder: (context, idx) {
        final subject = folders.keys.elementAt(idx);
        final count = folders[subject]!;
        return GestureDetector(
          onTap: () => setState(() => _selectedSubject = subject),
          child: GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color:
                        AppTheme.primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.folder_rounded,
                      color: AppTheme.primaryBlue, size: 30),
                ),
                const Spacer(),
                Text(
                  subject,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? "note" : "notes"}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.secondaryTeal),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotesListView() {
    final notes = _notesInSelectedSubject;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon:
                    const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: () =>
                    setState(() => _selectedSubject = null),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedSubject!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: Colors.white),
                    ),
                    Text(
                      '$_selectedSemester · ${notes.length} ${notes.length == 1 ? "note" : "notes"}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search in $_selectedSubject...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
            ),
            onChanged: (_) => _loadNotes(),
          ),
        ),

        if (notes.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No notes found.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: notes.length,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              itemBuilder: (context, idx) {
                final note = notes[idx];

                // FIX: Extract extension from the actual URL filename, not note.title.
                // note.title is a display name like "Physics Chapter 3" with no extension.
                // Using it caused _extFromUrl to always return 'bin', making all files
                // fail to open because OpenFilex couldn't determine the MIME type.
                final urlFileName =
                    Uri.parse(note.fileUrl).path.split('/').last;
                final fileExt = _extFromUrl(
                    note.fileUrl,
                    urlFileName.isNotEmpty ? urlFileName : note.title);

                final displayName = note.uploaderName.isNotEmpty
                    ? note.uploaderName
                    : (note.uploadedBy.length > 8
                        ? '${note.uploadedBy.substring(0, 8)}...'
                        : note.uploadedBy);

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: GestureDetector(
                    onTap: () {
                      // FIX: Pass the real URL filename so the file dialog
                      // and download use the correct extension.
                      final displayFileName = urlFileName.isNotEmpty
                          ? urlFileName
                          : note.title;
                      _showFileOptionsDialog(
                          context, note.fileUrl, displayFileName);
                    },
                    onLongPress: () => _showNoteOptions(note),
                    child: GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _colorForExt(fileExt)
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconForExt(fileExt),
                              color: _colorForExt(fileExt),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.title,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Teacher: ${note.teacher}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'By: $displayName',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white38),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.open_in_new,
                                color: AppTheme.primaryBlue,
                                size: 20),
                            tooltip: 'Open',
                            onPressed: () {
                              final displayFileName =
                                  urlFileName.isNotEmpty
                                      ? urlFileName
                                      : note.title;
                              _showFileOptionsDialog(context,
                                  note.fileUrl, displayFileName);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}