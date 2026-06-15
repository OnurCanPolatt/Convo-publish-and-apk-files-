import 'dart:convert';

import 'package:http/http.dart' as http;

class RequestService {
  final String baseUrl;
  final http.Client _client;

  RequestService(this._client, {required this.baseUrl});

  /// 1. Arkadaşlık İsteği Gönder (POST: api/Request/send-request/{id})
  Future<bool> sendFriendRequest(String targetUserId, String token) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Request/send-request/$targetUserId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return response.statusCode == 200;
  }

  /// 2. İsteği Kabul Et (POST: api/Request/accept-request/{id})
  Future<bool> acceptFriendRequest(String targetUserId, String token) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Request/accept-request/$targetUserId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return response.statusCode == 200;
  }

  Future<bool> rejectFriendRequest(String targetUserId, String token) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Request/reject-request/$targetUserId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return response.statusCode == 200;
  }

  /// 3. İsteği İptal Et veya Reddet (POST: api/Request/remove-request/{id})
  /// Backend'de her iki işlem de 'RemoveFriendRequest' metoduna gider.
  Future<bool> removeOrRejectRequest(String targetUserId, String token) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Request/remove-request/$targetUserId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return response.statusCode == 200;
  }

  /// 4. Arkadaştan Çıkar (POST: api/Request/remove-friend/{id})
  Future<bool> removeFriend(String targetUserId, String token) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/Request/remove-friend/$targetUserId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    return response.statusCode == 200;
  }

  Future<List<dynamic>> getFriendRequests(String userId, String token) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/Request/my-requests/$userId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return List<dynamic>.from(jsonDecode(response.body));
    }
    return [];
  }
}
