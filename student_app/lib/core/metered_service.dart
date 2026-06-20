import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MeteredService {
  // Metered.ca Subdomain (e.g. meetra.metered.ca -> 'meetra')
  static const String appSubdomain = 'meetra';
  
  // Replace with your actual Metered API Key from the dashboard
  static const String apiKey = '2xO34GkQgMU_S2w2wG5avBtpbWhnygaXFtq_KXEK0ijtyXWb';

  // Default fallback ICE Servers (Google STUN) if the API call fails or key is default
  static const List<Map<String, dynamic>> defaultIceServers = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    }
  ];

  /// Fetches dynamic, time-limited TURN/STUN credentials from Metered.ca
  static Future<List<Map<String, dynamic>>> fetchIceServers() async {
    if (apiKey == 'YOUR_METERED_API_KEY') {
      debugPrint('MeteredService: API Key not set. Using default STUN servers.');
      return defaultIceServers;
    }

    try {
      final url = Uri.parse('https://$appSubdomain.metered.ca/api/v1/turn/credentials?apiKey=$apiKey');
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        debugPrint('MeteredService: Successfully fetched dynamic TURN credentials.');
        
        // Map the structure to expected formats
        return data.map((server) {
          final Map<String, dynamic> mapped = {};
          
          if (server['urls'] != null) {
            mapped['urls'] = server['urls'];
          } else if (server['url'] != null) {
            mapped['urls'] = [server['url']];
          }

          if (server['username'] != null) {
            mapped['username'] = server['username'];
          }
          if (server['credential'] != null) {
            mapped['credential'] = server['credential'];
          }

          return mapped;
        }).toList();
      } else {
        debugPrint('MeteredService: Failed to fetch credentials (HTTP ${response.statusCode}). Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('MeteredService: Error fetching TURN credentials: $e');
    }

    // Return fallback servers on any failure
    return defaultIceServers;
  }
}
