import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationApiService {
  final http.Client client;
  final String baseUrl;

  NotificationApiService(this.client, {required this.baseUrl});

  // 1. Bildirimleri ve Okunmamış Sayısını Getir
  Future<Map<String, dynamic>> getMyNotifications(
    String token, {
    int skip = 0,
  }) async {
    final response = await client.get(
      Uri.parse('$baseUrl/Notification/my-notifications?skip=$skip'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      // Backend'den gelen: { notifications: [...], unreadCount: 5 }
      return jsonDecode(response.body);
    }
    throw Exception('Bildirimler yüklenemedi');
  }

  // 2. Bildirimleri Okundu Olarak İşaretle
  Future<bool> markAsRead(List<String> notificationIds, String token) async {
    final response = await client.post(
      Uri.parse('$baseUrl/Notification/mark-as-read'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(notificationIds),
    );

    return response.statusCode == 200;
  }

  Future<bool> deleteNotifications(List<String> ids, String token) async {
    final response = await client.post(
      Uri.parse(
        '$baseUrl/Notification/deletenotifications',
      ), // Controller ismine göre endpoint'i kontrol et
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(ids),
    );
    return response.statusCode == 200;
  }

  // 4. Tüm Bildirimleri Sil
  Future<bool> deleteAllNotifications(String userId, String token) async {
    final response = await client.post(
      Uri.parse('$baseUrl/Notification/deleteAllNotifications'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(userId),
    );
    return response.statusCode == 200;
  }
}
