// lib/providers/chat_provider.dart
import 'package:flutter/material.dart';
import '../models/chat_list_item.dart';
import '../models/chat_room_model.dart';

class ChatProvider extends ChangeNotifier {
  // Key: UserId, Value: Mesaj Listesi (Web'deki Cache gibi)
  final Map<String, List<Map<String, dynamic>>> _chatCache = {};

  // Key: UserId, Value: Okunmamış mesaj sayısı (P2P için)
  final Map<String, int> _unreadCounts = {};

  // ✅ YENİ: Key: GroupId, Value: Okunmamış mesaj sayısı (Grup için)
  final Map<String, int> _unreadGroupCounts = {};

  // 🚀 YENİ: Arkadaşların isimlerini ve profil resimlerini tutan cache
  // Key: UserId, Value: Name
  final Map<String, String> _userNameCache = {};
  // Key: UserId, Value: ImageUrl (İstersen kullanabilirsin)
  final Map<String, String?> _userImageCache = {};

  String? _activeChatUserId; // Şu an ekranda açık olan kişinin ID'si

  final Map<String, ChatRoomModel> _groupMetadata = {};

  // Getters
  Map<String, List<Map<String, dynamic>>> get chatCache => _chatCache;
  int getUnreadCount(String userId) => _unreadCounts[userId] ?? 0;
  int getUnreadGroupCount(String groupId) =>
      _unreadGroupCounts[groupId] ?? 0; // ✅ YENİ
  Map<String, String?> get userImageCache => _userImageCache;

  // 🚀 YENİ: Arkadaş listesi çekildiğinde isimleri belleğe atan metod
  void updateUserNameCache(List<UserItem> friends) {
    for (var friend in friends) {
      _userNameCache[friend.id.toLowerCase()] = friend.name;
      _userImageCache[friend.id.toLowerCase()] = friend.imageUrl;
    }
    debugPrint(
      "👥 ChatProvider: ${friends.length} arkadaşın ismi belleğe alındı.",
    );
    notifyListeners();
  }

  // 🚀 YENİ: ID'den hem Grup hem de Kullanıcı ismini bulan MERKEZİ METOD
  // IncomingCallOverlay ve diğer yerlerde bunu kullanacağız
  String getUserOrGroupName(String? id, {required bool isGroup}) {
    if (id == null) return "Bilinmeyen";

    if (isGroup) {
      // Grup ismini getir
      return _groupMetadata[id]?.name ?? "Bilinmeyen Grup";
    } else {
      // 🔍 Kullanıcı ismini cache'den bul (küçük harfe çevirerek ara)
      return _userNameCache[id.toLowerCase()] ?? "Bilinmeyen Kullanıcı";
    }
  }

  // Bir sayfa açıldığında orayı "aktif" işaretle ve sayacı sıfırla
  void setActiveChat(String? userId) {
    debugPrint("🎯 [PROVIDER] Aktif Sohbet Değişti: $userId");
    _activeChatUserId = userId;
    if (userId != null) {
      // ✅ FIX: Hem P2P hem de Grup badge'ini sıfırla
      _unreadCounts[userId] = 0; // P2P sayacı sıfırlandı
      _unreadGroupCounts[userId] = 0; // Grup sayacı sıfırlandı
      debugPrint("🎯 [PROVIDER] Badge sıfırlandı: P2P=0, Grup=0");
      notifyListeners();
    }
  }

  void addMessage(
    String chatWithId,
    Map<String, dynamic> messageData,
    bool isIncoming,
  ) {
    // 1. Chat listesi yoksa oluştur
    if (!_chatCache.containsKey(chatWithId)) {
      _chatCache[chatWithId] = [];
    }

    // 2. Veri Normalizasyonu
    final String mId = (messageData["id"] ?? messageData["Id"] ?? "")
        .toString();

    // ✅ DÜZELTME: Duplicate kontrolü
    if (_chatCache[chatWithId]!.any(
      (m) => (m["id"] ?? m["Id"] ?? "").toString() == mId,
    )) {
      debugPrint(
        "🚫 ChatProvider: Duplicate mesaj engellendi - MessageId: $mId",
      );
      // ✅ CRITICAL FIX: UI consistency için notify et!
      notifyListeners();
      return;
    }

    final String senderId =
        (messageData["senderId"] ?? messageData["SenderId"] ?? "").toString();
    final String content =
        (messageData["content"] ??
                messageData["Content"] ??
                messageData["newMessage"] ??
                "")
            .toString();
    final bool isGroup =
        messageData['isGroupMessage'] ?? messageData['IsGroupMessage'] ?? false;

    // 3. FileSize Güvenli Parse
    dynamic rawSize =
        messageData["fileSize"] ??
        messageData["FileSize"] ??
        messageData["filesize"];
    int? fileSize;
    if (rawSize != null) {
      if (rawSize is int) {
        fileSize = rawSize;
      } else if (rawSize is double) {
        fileSize = rawSize.toInt();
      } else {
        fileSize = int.tryParse(rawSize.toString());
      }
    }

    // 4. SentAt Güvenli Parse
    String rawDate =
        (messageData["sentAt"] ??
                messageData["SentAt"] ??
                DateTime.now().toUtc().toIso8601String())
            .toString();

    final normalizedMsg = {
      "id": mId,
      "senderId": senderId,
      "content": content,
      "sentAt": rawDate,
      "type": messageData["type"] ?? messageData["Type"] ?? 0,
      "fileUrl": messageData["fileUrl"] ?? messageData["FileUrl"],
      "fileData": messageData["fileData"] ?? messageData["FileData"],
      "fileSize": fileSize,
      "isGroupMessage": isGroup,
    };

    // 5. Mesajı Ekle ve Sırala
    _chatCache[chatWithId]!.add(normalizedMsg);

    try {
      _chatCache[chatWithId]!.sort((a, b) {
        DateTime dtA =
            DateTime.tryParse(a["sentAt"]?.toString() ?? "") ?? DateTime(1970);
        DateTime dtB =
            DateTime.tryParse(b["sentAt"]?.toString() ?? "") ?? DateTime(1970);
        return dtA.compareTo(dtB);
      });
    } catch (e) {
      debugPrint("❌ ChatProvider Sort Hatası: $e");
    }

    // 6. Badge Yönetimi ve Silinen Chat'in Tekrar Eklenmesi
    if (isIncoming) {
      // ✅ YENİ: Eğer bu sohbet daha önce silinmişse, message_screen'e bildir
      bool wasHidden = _chatCache[chatWithId]!.length == 1; // İlk mesaj mı?

      if (_activeChatUserId != chatWithId) {
        if (isGroup) {
          _unreadGroupCounts[chatWithId] =
              (_unreadGroupCounts[chatWithId] ?? 0) + 1;
        } else {
          _unreadCounts[chatWithId] = (_unreadCounts[chatWithId] ?? 0) + 1;
        }
      }

      // ✅ KRİTİK: Eğer bu silinen bir chat'ten ilk mesaj geliyorsa, listeyi tazele
      if (wasHidden) {
        debugPrint(
          "🔄 Silinen sohbetten mesaj geldi, liste tazelenecek: $chatWithId",
        );
        // Bu callback'i SignalrService'ten çağırmalıyız (aşağıda ekleyeceğiz)
      }
    }

    // 7. Arayüzü Tetikle
    notifyListeners();
    debugPrint(
      "✅ Mesaj İşlendi: $mId | Chat: $chatWithId | Unread: ${isGroup ? _unreadGroupCounts[chatWithId] : _unreadCounts[chatWithId]}",
    );
  }

  void setMessages(String friendId, List<dynamic> messages) {
    _chatCache[friendId] = messages.map((m) {
      final dynamic rawFileSize = m["fileSize"] ?? m["FileSize"];
      final int? fileSize = rawFileSize != null
          ? (rawFileSize is int
                ? rawFileSize
                : int.tryParse(rawFileSize.toString()))
          : null;

      final int? fileDataSize = m["fileData"] != null
          ? (m["fileData"]["fileSize"] ?? m["fileData"]["FileSize"])
          : null;

      return {
        "id": (m["id"] ?? m["Id"]).toString(),
        "senderId": (m["senderId"] ?? m["SenderId"]).toString(),
        "content": m["content"] ?? m["Content"] ?? "",
        "sentAt":
            m["sentAt"] ??
            m["SentAt"] ??
            DateTime.now().toUtc().toIso8601String(),
        "type": m["type"] ?? m["Type"] ?? 0,
        "fileUrl": m["fileUrl"] ?? m["FileUrl"],
        "fileData": m["fileData"] ?? m["FileData"],
        "fileSize": fileSize ?? fileDataSize,
      };
    }).toList();

    // ✅ KRİTİK DÜZELTME: Sıralamayı korumaya alıyoruz
    try {
      _chatCache[friendId]!.sort((a, b) {
        DateTime dtA =
            DateTime.tryParse(a["sentAt"]?.toString() ?? "") ?? DateTime(1970);
        DateTime dtB =
            DateTime.tryParse(b["sentAt"]?.toString() ?? "") ?? DateTime(1970);
        return dtA.compareTo(dtB);
      });
    } catch (e) {
      debugPrint("❌ ChatProvider setMessages SORT HATASI: $e");
    }

    notifyListeners();
  }

  void updateGroupMetadataFromItems(List<GroupItem> items) {
    for (var item in items) {
      _groupMetadata[item.id] = ChatRoomModel(
        id: item.id,
        name: item.name,
        members: [],
      );
    }
    debugPrint("🗂️ ChatProvider: ${items.length} grubun ismi belleğe alındı.");
    notifyListeners();
  }

  // ID'ye göre grup ismini döndüren eski fonksiyon (Geriye dönük uyumluluk için koruduk)
  String getGroupName(String? groupId) {
    if (groupId == null) return "Bilinmeyen Grup";
    return _groupMetadata[groupId]?.name ?? "Bilinmeyen Grup (ID: $groupId)";
  }

  // lib/providers/chat_provider.dart içine ekle
  void syncMessages(String chatWithId, List<dynamic> apiMessages) {
    if (!_chatCache.containsKey(chatWithId)) {
      _chatCache[chatWithId] = [];
    }

    final List<Map<String, dynamic>> currentMessages = _chatCache[chatWithId]!;
    bool hasNewData = false;

    for (var m in apiMessages) {
      final String mId = (m["id"] ?? m["Id"]).toString();

      // ✅ DUPLICATE KONTROLÜ: Eğer mesaj ID'si cache'de yoksa listeye ekle
      if (!currentMessages.any((msg) => msg["id"] == mId)) {
        // Veriyi normalize et (addMessage metodundaki yapıyla aynı olmalı)
        currentMessages.add({
          "id": mId,
          "senderId": (m["senderId"] ?? m["SenderId"]).toString(),
          "content": m["content"] ?? m["Content"] ?? "",
          "sentAt": m["sentAt"] ?? m["SentAt"],
          "type": m["type"] ?? m["Type"] ?? 0,
          "fileUrl": m["fileUrl"] ?? m["FileUrl"],
          "fileSize":
              m["fileSize"] ??
              m["FileSize"] ??
              (m["fileData"] != null ? m["fileData"]["fileSize"] : null),
          "isGroupMessage": m["chatRoomId"] != null || m["ChatRoomId"] != null,
        });
        hasNewData = true;
      }
    }

    notifyListeners();
  }
}
