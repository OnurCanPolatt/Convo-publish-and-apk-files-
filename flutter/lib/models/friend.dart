import 'package:my_first_flutterapp/models/chat_list_item.dart';

class FriendModel {
  final String id;
  String userName;
  final String firstName;
  final String lastName;
  String? imageUrl; // ✅ final kaldırıldı - artık değiştirilebilir

  FriendModel({
    required this.id,
    required this.userName,
    required this.firstName,
    required this.lastName,
    this.imageUrl, // ✅ required kaldırıldı
  });

  factory FriendModel.fromJson(Map<String, dynamic> json) {
    return FriendModel(
      id: (json['id'] ?? json['userId'] ?? json['Id'] ?? '').toString(),
      userName: json['userName'] ?? json['username'] ?? 'Bilinmeyen',
      firstName: json['firstName'] ?? json['firstname'] ?? '',
      lastName: json['lastName'] ?? json['lastname'] ?? '',
      imageUrl:
          json['profileImageUrl']?.toString() ?? json['imageUrl']?.toString(),
    );
  }

  UserItem toUserItem() {
    return UserItem(id: id, name: userName, imageUrl: imageUrl, online: false);
  }
}
