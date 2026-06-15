// lib/models/chat_message.dart

enum MessageType {
  Text, // 0
  Image, // 1
  File, // 2
  Audio, // 3
  Video, // 4
  Location, // 5
  System, // 6
  Document, // 7
}

class ChatMessage {
  final String text;
  final String? fileName;
  final bool isMe;
  final DateTime time;
  final String? fileUrl;
  final MessageType type; // int yerine artık Enum kullanıyoruz
  final int? fileSize;

  ChatMessage({
    required this.text,
    this.fileName,
    required this.isMe,
    required this.time,
    this.fileUrl,
    this.type = MessageType.Text,
    this.fileSize,
  });

  static MessageType parseType(dynamic type) {
    if (type == null) return MessageType.Text;
    String t = type.toString().trim().toLowerCase(); // 🚨 Küçük harfe çevir

    switch (t) {
      case "image":
        return MessageType.Image;
      case "video":
        return MessageType.Video;
      case "audio":
        return MessageType.Audio;
      case "document":
        return MessageType.Document;
      case "file":
        return MessageType.File;
      case "text":
        return MessageType.Text;
    }

    // Eğer sayı olarak gelirse (index)
    int? index = int.tryParse(t);
    if (index != null && index >= 0 && index < MessageType.values.length) {
      return MessageType.values[index];
    }
    return MessageType.Text;
  }
}
