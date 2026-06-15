class NotificationModel {
  final String id;
  final String senderId;
  String senderName;
  String senderImageUrl;
  final String message;
  final String date;
  bool isRead;
  final bool isRequest;
  String? lastUpdate; // 🚀 Cache kırmak için

  NotificationModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderImageUrl,
    required this.message,
    required this.date,
    this.isRead = false,
    required this.isRequest,
    this.lastUpdate,
  });

  // Backend'den gelen Map'i Object'e çevirir
  factory NotificationModel.fromMap(
    Map<String, dynamic> map, {
    bool isRequest = false,
  }) {
    return NotificationModel(
      id: (map['id'] ?? map['Id'] ?? "").toString(),
      senderId: (map['senderId'] ?? map['SenderId'] ?? "").toString(),
      senderName: map['senderName'] ?? map['SenderName'] ?? "Bilinmeyen",
      senderImageUrl: map['senderImageUrl'] ?? map['SenderImageUrl'] ?? "",
      message: map['message'] ?? map['Message'] ?? "",
      date: map['date'] ?? map['Date'] ?? DateTime.now().toIso8601String(),
      isRead: map['isRead'] ?? map['IsRead'] ?? false,
      isRequest: isRequest,
      lastUpdate: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  // 🚀 İşte bu sihirli metot: ExploreUsers'daki gibi nesneyi günceller
  NotificationModel copyWith({
    String? name,
    String? imageUrl,
    String? updateTag,
  }) {
    return NotificationModel(
      id: id,
      senderId: senderId,
      senderName: name ?? senderName,
      senderImageUrl: imageUrl ?? senderImageUrl,
      message: message,
      date: date,
      isRead: isRead,
      isRequest: isRequest,
      lastUpdate: updateTag ?? lastUpdate,
    );
  }
}
