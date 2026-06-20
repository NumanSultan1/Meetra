import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final cloudName = 'dbysov7of';
  final uploadPreset = 'studysync_upload';
  final urlStr = 'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
  
  final pdfBytes = [37, 80, 68, 70, 45, 49, 46, 52, 10, 37, 226, 227, 207, 211, 10, 49, 32, 48, 32, 111, 98, 106, 10];
  
  final request = http.MultipartRequest('POST', Uri.parse(urlStr))
    ..fields['upload_preset'] = uploadPreset
    ..fields['folder'] = 'notes'
    ..fields['public_id'] = 'test_note_auto'
    ..files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: 'test.pdf'));

  final uploadRes = await request.send();
  final body = await uploadRes.stream.bytesToString();
  
  if (uploadRes.statusCode == 200) {
    final data = jsonDecode(body);
    final secureUrl = data['secure_url'];
    print('Secure URL: $secureUrl');
    
    final getResponse = await http.get(Uri.parse(secureUrl));
    print('Download Status: ${getResponse.statusCode}');
    print('Download Body: ${getResponse.body}');
  } else {
    print('Upload failed: $body');
  }
}
