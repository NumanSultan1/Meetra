import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final secureUrl = 'https://res.cloudinary.com/dbysov7of/image/upload/v1781431666/notes/test_note_auto_real.jpg';
  final getResponse = await http.get(Uri.parse(secureUrl));
  print('Download Status: ${getResponse.statusCode}');
}
