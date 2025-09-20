import 'dart:convert';
import 'package:http/http.dart' as http;

// Use consistent BASE_URL throughout your app
//const String BASE_URL = "http://127.0.0.1:5000"; // For local development
 const String BASE_URL = "https://smart-doc-checker-p6tt.onrender.com"; // For production

Future<Map<String, dynamic>> login(String username, String password) async {
  final url = Uri.parse('$BASE_URL/login');
  
  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(Duration(seconds: 10)); // Add timeout

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to login: ${response.body}');
    }
  } catch (e) {
    throw Exception('Network error: $e');
  }
}

Future<Map<String, dynamic>> getProfile(String token) async {
  final url = Uri.parse('$BASE_URL/profile');
  
  try {
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(Duration(seconds: 10)); // Add timeout

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch profile: ${response.statusCode}');
    }
  } catch (e) {
    throw Exception('Network error: $e');
  }
}