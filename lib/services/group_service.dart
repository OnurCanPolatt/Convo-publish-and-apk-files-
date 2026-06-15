// lib/services/group_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/chat_room_model.dart';

class GroupService {
  // Mesaj servisinde yaptığın gibi, Controller adını doğrudan baseUrl'e ekliyoruz
  final String baseUrl = 'https://convoapp.app/api/Group';

  Future<bool> createGroup(Map<String, dynamic> payload, String token) async {
    try {
      // Mesaj servisiyle aynı mantık: baseUrl + endpoint adı
      final response = await http.post(
        Uri.parse("$baseUrl/createGroup"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode(payload),
      );

      // Hata detaylarını görmek için (Tıpkı mesaj servisinde yaptığın gibi)
      if (response.statusCode != 200) {
        debugPrint("❌ Grup API Hatası: ${response.statusCode}");
        debugPrint("❌ Hata Detayı: ${response.body}");
      }

      // Başarılı ise true döner
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ İstek sırasında hata oluştu: $e");
      return false;
    }
  }

  Future<ChatRoomModel?> getFreshGroupInfo(String groupId, String token) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/getFreshGroupInfo/$groupId"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        // Senin paylaştığın ChatRoomModel.fromJson metodunu kullanıyoruz
        return ChatRoomModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint("❌ GetFreshGroupInfo Hatası: $e");
      return null;
    }
  }

  // lib/services/group_service.dart

  Future<String?> uploadGroupImage(
    File imageFile,
    String groupId,
    String token,
  ) async {
    try {
      // 1. Create sayfasında çalışan aynı URL: ImageController -> uploadGroupPhoto
      final String uploadUrl =
          "https://convoapp.app/api/Image/uploadGroupPhoto/$groupId";

      var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.headers['Authorization'] = 'Bearer $token';

      // 2. KRİTİK NOKTA: Create sayfasında 'file' mı 'File' mı kullandığını kontrol et.
      // Senin ImageController'ın 'FirstOrDefault()' kullandığı için anahtar ismi çok kritik değil
      // ama 'file' (küçük harf) standarttır.
      request.files.add(
        await http.MultipartFile.fromPath(
          'file', // Burayı 'file' olarak sabitleyelim
          imageFile.path,
        ),
      );

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var json = jsonDecode(responseData);
        if (json['success'] == true) {
          // Sunucu 'data' -> 'originalImageUrl' yapısında dönüyor
          return json['data']['originalImageUrl'];
        }
      }
      return null;
    } catch (e) {
      debugPrint("❌ uploadGroupImage Hatası: $e");
      return null;
    }
  }

  Future<bool> updateGroupInfo(
    String groupId,
    String name,
    String description,
    String token, {
    String? imageUrl, // 🚀 Fotoğraf URL'ini DB'ye kaydetmek için parametre
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/updateGroup/$groupId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'description': description,
        'imageUrl': imageUrl, // 🚀 JSON gövdesine ekledik
      }),
    );
    return response.statusCode == 200;
  }

  // 2. Gruptan ayrılma metodunu ekle (Web'deki LeaveGroup karşılığı)
  Future<bool> leaveGroup(String groupId, String userId, String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/leaveGroup/$groupId/$userId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return response.statusCode == 200;
  }

  Future<bool> deleteGroup(String groupId, String token) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/deleteGroup/$groupId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    return response.statusCode == 200;
  }

  Future<bool> updateMemberRole(
    String groupId,
    String userId,
    bool makeAdmin, // Web'deki IsAdmin karşılığı
    String token,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/updateMemberAdminStatus'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chatRoomId': groupId, // Web'deki isimlendirmeyle aynı
          'userId': userId, // Web'deki isimlendirmeyle aynı
          'isAdmin': makeAdmin, // Web'deki isimlendirmeyle aynı
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ updateMemberRole Hatası: $e");
      return false;
    }
  }

  Future<bool> addMembersToGroup(
    String groupId,
    List<String> userIds,
    String token,
  ) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/addMembers/$groupId',
      ), // URL baseUrl'den geliyor (GroupController)
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(userIds),
    );
    debugPrint(
      "➕ Üye Ekleme Yanıtı: ${response.statusCode} - ${response.body}",
    );
    return response.statusCode == 200;
  }
}
