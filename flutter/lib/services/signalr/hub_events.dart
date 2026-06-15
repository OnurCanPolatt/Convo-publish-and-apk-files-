// lib/services/signalr/hub_events.dart
import 'package:my_first_flutterapp/services/signalr/signalr_service.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:flutter/material.dart';
import '../../models/chat_message.dart';

class HubEvents {
  final HubConnection? _connection;
  final SignalrService _signalrService;

  final Function(Map<String, dynamic>) onMessageReceived;
  final Function(List<String> onlineIds) onOnlineListLoaded;
  final Function(String odataId) onUserOnline;
  final Function(String odataId) onUserOffline;
  final Function(String? groupId) onGroupCreated;
  // ✅ GÜNCELLEME: userId parametresi eklendi
  final Function(String? odataId) onInfoUpdated;
  final Function(List<dynamic> requests, int count)? onRequestsLoaded;
  final Function(List<dynamic> notifications, int count)? onNotificationsLoaded;
  final Function()? onDiscoveryListChanged;
  final Function(String? affectedUserId, int? newStatus)? onFriendListChanged;
  final Function(String senderId)? onFriendRequestRemoved;
  final Function(String odataId, String userName)? onFriendRemoved;
  final Function(String odataId, String userName)? onFriendRequestAccepted;
  final Function(String groupId)? onGroupDeleted;
  final Function(String groupId, String userId)? onUserLeftGroup;

  // Conference callbacks
  final Function(String roomId, String starterId, String targetId)?
  onConferenceStarted;
  final Function(String roomId, String starterId, String groupId)?
  onGroupConferenceStarted;
  final Function(String roomId, String oderId)? onUserJoined;
  final Function(String oderId)? onConferenceEnded;
  final Function(String roomId, String userId)? onUserLeft; // 👈 Yeni
  HubEvents(
    this._connection,
    this._signalrService, {
    required this.onMessageReceived,
    required this.onOnlineListLoaded,
    required this.onUserOnline,
    required this.onUserOffline,
    required this.onInfoUpdated,
    required this.onGroupCreated,
    this.onRequestsLoaded,
    this.onNotificationsLoaded,
    this.onDiscoveryListChanged,
    this.onFriendListChanged,
    this.onFriendRequestRemoved,
    this.onFriendRemoved,
    this.onFriendRequestAccepted,
    this.onConferenceStarted,
    this.onGroupConferenceStarted,
    this.onUserJoined,
    this.onConferenceEnded,
    this.onUserLeft,
    this.onGroupDeleted,
    this.onUserLeftGroup,
  });

  void setup() {
    if (_connection == null) return;

    _connection.on("ReceiveMessage", (List<dynamic>? args) {
      try {
        // 🚩 1. Veri varlığı kontrolü
        if (args == null || args.length < 5) {
          debugPrint("❌ ReceiveMessage: Eksik argüman!");
          return;
        }

        // 🚩 2. Her bir argümanı tip güvenli şekilde çıkar
        final String senderId = args[0]?.toString() ?? "";
        final String content = args[1]?.toString() ?? "";
        final String? fileUrl = (args[2] == null || args[2].toString().isEmpty)
            ? null
            : args[2].toString();
        // ✅ P2P'DEKİ GİBİ: MessageType'ı int olarak parse et (backend int gönderiyor)
        final dynamic rawMessageType = args[3];
        final int messageType = rawMessageType is int
            ? rawMessageType
            : (int.tryParse(rawMessageType?.toString() ?? "0") ?? 0);

        // ✅ P2P'DEKİ GİBİ: Filesize için güvenli parse (long/int/double/string)
        int? size;
        if (args[4] != null) {
          var rawSize = args[4];
          if (rawSize is int) {
            size = rawSize;
          } else if (rawSize is double) {
            size = rawSize.toInt();
          } else {
            // String veya başka tip ise tryParse kullan
            final parsed = int.tryParse(rawSize.toString());
            if (parsed != null) {
              size = parsed;
            } else {
              debugPrint("⚠️ FileSize parse edilemedi: $rawSize");
              size = 0; // Fallback
            }
          }
        }

        final String? targetId =
            (args.length > 5 && args[5] != null && args[5].toString() != "null")
            ? args[5].toString()
            : null;

        final String messageId = (args.length > 6 && args[6] != null)
            ? args[6].toString()
            : "temp_${DateTime.now().millisecondsSinceEpoch}";

        final String? receiverId =
            (args.length > 7 && args[7] != null && args[7].toString() != "null")
            ? args[7].toString()
            : null;

        // ✅ DÜZELTME: Backend her zaman sentAt gönderiyor, fallback'e gerek yok
        final String sentAt = (args.length > 8 && args[8] != null)
            ? args[8].toString()
            : DateTime.now().toUtc().toIso8601String(); // Son çare fallback

        final bool isGroup = targetId != null;

        // ✅ P2P'DEKİ GİBİ: Callback'i güvenli çağır
        onMessageReceived({
          "id": messageId,
          "senderId": senderId,
          "content": content,
          "fileUrl": fileUrl,
          "type": messageType, // ✅ int olarak gönder (string değil)
          "fileSize": size,
          "targetId": targetId,
          "receiverId": receiverId,
          "isGroupMessage": isGroup,
          "sentAt": sentAt,
        });
      } catch (e, stack) {
        debugPrint("❌ HUB_EVENTS KRİTİK HATA: $e");
        debugPrint("Stack: $stack");
        // Hata olsa bile Stream'i bozmamak için burada kalıyoruz
      }
    });

    // 2. Online Durumları
    _connection.on("OnlineUsersList", (args) {
      if (args != null && args.isNotEmpty) {
        final List<String> ids = (args[0] as List)
            .map((e) => e.toString().toLowerCase())
            .toList();
        onOnlineListLoaded(ids);
      }
    });
    _connection.on("UserOnline", (args) => onUserOnline(args![0].toString()));
    _connection.on("UserOffline", (args) => onUserOffline(args![0].toString()));

    // 3. Arkadaşlık İstekleri
    _connection.on("RequestsLoaded", (args) {
      if (args != null && onRequestsLoaded != null) {
        final List<dynamic> rawList = args[0] as List;
        final formattedList = rawList.map((item) {
          final senderObj = item['sender'];
          return {
            ...item,
            'senderName': senderObj != null
                ? senderObj['userName']
                : (item['senderName'] ?? "Bilinmeyen"),
            'message':
                item['message'] ?? "Size bir arkadaşlık isteği gönderdi.",
          };
        }).toList();
        onRequestsLoaded!(formattedList, (args[1] ?? 0) as int);
      }
    });

    _connection.on(
      "RequestRemoved",
      (args) => onFriendRequestRemoved?.call(args![0].toString()),
    );
    _connection.on(
      "FriendRequestAcceptedByOther",
      (args) => onFriendRequestAccepted?.call(
        args![0].toString(),
        args![1].toString(),
      ),
    );
    _connection.on(
      "FriendRemovedByOther",
      (args) => onFriendRemoved?.call(args![0].toString(), args![1].toString()),
    );
    _connection.on(
      "UnreadNotificationsLoaded",
      (args) => onNotificationsLoaded?.call(args![0] as List, args![1] as int),
    );

    // 4. Liste Yenileme ve Bilgi Güncellemeleri
    _connection.on(
      "DiscoveryListChanged",
      (_) => onDiscoveryListChanged?.call(),
    );
    _connection.on("FriendListChanged", (List<dynamic>? args) {
      debugPrint("🔍 RAW FriendListChanged args: $args");

      String? affectedUserId;
      int? newStatus;

      if (args != null && args.isNotEmpty) {
        affectedUserId = args[0]?.toString();
        if (args.length > 1) {
          // Güvenli int cast
          var statusValue = args[1];
          if (statusValue is int) {
            newStatus = statusValue;
          } else if (statusValue is String) {
            newStatus = int.tryParse(statusValue);
          }
        }
      }

      debugPrint(
        "📡 SignalR: FriendListChanged -> User: $affectedUserId, Status: $newStatus",
      );

      // ✅ BURASI KRİTİK: Artık callback'i 2 parametre ile çağırıyoruz
      onFriendListChanged?.call(affectedUserId, newStatus);
    });
    // ✅ GÜNCELLEME: userId'yi parse et
    _connection.on("ReceiveUserInfoUpdated", (List<dynamic>? args) {
      debugPrint("📡 SignalR: ReceiveUserInfoUpdated alındı - args: $args");

      String? updatedUserId; // userId yerine tutarlı bir isim
      try {
        if (args != null && args.isNotEmpty) {
          final data = args[0];
          if (data is Map) {
            updatedUserId = data['userId']?.toString();
          } else if (data is String) {
            updatedUserId = data;
          }
        }
      } catch (e) {
        debugPrint("⚠️ ReceiveUserInfoUpdated parse hatası: $e");
      }

      debugPrint(
        "📡 SignalR: Kullanıcı bilgisi güncellendi - userId: $updatedUserId",
      );
      onInfoUpdated(updatedUserId);
    });

    _connection.on("ReceiveGroupCreated", (List<dynamic>? args) {
      try {
        if (args == null || args.isEmpty) {
          debugPrint("⚠️ SignalR: ReceiveGroupCreated - args boş!");
          return;
        }

        final String groupId = args[0].toString();
        debugPrint("🆕 SignalR: YENİ GRUP OLUŞTURULDU! GroupId: $groupId");
        onGroupCreated(groupId);
      } catch (e) {
        debugPrint("❌ SignalR: ReceiveGroupCreated hatası: $e");
      }
    });

    _connection.on("ReceiveGroupUpdated", (List<dynamic>? args) {
      try {
        if (args == null || args.isEmpty) return;

        final String groupId = args[0].toString();
        debugPrint(
          "📡 SignalR: Grup güncelleme sinyali alındı! GroupId: $groupId",
        );

        // ✅ DÜZELTME: Sayfaların tanıması için tipi netleştirelim
        _signalrService.emitFriendEvent({
          'type': 'GroupInfoUpdated', // <-- Bu ismi sayfada da karşılayacağız
          'groupId': groupId,
        });
      } catch (e) {
        debugPrint("❌ SignalR: ReceiveGroupUpdated hatası: $e");
      }
    });

    // ✅ GÜNCELLEME: MyInfo için de userId parse et
    _connection.on("MyInfo", (List<dynamic>? args) {
      debugPrint("📡 SignalR: MyInfo alındı - args: $args");

      String? myId;
      try {
        if (args != null && args.isNotEmpty) {
          final data = args[0];
          if (data is Map) {
            myId = data['userId']?.toString();
          } else if (data is String) {
            myId = data;
          }
        }
      } catch (e) {
        debugPrint("⚠️ MyInfo parse hatası: $e");
      }

      onInfoUpdated(myId);
    });

    // P2P Araması (Web'den Mobile)
    _connection.on("ReceiveConferenceNotification", (args) {
      debugPrint("📞 P2P ARAMA SİNYALİ GELDİ: $args");
      _handleIncomingCall(args, isGroup: false);
    });

    // Grup Araması (Web'den Mobile)
    _connection.on("ReceiveGroupConferenceNotification", (args) {
      debugPrint("👥 GRUP ARAMA SİNYALİ GELDİ: $args");
      _handleIncomingCall(args, isGroup: true);
    });

    _connection.on("ReceiveUserJoined", (args) {
      if (args != null && args.length >= 2) {
        debugPrint(
          "👤 SignalR: Kullanıcı konferansa katıldı - Room: ${args[0]}, User: ${args[1]}",
        );
        onUserJoined?.call(args[0].toString(), args[1].toString());
      }
    });

    _connection.on("ReceiveP2pEndNotification", (args) {
      debugPrint("📴 SignalR: P2P Konferans sonlandırıldı");
      onConferenceEnded?.call("p2p");
    });

    // ✅ Grup için ayrı event
    _connection.on("ReceiveConferenceEnded", (args) {
      if (args != null && args.isNotEmpty) {
        debugPrint(
          "📴 SignalR: Grup konferansı sonlandırıldı - GroupId: ${args[0]}",
        );
        onConferenceEnded?.call(args[0].toString());
      }
    });

    _connection.on("ReceiveUserLeft", (args) {
      if (args != null && args.length >= 2) {
        debugPrint(
          "🚪 SignalR: Kullanıcı ayrıldı - Room: ${args[0]}, User: ${args[1]}",
        );
        // onUserLeft diye yeni bir callback tanımlayacağız (aşağıda)
        onUserLeft?.call(args[0].toString(), args[1].toString());
      }
    });
    // ✅ YENİ: Grup Silme Eventi (Tüm üyeler için)
    _connection.on("ReceiveGroupDeleted", (args) {
      if (args != null && args.isNotEmpty) {
        final String groupId = args[0].toString();
        debugPrint("🗑️ SignalR: Grup silindi - GroupId: $groupId");
        onGroupDeleted?.call(groupId); // ✅ Callback çağır
      }
    });

    _connection.on("ReceiveUserLeftGroup", (args) {
      if (args != null && args.length >= 2) {
        final String groupId = args[0].toString();
        final String userId = args[1].toString();
        debugPrint(
          "🚪 SignalR: Kullanıcı gruptan ayrıldı - GroupId: $groupId, UserId: $userId",
        );
        onUserLeftGroup?.call(groupId, userId); // ✅ Callback çağır
      }
    });
  }

  void _handleIncomingCall(List<dynamic>? args, {required bool isGroup}) {
    if (args == null || args.isEmpty) {
      debugPrint("⚠️ SignalR: Sinyal içeriği boş.");
      return;
    }

    final String roomId = args[0].toString();
    final String starterId = args[1].toString();
    final String? extraId = (args.length >= 3) ? args[2].toString() : null;

    _signalrService.emitConferenceEvent({
      'type': isGroup ? 'group_started' : 'p2p_started',
      'roomId': roomId,
      'starterId': starterId,
      'groupId': isGroup ? extraId : null,
      'targetId': !isGroup ? extraId : null,
      'isGroup': isGroup,
    });
  }

  void clear() {
    if (_connection == null) return;

    _connection.off("ReceiveMessage");
    _connection.off("OnlineUsersList");
    _connection.off("RequestsLoaded");
    _connection.off("RequestRemoved");
    _connection.off("UnreadNotificationsLoaded");
    _connection.off("UserOnline");
    _connection.off("UserOffline");
    _connection.off("DiscoveryListChanged");
    _connection.off("FriendListChanged");
    _connection.off("MyInfo");
    _connection.off("ReceiveUserInfoUpdated");
    _connection.off("ReceiveGroupUpdated");
    _connection.off("ReceiveGroupCreated");

    _connection.off("ReceiveConferenceNotification");
    _connection.off("ReceiveGroupConferenceNotification");
    _connection.off("ReceiveUserJoined");
    _connection.off("ReceiveP2pEndNotification");
    _connection.off("ReceiveConferenceEnded");
    _connection.off("ReceiveGroupDeleted");
    _connection.off("ReceiveUserLeftGroup");

    debugPrint("🧹 SignalR: Tüm event dinleyicileri temizlendi.");
  }
}
