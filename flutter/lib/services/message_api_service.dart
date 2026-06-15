// lib/services/message_api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class MessageApiService {
  final String baseUrl = "https://convoapp.app/api/Message";

  // lib/services/message_api_service.dart
  Future<bool> saveMessageToDb(
    Map<String, dynamic> messageData,
    String token,
  ) async {
    try {
      // 🔍 DEBUG: Gönderilen mesaj detayları
      debugPrint("💾 DB'ye kaydediliyor:");
      debugPrint("   - MessageId: ${messageData['Id']}");
      debugPrint("   - SenderId: ${messageData['SenderId']}");
      debugPrint("   - ReceiverId: ${messageData['ReceiverId']}");
      debugPrint("   - Content: ${messageData['Content']}");

      final response = await http.post(
        Uri.parse("$baseUrl/saveMessage"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode(messageData),
      );

      // 🔍 HATAYI GÖRMEK İÇİN BURAYI EKLE:
      if (response.statusCode != 200) {
        debugPrint("❌ API Hatası: ${response.statusCode}");
        debugPrint("❌ Hata Detayı: ${response.body}");
        return false;
      } else {
        // ✅ FIX: Backend true/false döndürüyor, body'yi parse et!
        final bool result = jsonDecode(response.body) as bool;
        debugPrint("✅ saveMessageToDb sonucu: $result");
        if (!result) {
          debugPrint("⚠️ Backend mesajı kaydedemedi (duplicate veya hata)");
        }
        return result;
      }
    } catch (e) {
      debugPrint("❌ İstek sırasında hata oluştu: $e");
      return false;
    }
  }

  Future<List<dynamic>> getMessagesFromDb(
    String senderId,
    String receiverId,
    String token,
  ) async {
    try {
      // 🔍 DEBUG: Sorgu parametreleri
      debugPrint("🔍 DB'den mesajlar çekiliyor:");
      debugPrint("   - SenderId (ben): $senderId");
      debugPrint("   - ReceiverId (arkadaş): $receiverId");

      final response = await http.post(
        Uri.parse("$baseUrl/getMessages"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"SenderId": senderId, "ReceiverId": receiverId}),
      );
      if (response.statusCode == 200) {
        final messages = jsonDecode(response.body) as List<dynamic>;
        debugPrint("✅ DB'den ${messages.length} mesaj çekildi");
        return messages;
      } else {
        debugPrint(
          "❌ Mesajlar çekilemedi: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ GetMessages Hatası: $e");
      return [];
    }
  }

  Future<List<dynamic>> getGroupMessagesFromDb(
    String groupId,
    String token,
  ) async {
    try {
      debugPrint("🔍 DB'den grup mesajları çekiliyor - GroupId: $groupId");
      final response = await http.post(
        Uri.parse("$baseUrl/getGroupMessages"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"GroupId": groupId}),
      );
      if (response.statusCode == 200) {
        final messages = jsonDecode(response.body) as List<dynamic>;
        debugPrint("✅ DB'den ${messages.length} grup mesajı çekildi");
        return messages;
      } else {
        debugPrint(
          "❌ Grup Mesajları çekilemedi: ${response.statusCode} - ${response.body}",
        );
        return [];
      }
    } catch (e) {
      debugPrint("❌ GetGroupMessages Hatası: $e");
      return [];
    }
  }
  // lib/services/message_api_service.dart içine eklenecek yeni metodlar

  // --- P2P (Birebir) Sohbet Gizleme ---
  Future<bool> hidePrivateChat(String friendId, String token) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/HidePrivateChat"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"FriendId": friendId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ HidePrivateChat Hatası: $e");
      return false;
    }
  }

  // --- P2P (Birebir) Sohbet Gösterme ---
  // ✅ Backend'den wasUnhidden değerini parse eder
  Future<bool> unhidePrivateChat(String friendId, String token) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/UnhidePrivateChat"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"FriendId": friendId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        bool wasUnhidden = data['wasUnhidden'] ?? false;
        debugPrint("🔓 UnhidePrivateChat - wasUnhidden: $wasUnhidden");
        return wasUnhidden; // ✅ Gerçekten unhide oldu mu döndür
      }
      return false;
    } catch (e) {
      debugPrint("❌ UnhidePrivateChat Hatası: $e");
      return false;
    }
  }

  // --- Grup Sohbeti Gizleme ---
  Future<bool> hideGroupChat(String groupId, String token) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/HideGroupChat"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"GroupId": groupId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ HideGroupChat Hatası: $e");
      return false;
    }
  }

  // --- Grup Sohbeti Gösterme ---
  // ✅ Backend'den wasUnhidden değerini parse eder
  Future<bool> unhideGroupChat(String groupId, String token) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/UnhideGroupChat"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"GroupId": groupId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        bool wasUnhidden = data['wasUnhidden'] ?? false;
        debugPrint("🔓 UnhideGroupChat - wasUnhidden: $wasUnhidden");
        return wasUnhidden; // ✅ Gerçekten unhide oldu mu döndür
      }
      return false;
    } catch (e) {
      debugPrint("❌ UnhideGroupChat Hatası: $e");
      return false;
    }
  }
}
