// lib/models/chat_room_model.dart
import 'package:flutter/cupertino.dart';
import 'package:my_first_flutterapp/models/chat_list_item.dart';

class ChatRoomMemberModel {
  final String userId;
  final int role;
  final DateTime joinedAt;
  final String? userName;
  final String? imageUrl;

  ChatRoomMemberModel({
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.userName,
    this.imageUrl,
  });

  factory ChatRoomMemberModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(
        json['joinedAt'] ??
            json['JoinedAt'] ??
            DateTime.now().toIso8601String(),
      );
    } catch (e) {
      parsedDate = DateTime.now();
    }

    return ChatRoomMemberModel(
      userId: json['userId'] ?? json['UserId'] ?? '',
      role: json['role'] ?? json['Role'] ?? 1,
      joinedAt: parsedDate,
      userName: json['user']?['userName'],
      imageUrl:
          json['imageUrl'] ?? json['ImageUrl'], // Üye fotoğrafı için eklendi
    );
  }
}

class ChatRoomModel {
  final String id;
  final String? name;
  final String? description;
  final String? imageUrl;
  final String? createdByUserId;
  final DateTime? createdAt; // 🚀 YENİ ALAN
  final List<ChatRoomMemberModel> members;

  ChatRoomModel({
    required this.id,
    this.name,
    this.description,
    this.imageUrl,
    this.createdByUserId,
    this.createdAt, // 🚀 Constructor'a eklendi
    required this.members,
  });

  ChatRoomModel copyWith({
    String? imageUrl,
    String? name,
    String? description,
    DateTime? createdAt, // copyWith'e de ekleyelim
  }) {
    return ChatRoomModel(
      id: this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      createdByUserId: this.createdByUserId,
      createdAt: createdAt ?? this.createdAt, // copyWith desteği
      members: this.members,
    );
  }

  factory ChatRoomModel.fromJson(Map<String, dynamic> json) {
    try {
      var memberList =
          json['members'] as List? ?? json['Members'] as List? ?? [];

      // 🚀 Tarih Parse İşlemi
      DateTime? parsedCreatedAt;
      var rawDate = json['createdAt'] ?? json['CreatedAt'];
      if (rawDate != null) {
        parsedCreatedAt = DateTime.parse(rawDate.toString());
      }

      return ChatRoomModel(
        id: (json['id'] ?? json['Id'] ?? '').toString(),
        name: json['name'] ?? json['Name'] ?? 'İsimsiz Grup',
        imageUrl: json['imageUrl'] ?? json['ImageUrl'],
        description: json['description'] ?? json['Description'] ?? '',
        createdByUserId: json['createdByUserId'] ?? json['CreatedByUserId'],
        createdAt: parsedCreatedAt, // 🚀 Buraya atama yapıldı
        members: memberList
            .map((m) => ChatRoomMemberModel.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      debugPrint("❌ ChatRoomModel Parsing Error: $e");
      return ChatRoomModel(id: '', members: []);
    }
  }

  GroupItem toGroupItem() {
    return GroupItem(
      id: id,
      name: name ?? "İsimsiz Grup",
      imageUrl: imageUrl,
      members: members
          .map(
            (m) => UserItem(
              id: m.userId,
              name: m.userName ?? "Bilinmeyen",
              imageUrl: m.imageUrl,
            ),
          )
          .toList(),
    );
  }
}
