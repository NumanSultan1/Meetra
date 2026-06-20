import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final cloudName = 'dbysov7of';
  final urlStr = 'https://res.cloudinary.com/dbysov7of/raw/upload/v1718329623/notes/test.txt';
  
  // Try fetching
  final response = await http.get(Uri.parse(urlStr));
  print('Download Response: ${response.statusCode} - ${response.body}');
}
