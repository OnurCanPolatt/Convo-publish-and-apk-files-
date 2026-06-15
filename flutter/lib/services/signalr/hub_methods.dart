import 'package:signalr_netcore/signalr_client.dart';
import 'package:flutter/material.dart';

class HubMethods {
  final HubConnection? _connection;
  String? currentUserId;
  HubMethods(this._connection);

  // Genel bağlantı kontrolü
  bool _ensureConnection() =>
      _connection?.state == HubConnectionState.Connected;

  Future<void> registerUser(String userId) async {
    if (!_ensureConnection()) return;
    currentUserId = userId; // 🚀 Giriş yapan ID'yi burada sakla
    await _connection!.invoke("RegisterUser", args: [userId]);
  }

  Future<bool> sendMessage(
    String receiverId,
    String? newMessage,
    String? fileUrl,
    String? messageType,
    int? filesize,
    bool isGroupMessage,
    String? messageId,
    String? sentAt, // ✅ YENİ PARAMETRE
  ) async {
    // 🔍 Bağlantı kontrolü
    if (!_ensureConnection()) {
      debugPrint("❌ SignalR bağlantısı yok! Mesaj gönderilemedi.");
      debugPrint("   Connection State: ${_connection?.state}");
      return false;
    }

    try {
      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      debugPrint("📤 [FLUTTER -> SIGNALR] SendMessage BAŞLADI");
      debugPrint("   Connection State: ${_connection!.state}");
      debugPrint("   receiverId (targetId): $receiverId");
      debugPrint("   isGroupMessage: $isGroupMessage");
      debugPrint("   messageId: $messageId");
      debugPrint("   messageType: $messageType");
      debugPrint("   filesize: $filesize");
      debugPrint("   sentAt: $sentAt"); // ✅ YENİ LOG
      if (newMessage != null && newMessage.isNotEmpty) {
        final preview = newMessage.length > 50
            ? newMessage.substring(0, 50)
            : newMessage;
        debugPrint("   content: $preview...");
      }
      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

      // ✅ FIX: null-safe argümanlar için List<Object> kullan
      final arguments = <Object>[
        receiverId, // Guid targetId
        newMessage ?? "", // string newMessage
        fileUrl ?? "", // string fileUrl
        messageType ?? "0", // string messageType
        filesize ?? 0, // long? filesize
        isGroupMessage, // bool isGroupMessage
        messageId ?? "", // string? messageId
        sentAt ?? DateTime.now().toUtc().toIso8601String(), // ✅ string? sentAt
      ];

      await _connection!.invoke("SendMessage", args: arguments);

      debugPrint("✅ SignalR invoke BAŞARILI!");
      return true;
    } catch (e) {
      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      debugPrint("❌ SignalR SendMessage HATASI!");
      debugPrint("   Hata: $e");
      debugPrint("   Stack: ${StackTrace.current}");
      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      return false;
    }
  }

  Future<bool> joinMultipleGroups(List<String> groupIds) async {
    if (!_ensureConnection()) return false;
    try {
      debugPrint("📡 SignalR: Gruplara katılma isteği gönderiliyor: $groupIds");
      await _connection!.invoke("JoinMultipleGroups", args: [groupIds]);
      return true;
    } catch (e) {
      debugPrint("❌ JoinMultipleGroups Invoke Hatası: $e");
      return false;
    }
  }

  // Konferans Metodları
  Future<bool> notifyConferenceStarted(
    String roomId,
    String currentUserId,
    String targetUserId,
  ) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke(
        "NotifyConferenceStarted",
        args: [roomId, currentUserId, targetUserId],
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> notifyConferenceEnded(String userId) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke("NotifyConferenceEnded", args: [userId]);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> notifyGroupConferenceStarted(
    String roomId,
    String starterId,
    String groupId,
  ) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke(
        "NotifyGroupConferenceStarted",
        args: [roomId, starterId, groupId],
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> userInfoUpdated(String userId) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke("UserInfoUpdated", args: [userId]);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> notifyGroupUserJoined(
    String roomId,
    String userId,
    String groupId,
  ) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke(
        "NotifyGroupUserJoined",
        args: [roomId, userId, groupId],
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> notifyUserJoined(
    String roomId,
    String userId,
    String targetUserId,
  ) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke(
        "NotifyUserJoined",
        args: [roomId, userId, targetUserId],
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> notifyGroupConferenceEnded(String roomId, String groupId) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke(
        "NotifyGroupConferenceEnded",
        args: [roomId, groupId],
      );
      debugPrint(
        "🏁 SignalR: Grup konferansı sonlandırıldı bildirimi gönderildi.",
      );
      return true;
    } catch (e) {
      debugPrint("❌ notifyGroupConferenceEnded Hatası: $e");
      return false;
    }
  }

  Future<bool> notifyGroupUserLeft(
    String roomId,
    String userId,
    String groupId,
  ) async {
    if (!_ensureConnection()) return false;
    try {
      await _connection!.invoke(
        "NotifyGroupUserLeft",
        args: [roomId, userId, groupId],
      );
      debugPrint("👤 SignalR: Kullanıcı gruptan ayrıldı bildirimi gönderildi.");
      return true;
    } catch (e) {
      debugPrint("❌ notifyGroupUserLeft Hatası: $e");
      return false;
    }
  }

  Future<int> getActiveRoomForGroup(String groupId) async {
    if (!_ensureConnection()) return 0;
    try {
      final result = await _connection!.invoke(
        "GetActiveRoomForGroup",
        args: [groupId],
      );
      return result as int? ?? 0;
    } catch (e) {
      debugPrint("❌ GetActiveRoomForGroup Hatası: $e");
      return 0;
    }
  }

  Future<bool> groupInfoUpdated(String groupId) async {
    if (!_ensureConnection()) return false;
    try {
      debugPrint("📡 SignalR: GroupInfoUpdated çağrılıyor - GroupId: $groupId");
      await _connection!.invoke("GroupInfoUpdated", args: [groupId]);
      return true;
    } catch (e) {
      debugPrint("❌ GroupInfoUpdated failed: $e");
      return false;
    }
  }
}
