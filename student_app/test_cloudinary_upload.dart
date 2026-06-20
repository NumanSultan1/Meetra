import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final cloudName = 'dbysov7of';
  final uploadPreset = 'studysync_upload';
  final urlStr = 'https://api.cloudinary.com/v1_1/$cloudName/raw/upload';
  
  print('Uploading...');
  final request = http.MultipartRequest('POST', Uri.parse(urlStr))
    ..fields['upload_preset'] = uploadPreset
    ..fields['folder'] = 'notes'
    ..fields['public_id'] = 'test_note_401'
    ..files.add(http.MultipartFile.fromString('file', 'Dummy text file', filename: 'test_file.txt'));

  final uploadRes = await request.send();
  final body = await uploadRes.stream.bytesToString();
  print('Upload Status: ${uploadRes.statusCode}');
  print('Upload Body: $body');

  if (uploadRes.statusCode == 200) {
    final data = jsonDecode(body);
    final secureUrl = data['secure_url'];
    print('Secure URL: $secureUrl');
    
    print('Downloading...');
    final getResponse = await http.get(Uri.parse(secureUrl));
    print('Download Status: ${getResponse.statusCode}');
    print('Download Body: ${getResponse.body}');
  }
}
