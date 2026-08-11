import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CloudinaryService {
  static const String cloudName = 'dbysov7of';
  static const String uploadPreset = 'studysync_upload';

  /// Local file type validation (allowing PDFs, images, and audio only, preventing executables)
  static void validateFileType(String fileName) {
    final lowerName = fileName.toLowerCase();

    // Check if it's an executable
    final executables = ['.exe', '.msi', '.apk', '.bin', '.sh', '.bat', '.cmd', '.com', '.vbs', '.js', '.ts', '.jar', '.elf'];
    for (final ext in executables) {
      if (lowerName.endsWith(ext)) {
        throw Exception('Security violation: Executable files are not allowed.');
      }
    }

    // Must be PDF, image, or audio only
    final allowedExtensions = [
      // PDF
      '.pdf',
      // Images
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif',
      // Audio
      '.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac', '.wma', '.amr', '.webm'
    ];

    bool isAllowed = false;
    for (final ext in allowedExtensions) {
      if (lowerName.endsWith(ext)) {
        isAllowed = true;
        break;
      }
    }

    if (!isAllowed) {
      throw Exception('Allowed file types: PDFs, Images, and Audio files only.');
    }
  }

  /// Unified chunked uploader — works on Web + Mobile, handles files up to 700MB, provides progress.
  static Future<String> uploadFileChunked({
    required dynamic file, // Uint8List (Web) or File (Mobile)
    required String fileName,
    required String folder,
    void Function(double progress)? onProgress,
  }) async {
    validateFileType(fileName);

    final String uploadUrl = 'https://api.cloudinary.com/v1_1/$cloudName/raw/upload';
    final int chunkSize = 6 * 1024 * 1024; // 6MB chunk size
    final String uniqueId = DateTime.now().millisecondsSinceEpoch.toString() + '_' + fileName.hashCode.toString();

    int totalBytes = 0;
    List<int> fileBytes = [];
    RandomAccessFile? raf;

    if (kIsWeb) {
      fileBytes = file as Uint8List;
      totalBytes = fileBytes.length;
    } else {
      final f = file as File;
      totalBytes = await f.length();
    }

    int start = 0;
    String secureUrl = '';

    try {
      if (!kIsWeb) {
        final f = file as File;
        raf = await f.open(mode: FileMode.read);
      }

      while (start < totalBytes) {
        final int end = (start + chunkSize < totalBytes) ? start + chunkSize : totalBytes;
        final int currentChunkSize = end - start;

        List<int> chunkData;
        if (kIsWeb) {
          chunkData = fileBytes.sublist(start, end);
        } else {
          await raf!.setPosition(start);
          chunkData = await raf.read(currentChunkSize);
        }

        // Prepare request
        final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
          ..headers['X-Unique-Upload-Id'] = uniqueId
          ..headers['Content-Range'] = 'bytes $start-${end - 1}/$totalBytes'
          ..fields['upload_preset'] = uploadPreset
          ..fields['folder'] = folder
          ..fields['public_id'] = fileName.split(RegExp(r'[/\\]')).last;

        request.files.add(http.MultipartFile.fromBytes(
          'file',
          chunkData,
          filename: fileName.split(RegExp(r'[/\\]')).last,
        ));

        final response = await request.send();
        final body = await response.stream.bytesToString();
        final data = jsonDecode(body);

        if (response.statusCode == 200 || response.statusCode == 201) {
          if (end == totalBytes) {
            secureUrl = data['secure_url'] ?? '';
          }
        } else {
          throw Exception('Upload chunk failed: ${data['error']?['message'] ?? response.reasonPhrase}');
        }

        start = end;
        if (onProgress != null) {
          onProgress(start / totalBytes);
        }
      }
    } finally {
      if (raf != null) {
        await raf.close();
      }
    }

    if (secureUrl.isEmpty) {
      throw Exception('Upload failed to return secure URL.');
    }
    return secureUrl;
  }

  // Upload profile picture — works on Web + Mobile
  static Future<String> uploadImage(dynamic imageFile, [String? fileName]) async {
    final name = fileName ?? (imageFile is File ? imageFile.path.split(RegExp(r'[/\\]')).last : 'profile_picture.jpg');
    return uploadFileChunked(
      file: imageFile,
      fileName: name,
      folder: 'profile_pictures',
    );
  }

  // Upload PDF/file for notes — works on Web + Mobile
  static Future<String> uploadFile(dynamic file, String fileName, {void Function(double progress)? onProgress}) async {
    return uploadFileChunked(
      file: file,
      fileName: fileName,
      folder: 'notes',
      onProgress: onProgress,
    );
  }
}
