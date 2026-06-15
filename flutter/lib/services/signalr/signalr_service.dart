import 'package:flutter/material.dart';
import 'package:signalr_netcore/signalr_client.dart';
import '../../models/chat_list_item.dart';
import 'hub_methods.dart';
import 'hub_events.dart';
import '../../providers/chat_provider.dart';
import '../../providers/notification_provider.dart';
import 'dart:async';
import '../../services/api_service.dart';

class SignalrService extends ChangeNotifier {
  HubConnection? _hubConnection;
  HubMethods? methods;
  HubEvents? events;

  VoidCallback? onDiscoveryRefreshNeeded;
  VoidCallback? onFriendRefreshNeeded;

  static const String _baseUrl = 'https://convoapp.app';
  static const String _hubUrl = '$_baseUrl/chatHub';

  bool _isConnected = false;
  Set<String> _onlineUserIds = {};
  String? _currentUserId;
  String? _currentToken; // ✅ Token saklamak için değişken

  bool get isConnected => _isConnected;
  Set<String> get onlineUserIds => _onlineUserIds;

  ChatProvider? _chatProvider;
  NotificationProvider? _notificationProvider;
  final ApiService _apiService = ApiService();

  final _friendEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendEventStream =>
      _friendEventController.stream;
  void emitFriendEvent(Map<String, dynamic> data) {
    if (!_friendEventController.isClosed) {
      _friendEventController.add(data);
    }
  }

  final _conferenceEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get conferenceEventStream =>
      _conferenceEventController.stream;
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  final _appResumedController = StreamController<void>.broadcast();
  Stream<void> get appResumedStream => _appResumedController.stream;

  void notifyAppResumed() {
    if (!_appResumedController.isClosed) {
      _appResumedController.add(null);
    }
  }

  void emitConferenceEvent(Map<String, dynamic> data) {
    _conferenceEventController.add(data);
  }

  Future<void> start(
    String userId,
    String token,
    ChatProvider chatProvider,
    NotificationProvider notificationProvider,
  ) async {
    if (_isConnected) return;
    _currentUserId = userId;
    _chatProvider = chatProvider;
    _notificationProvider = notificationProvider;
    _currentToken = token; // ✅ Token atandı

    _hubConnection = HubConnectionBuilder()
        .withUrl(
          _hubUrl,
          options: HttpConnectionOptions(
            accessTokenFactory: () async => token,
            transport: HttpTransportType.WebSockets,
            skipNegotiation: true,
          ),
        )
        .withAutomaticReconnect(retryDelays: [0, 2000, 5000, 10000, 20000])
        .build();

    _hubConnection!.onreconnecting(({error}) {
      debugPrint("🔄 SignalR: Bağlantı koptu, yeniden deneniyor...");
      _isConnected = false;
      notifyListeners();
    });

    _hubConnection!.onreconnected(({connectionId}) async {
      _isConnected = true;
      _connectionStateController.add(true); // ✅ Bağlantı geldi haberi uçur
      if (_currentUserId != null) {
        await methods?.registerUser(_currentUserId!);
        await _joinUserGroups(); // ✅ Otomatik katıl
      }
      notifyListeners();
    });

    _hubConnection!.onclose(({error}) {
      _isConnected = false;
      notifyListeners();
    });

    methods = HubMethods(_hubConnection);

    events = HubEvents(
      _hubConnection,
      this,
      onUserOnline: (uid) {
        _onlineUserIds.add(uid.toLowerCase());
        notifyListeners();
      },
      onUserOffline: (uid) {
        _onlineUserIds.remove(uid.toLowerCase());
        notifyListeners();
      },
      onOnlineListLoaded: (ids) {
        _onlineUserIds = Set.from(ids.map((e) => e.toString().toLowerCase()));
        notifyListeners();
      },

      onMessageReceived: (data) async {
        try {
          final bool isGroup = data['isGroupMessage'] ?? false;
          final String senderId = data['senderId'].toString();
          final String myId = _currentUserId ?? "";

          // ✅ P2P'DEKİ GİBİ: Kendi mesajımızı grup içinde filtrele
          // Duplicate mesaj eklenmesini önle
          if (isGroup && senderId.toLowerCase() == myId.toLowerCase()) {
            debugPrint(
              "🚫 SignalR: Kendi grup mesajımız filtrelendi (Duplicate önlendi) - MessageId: ${data['id']}",
            );
            return;
          }

          final String chatWithId = isGroup
              ? data['targetId'].toString()
              : senderId;
          final bool isIncoming = senderId.toLowerCase() != myId.toLowerCase();

          // ✅ P2P'DEKİ GİBİ: Gelen mesaj logla
          debugPrint(
            "📨 SignalR Mesaj Alındı: ${isGroup ? 'GRUP' : 'P2P'} | From: $senderId | ChatId: $chatWithId | MessageId: ${data['id']}",
          );

          // 🚩 Unhide işlemini bekleme (async çalışsın), UI'ı bloklama
          if (isIncoming && _currentToken != null) {
            // ✅ DÜZELTME: Hem P2P hem Grup için unhide
            final unhideFuture = isGroup
                ? _apiService.messageApi.unhideGroupChat(
                    chatWithId,
                    _currentToken!,
                  )
                : _apiService.messageApi.unhidePrivateChat(
                    chatWithId,
                    _currentToken!,
                  );

            unhideFuture
                .then((wasUnhidden) {
                  // ✅ FIX: Backend zaten unhide yapmış olabilir, yine de listeyi refresh et
                  debugPrint(
                    "🔄 Unhide sonucu: $wasUnhidden, event emit ediliyor...",
                  );
                  emitFriendEvent({
                    'type': 'FriendListChanged',
                    'userId': chatWithId,
                  });
                })
                .catchError((e) => debugPrint("Unhide Hatası: $e"));
          }
          // 🚩 Mesajı Provider'a gönder
          _chatProvider?.addMessage(chatWithId, data, isIncoming);
        } catch (e) {
          debugPrint("❌ SignalrService onMessageReceived Hatası: $e");
        }
      },

      onGroupCreated: (String? groupId) async {
        if (groupId != null && groupId.isNotEmpty) {
          debugPrint(
            "🆕 Yeni grup algılandı, otomatik join yapılıyor: $groupId",
          );

          // 1. Hub grubuna katıl (Mesajları duymak için)
          await methods?.joinMultipleGroups([groupId]);

          // 2. UI'ı tetikle (Listeye eklenmesi için)
          // _friendEventController.add yerine emitFriendEvent kullan
          emitFriendEvent({'type': 'GroupCreated', 'groupId': groupId});

          notifyListeners();
        }
      },
      onInfoUpdated: (String? uid) {
        _friendEventController.add({'type': 'InfoUpdated', 'userId': uid});
        notifyListeners();
      },
      onRequestsLoaded: (List<dynamic>? requests, int? count) {
        if (requests != null && requests.isNotEmpty) {
          // 🚀 Provider'a kendi ID'mizi de gönderiyoruz (Filtreleme için gerekebilir veya setRequests içinde halledilir)
          _notificationProvider?.setRequests(requests, count ?? 0);
        } else {
          _notificationProvider?.refreshNotifications(
            userId, // start metodundaki userId parametresi
            token,
            _apiService,
          );
        }
      },
      onNotificationsLoaded: (notifications, count) async {
        // 🚀 KRİTİK: addSingleNotification metoduna artık myId gönderiyoruz
        if (notifications.isNotEmpty && _currentToken != null) {
          await _notificationProvider?.addSingleNotification(
            notifications[0],
            _currentUserId ?? "", // Kendi ID'niz
            _apiService, // API servisi
            _currentToken!, // Token
          );
        }
      },

      onFriendListChanged: (String? affectedUserId, int? newStatus) {
        // ✅ Parametreleri ekle
        emitFriendEvent({
          'type': 'FriendListChanged',
          'userId': affectedUserId,
          'newStatus': newStatus,
        });
        onFriendRefreshNeeded?.call();
        // User ID ve Token start metodundan gelmeli
        if (_currentUserId != null && _currentToken != null) {
          _notificationProvider?.refreshNotifications(
            _currentUserId!,
            _currentToken!,
            _apiService,
          );
        }
      },
      onDiscoveryListChanged: () {
        onDiscoveryRefreshNeeded?.call();
      },
      onConferenceStarted: (roomId, starterId, targetId) {
        _conferenceEventController.add({
          'type': 'p2p_started',
          'roomId': roomId,
          'starterId': starterId,
          'targetId': targetId,
        });
      },
      onGroupConferenceStarted: (roomId, starterId, groupId) {
        _conferenceEventController.add({
          'type': 'group_started',
          'roomId': roomId,
          'starterId': starterId,
          'groupId': groupId,
        });
      },
      onUserJoined: (roomId, userId) {
        _conferenceEventController.add({
          'type': 'user_joined',
          'roomId': roomId,
          'userId': userId,
        });
      },
      onConferenceEnded: (roomId) {
        _conferenceEventController.add({'type': 'ended', 'roomId': roomId});
      },
      onUserLeft: (roomId, userId) {
        _conferenceEventController.add({
          'type': 'user_left', // 👈 Bu tipte bir event fırlatıyoruz
          'roomId': roomId,
          'userId': userId,
        });
      },
      // ✅ YENİ: Grup silme callback'i
      onGroupDeleted: (groupId) {
        debugPrint("🗑️ SignalR Service: Grup silindi - $groupId");
        emitFriendEvent({'type': 'GroupDeleted', 'groupId': groupId});
      },
      // ✅ YENİ: Gruptan ayrılma callback'i
      onUserLeftGroup: (groupId, userId) {
        debugPrint(
          "🚪 SignalR Service: Kullanıcı gruptan ayrıldı - Group: $groupId, User: $userId",
        );
        emitFriendEvent({
          'type': 'UserLeftGroup',
          'groupId': groupId,
          'userId': userId,
        });
      },
    );

    events?.setup();

    try {
      await _hubConnection!.start();
      _isConnected = true;
      await methods?.registerUser(userId);

      // ✅ KRİTİK: Kullanıcının gruplarına katıl
      await _joinUserGroups();

      notifyListeners();
    } catch (e) {
      debugPrint("💥 SignalR Start Error: $e");
    }
  }

  Future<void> _joinUserGroups() async {
    if (!_isConnected || methods == null) return;

    try {
      debugPrint("🔄 Rejoin: Gruplara hızlı abonelik başlatılıyor...");

      // 🚀 HIZLI YOL: API'yi bekleme, Provider'daki mevcut grupları kullan
      // Sadece Provider boşsa veya hata varsa API'ye git.
      List<String> groupIds = [];

      if (_chatProvider != null &&
          _chatProvider!.chatCache.keys.any((key) => key.length > 30)) {
        // UUID uzunluğundaki key'ler grup/chat ID'leridir
        groupIds = _chatProvider!.chatCache.keys.toList();
        debugPrint("⚡ Cache'den ${groupIds.length} grup ID'si alındı.");
      }

      // Eğer cache boşsa (ilk açılış gibi), API'ye git
      if (groupIds.isEmpty && _currentUserId != null && _currentToken != null) {
        final groupsResponse = await _apiService.beginApi.getMyGroups(
          _currentUserId!,
          _currentToken!,
        );
        groupIds = groupsResponse.map((g) => g.id.toString()).toList();
      }

      if (groupIds.isNotEmpty) {
        // Hub'a toplu katılma isteği gönder
        final success = await methods!.joinMultipleGroups(groupIds);
        if (success) {
          debugPrint("✅ Rejoin: Tüm gruplara saniyeler içinde abone olundu.");
        }
      }
    } catch (e) {
      debugPrint("❌ _joinUserGroups Hatası: $e");
    }
  }

  // ✅ PUBLIC METOD: Grupları yükledikten sonra dışarıdan çağrılacak
  Future<void> joinAllMyGroups(List<String> groupIds) async {
    if (!_isConnected || methods == null) {
      debugPrint("⚠️ SignalR bağlı değil, gruplara katılınamıyor");
      return;
    }

    if (groupIds.isEmpty) {
      debugPrint("ℹ️ Katılacak grup yok");
      return;
    }

    try {
      debugPrint("📡 ${groupIds.length} gruba katılma isteği gönderiliyor...");

      final success = await methods!.joinMultipleGroups(groupIds);

      if (success) {
        debugPrint("✅ ${groupIds.length} gruba başarıyla katıldı");
      } else {
        debugPrint("⚠️ Gruplara katılma başarısız oldu");
      }
    } catch (e) {
      debugPrint("❌ joinAllMyGroups hatası: $e");
    }
  }

  Future<void> stop() async {
    events?.clear();
    await _hubConnection?.stop();
    _isConnected = false;
    notifyListeners();
  }

  void setInitialOnlineUsers(List<String> ids) {
    _onlineUserIds = Set<String>.from(ids.map((id) => id.toLowerCase()));
    notifyListeners();
  }

  Future<void> syncGroupSubscriptions() async {
    if (!_isConnected || _currentUserId == null) return;

    // API'den güncel grupları al ve hepsine join at
    final groups = await _apiService.beginApi.getMyGroups(
      _currentUserId!,
      _currentToken!,
    );
    final ids = groups.map((g) => g.id).toList();
    await methods?.joinMultipleGroups(ids);
  }
}
