class ChatListItem {
  final String id;
  String _name;
  final String subTitle;
  final bool isOnline;
  final int unreadMessageCount;
  final DateTime? lastMessageTime;
  String? imageUrl;

  ChatListItem({
    required this.id,
    required String name,
    required this.subTitle,
    this.isOnline = false,
    this.unreadMessageCount = 0,
    this.lastMessageTime,
    this.imageUrl,
  }) : _name = name;

  // ✅ Getter ve Setter - name değiştirilebilir olmalı
  String get name => _name;
  set name(String value) => _name = value;
}

class UserItem extends ChatListItem {
  UserItem({
    required String id,
    required String name,
    bool online = false,
    String? imageUrl,
  }) : super(
         id: id,
         name: name,
         subTitle: "Kullanıcı",
         isOnline: online,
         imageUrl: imageUrl,
       );
}

class GroupItem extends ChatListItem {
  final List<UserItem> members;

  GroupItem({
    required String id,
    required String name,
    this.members = const [],
    String? imageUrl,
  }) : super(
         id: id,
         name: name,
         subTitle: "Grup",
         isOnline: false,
         imageUrl: imageUrl,
       );
}
