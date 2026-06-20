import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final cloudName = 'dbysov7of';
  final uploadPreset = 'studysync_upload';
  final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/raw/upload');

  final request = http.MultipartRequest('POST', url)
    ..fields['upload_preset'] = uploadPreset
    ..fields['folder'] = 'notes'
    ..fields['public_id'] = 'test_note_123'
    ..files.add(http.MultipartFile.fromString('file', 'Hello World', filename: 'test.txt'));

  final response = await request.send();
  final body = await response.stream.bytesToString();
  print('Upload Response: ${response.statusCode} - $body');
  
  if (response.statusCode == 200) {
    final data = jsonDecode(body);
    final secureUrl = data['secure_url'];
    print('Secure URL: $secureUrl');
    
    final getResponse = await http.get(Uri.parse(secureUrl));
    print('Download Response: ${getResponse.statusCode} - ${getResponse.body}');
  }
}
