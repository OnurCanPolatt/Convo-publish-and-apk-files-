// lib/services/begin_api_service.dart

import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:my_first_flutterapp/models/friend.dart';
// 🚨 BU IMPORTUN DOĞRU OLDUĞUNDAN EMİN OLUN:
import 'package:my_first_flutterapp/models/chat_room_model.dart';
import 'package:my_first_flutterapp/models/chat_list_item.dart';

class BeginApiService {
  final String _baseUrl = 'https://convoapp.app/api';
  final http.Client _client;

  BeginApiService(this._client);

  // --- Arkadaşlarımı Getir ---
  Future<List<UserItem>> getMyFriends(
    String currentUserId,
    String token,
  ) async {
    final url = Uri.parse('$_baseUrl/Users/getMyFriends');

    try {
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        final List<UserItem> friends = [];

        for (var jsonFriendship in jsonList) {
          final String friendUserIdInRel = jsonFriendship['friendId'] as String;
          Map<String, dynamic>? friendUserJson;

          // Arkadaşlık ilişkisinde kimin 'arkadaş' olduğunu belirle
          if (friendUserIdInRel == currentUserId) {
            friendUserJson = jsonFriendship['user'];
          } else {
            friendUserJson = jsonFriendship['friendUser'];
          }

          if (friendUserJson != null) {
            final friendModel = FriendModel.fromJson(friendUserJson);
            friends.add(friendModel.toUserItem());
          }
        }
        return friends;
      } else {
        throw Exception('Arkadaş listesi çekilemedi: ${response.statusCode}');
      }
    } catch (e) {
      log('getMyFriends Hatası: $e');
      rethrow;
    }
  }

  // --- Gruplarımı Getir ---
  Future<List<GroupItem>> getMyGroups(String userId, String token) async {
    final url = Uri.parse('$_baseUrl/Group/getMyGroups');

    // Backend string ID bekliyorsa tırnak içine alarak gönderiyoruz
    final body = jsonEncode(userId);

    try {
      log('Grup İsteği Gönderiliyor: $url');
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);

        // ChatRoomModel'den GroupItem'a dönüşüm
        return jsonList
            .map((jsonItem) => ChatRoomModel.fromJson(jsonItem).toGroupItem())
            .toList();
      } else {
        throw Exception('Grup listesi alınamadı: ${response.statusCode}');
      }
    } catch (e) {
      log('getMyGroups Hatası: $e');
      rethrow;
    }
  }

  // --- Online Kullanıcıları Getir ---
  Future<List<String>> getOnlineUsersList(String token) async {
    final url = Uri.parse('$_baseUrl/Users/onlineUsersList');

    try {
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.cast<String>();
      } else {
        throw Exception('Online kullanıcı listesi alınamadı.');
      }
    } catch (e) {
      log('OnlineUsersList Hatası: $e');
      rethrow;
    }
  }
}
