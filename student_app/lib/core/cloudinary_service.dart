import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CloudinaryService {
  static const String cloudName = 'dbysov7of';
  static const String uploadPreset = 'studysync_upload';

  // Upload profile picture — works on Web + Mobile
  static Future<String> uploadImage(dynamic imageFile) async {
    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    if (kIsWeb) {
      // Web: imageFile is Uint8List
      final bytes = imageFile as Uint8List;
      final base64Image = base64Encode(bytes);
      final response = await http.post(url, body: {
        'file': 'data:image/jpeg;base64,$base64Image',
        'upload_preset': uploadPreset,
        'folder': 'profile_pictures',
      });
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['secure_url'];
      throw Exception('Upload failed: ${data['error']['message']}');
    } else {
      // Mobile: imageFile is File
      final file = imageFile as File;
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = 'profile_pictures'
        ..files.add(await http.MultipartFile.fromPath(
          'file', 
          file.path, 
          filename: file.path.split(RegExp(r'[/\\]')).last,
        ));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);
      if (response.statusCode == 200) return data['secure_url'];
      throw Exception('Upload failed: ${data['error']['message']}');
    }
  }

  // Upload PDF/file for notes — works on Web + Mobile
  static Future<String> uploadFile(dynamic file, String fileName) async {
    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/raw/upload',
    );

    if (kIsWeb) {
      final bytes = file as Uint8List;
      final base64File = base64Encode(bytes);
      final response = await http.post(url, body: {
        'file': 'data:application/octet-stream;base64,$base64File',
        'upload_preset': uploadPreset,
        'folder': 'notes',
      });
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return data['secure_url'];
      throw Exception('Upload failed: ${data['error']['message']}');
    } else {
      final f = file as File;
      final request = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = 'notes'
        ..fields['public_id'] = fileName.split(RegExp(r'[/\\]')).last
        ..files.add(await http.MultipartFile.fromPath(
          'file', 
          f.path,
          filename: f.path.split(RegExp(r'[/\\]')).last,
        ));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body);
      if (response.statusCode == 200) return data['secure_url'];
      throw Exception('Upload failed: ${data['error']['message']}');
    }
  }
}