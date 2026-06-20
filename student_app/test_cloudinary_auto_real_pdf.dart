import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final cloudName = 'dbysov7of';
  final uploadPreset = 'studysync_upload';
  final urlStr = 'https://api.cloudinary.com/v1_1/$cloudName/auto/upload';
  
  // A minimal valid PDF
  final pdfBytes = utf8.encode(
    "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
    "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n"
    "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R >>\nendobj\n"
    "4 0 obj\n<< /Length 0 >>\nstream\nendstream\nendobj\n"
    "xref\n0 5\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000214 00000 n \n"
    "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n264\n%%EOF\n"
  );
  
  final request = http.MultipartRequest('POST', Uri.parse(urlStr))
    ..fields['upload_preset'] = uploadPreset
    ..fields['folder'] = 'notes'
    ..fields['public_id'] = 'test_note_auto_real'
    ..files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: 'test.pdf'));

  final uploadRes = await request.send();
  final body = await uploadRes.stream.bytesToString();
  
  if (uploadRes.statusCode == 200) {
    final data = jsonDecode(body);
    final secureUrl = data['secure_url'];
    print('Secure URL: $secureUrl');
    
    final getResponse = await http.get(Uri.parse(secureUrl));
    print('Download Status: ${getResponse.statusCode}');
    print('Download Body snippet: ${getResponse.body.length > 50 ? getResponse.body.substring(0, 50) : getResponse.body}');
  } else {
    print('Upload failed: $body');
  }
}
