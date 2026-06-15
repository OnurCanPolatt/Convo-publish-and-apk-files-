import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/services/signalr/signalr_service.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../models/chat_list_item.dart';
import '../models/friend.dart';
import '../providers/chat_provider.dart';
import '../providers/conference_provider.dart';
import '../providers/notification_provider.dart';
import '../screens/chat_screen.dart';
import '../screens/group_chat_screen.dart';
import '../screens/notification_screen.dart';
import 'api_service.dart';
import 'auth_provider.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static const String _baseUrl = 'https://convoapp.app/api';

  HttpClient _createHttpClient() {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    return client;
  }

  Future<void> initialize(String userId) async {
    try {
      final FlutterLocalNotificationsPlugin localNotif =
          FlutterLocalNotificationsPlugin();
      const videoCallChannel = AndroidNotificationChannel(
        'video_call_channel_v2',
        'Video Calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await localNotif
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(videoCallChannel);

      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.max,
      );
      await localNotif
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      // ✅ Notification initialization settings
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
      );

      // ✅ Notification tıklama ve action handling
      await localNotif.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationAction(response);
        },
      );

      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await _messaging.getToken();
        debugPrint(
          "********************************ADIM 1: FCM TOKEN********************************",
        );
        debugPrint("🚀 TOKEN: $token");
        debugPrint(
          "**********************************************************************************",
        );
        if (token != null) await _registerTokenToBackend(userId, token);

        // ✅ Foreground message handler'ı başlat
        setupForegroundMessageHandler();
      }
    } catch (e) {
      debugPrint('❌ FcmService.initialize Hatası: $e');
    }
  }

  Future<void> _registerTokenToBackend(String userId, String token) async {
    try {
      final client = _createHttpClient();
      final request = await client.postUrl(
        Uri.parse('$_baseUrl/DeviceToken/register'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(
        jsonEncode({'userId': userId, 'token': token, 'platform': 'android'}),
      );
      final response = await request.close();
      client.close();
    } catch (e) {
      debugPrint('❌ Backend Kayıt Hatası: $e');
    }
  }

  void setupForegroundMessageHandler() {
    // ✅ Uygulama açıkken gelen notification'ları yakala
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("📩 Foreground Message Received: ${message.data}");

      final String type = message.data['type'] ?? '';

      // ✅ DÜZELTME: Foreground'da (uygulama içinde) video call notification GÖSTERME
      // SignalR zaten IncomingCallOverlay gösteriyor, duplicate bildirim istemiyoruz
      if (type == 'P2P_VIDEO_CALL' || type == 'GROUP_VIDEO_CALL') {
        debugPrint(
          "ℹ️ Foreground video call - SignalR overlay gösterecek, bildirim atlandı",
        );
        // ❌ showVideoCallNotification çağırma - SignalR IncomingCallOverlay gösterecek
        return;
      }

      // Diğer bildirim türleri için (chat mesajları vb.) eski mantığı kullan
      // ... (eğer başka foreground notification'larınız varsa buraya ekleyin)
    });
  }

  void setupInteractedMessages() async {
    debugPrint("🔔 FCM setupInteractedMessages başlatıldı");

    // 1. Uygulama Kapalıyken (Terminated/Killed) tıklanma
    RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
        "🚀 Killed state'den bildirim tespit edildi: ${initialMessage.data}",
      );

      // ✅ YENİ: Navigator VE Auth'un hazır olmasını bekle
      await _waitForNavigator();
      debugPrint("🔐 Auth token bekleniyor...");
      await _waitForAuth();
      debugPrint("🎯 Navigator ve Auth hazır, navigation başlatılıyor");

      _handleNavigation(initialMessage);
    }

    // 2. Uygulama Arka Plandayken (Background/Resume) tıklanma
    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      debugPrint(
        "🚀 Background state'den bildirim tespit edildi: ${message.data}",
      );

      // Resume durumunda genelde token zaten yüklü ama yine de kontrol edelim
      await _waitForNavigator();
      await _waitForAuth();

      _handleNavigation(message);
    });
  }

  // ✅ YENİ: Navigator hazır olana kadar bekleyen helper metod
  Future<void> _waitForNavigator() async {
    int attempts = 0;
    while (navigatorKey.currentState == null && attempts < 50) {
      debugPrint(
        "⏳ Navigator henüz hazır değil, bekleniyor... (${attempts + 1}/50)",
      );
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    if (navigatorKey.currentState != null) {
      debugPrint("✅ Navigator hazır!");
    } else {
      debugPrint("❌ Navigator timeout! Navigation yapılamayabilir.");
    }
  }

  Future<void> _waitForAuth() async {
    int attempts = 0;
    while (attempts < 50) {
      debugPrint("⏳ Auth token kontrol ediliyor... (${attempts + 1}/50)");

      final context = navigatorKey.currentContext;
      if (context != null) {
        try {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );

          // Token ve user yüklenmişse hazır
          if (authProvider.token != null &&
              authProvider.currentUser != null &&
              !authProvider.isLoading) {
            debugPrint("✅ Auth token hazır!");
            return;
          }
        } catch (e) {
          debugPrint("⚠️ Auth provider henüz erişilebilir değil: $e");
        }
      }

      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }

    debugPrint("❌ Auth timeout! Token yüklenemedi.");
  }

  Future<void> _handleNavigation(RemoteMessage message) async {
    debugPrint("🎯 Tıklanan Bildirim Verisi: ${message.data}");

    // ✅ YENİ: addPostFrameCallback KALDIRILDI, direkt çalıştır
    // Navigator zaten _waitForNavigator() ile hazır

    final String type = (message.data['type'] ?? "").toString();
    final String id = (message.data['id'] ?? "").toString();
    final String name = (message.data['name'] ?? "Convo").toString();

    if (id.isEmpty) {
      debugPrint("❌ Bildirimde ID yok, navigation iptal edildi");
      return;
    }

    final navState = navigatorKey.currentState;
    if (navState == null) {
      debugPrint("❌ Navigator state null, navigation iptal edildi");
      return;
    }

    // Zaten bu chat açıksa yönlendirme yapma
    bool isAlreadyOnThisChat = false;
    navState.popUntil((route) {
      if (route.settings.name == '/chat_$id') {
        isAlreadyOnThisChat = true;
      }
      return true;
    });
    if (isAlreadyOnThisChat) {
      debugPrint("⚠️ Zaten bu sohbet açık, yönlendirme atlandı.");
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint("❌ Context null, navigation iptal edildi");
      return;
    }

    final signalr = Provider.of<SignalrService>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final notifProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );

    // ✅ KRİTİK: SignalR başlatılmamışsa başlat VE her zaman sync yap
    if (!signalr.isConnected) {
      debugPrint("⚠️ SignalR başlatılmamış, şimdi başlatılıyor...");

      if (authProvider.currentUser != null && authProvider.token != null) {
        await signalr.start(
          authProvider.currentUser!.userId!,
          authProvider.token!,
          chatProvider,
          notifProvider,
        );
        debugPrint("✅ SignalR başlatıldı");

        // ✅ Gruplara otomatik katıl
        await signalr.syncGroupSubscriptions();
        debugPrint("✅ Gruplara yeniden katılındı");
      } else {
        debugPrint("❌ Token/User yok, SignalR başlatılamadı");
        return;
      }
    } else {
      // ✅ YENİ: SignalR zaten bağlıysa (resume state), grup senkronizasyonunu yeniden yap
      debugPrint(
        "⚠️ SignalR zaten bağlı (resume state), grup sync yapılıyor...",
      );
      await signalr.syncGroupSubscriptions();
      debugPrint("✅ Resume state - gruplara yeniden katılındı");
    }

    // ✅ Mesajları önceden yükle
    final ApiService apiService = ApiService();

    if (type == "P2P_CHAT") {
      debugPrint("📱 P2P Chat'e yönlendiriliyor: $id");

      // P2P mesajlarını önceden yükle
      try {
        final dbMessages = await apiService.messageApi.getMessagesFromDb(
          authProvider.currentUser!.userId!,
          id,
          authProvider.token!,
        );
        if (dbMessages.isNotEmpty) {
          chatProvider.setMessages(id, dbMessages);
          debugPrint(
            "✅ P2P mesajları önceden yüklendi: ${dbMessages.length} adet",
          );
        }
      } catch (e) {
        debugPrint("❌ P2P mesaj yükleme hatası: $e");
      }

      final friend = FriendModel(
        id: id,
        userName: name,
        firstName: name,
        lastName: "",
        imageUrl: null,
      );

      await navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          settings: RouteSettings(name: '/chat_$id'),
          builder: (_) =>
              ChatScreen(friendModel: friend, signalRService: signalr),
        ),
        (route) => route.isFirst,
      );

      debugPrint("✅ P2P Chat sayfası açıldı");
    } else if (type == "GROUP_CHAT") {
      debugPrint("📱 Grup Chat'e yönlendiriliyor: $id");

      // ✅ Gruba JOIN yap ve mesajları yükle
      try {
        // 1. SignalR Hub grubuna katıl
        await signalr.methods?.joinMultipleGroups([id]);
        debugPrint("✅ Grup SignalR'a katıldı: $id");

        // 2. Grup mesajlarını yükle
        final dbMessages = await apiService.messageApi.getGroupMessagesFromDb(
          id,
          authProvider.token!,
        );
        if (dbMessages.isNotEmpty) {
          chatProvider.setMessages(id, dbMessages);
          debugPrint(
            "✅ Grup mesajları önceden yüklendi: ${dbMessages.length} adet",
          );
        }
      } catch (e) {
        debugPrint("❌ Grup mesaj yükleme hatası: $e");
      }

      final group = GroupItem(id: id, name: name, imageUrl: "", members: []);

      await navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          settings: RouteSettings(name: '/chat_$id'),
          builder: (_) =>
              GroupChatScreen(groupModel: group, signalRService: signalr),
        ),
        (route) => route.isFirst,
      );

      debugPrint("✅ Grup Chat sayfası açıldı");
    } else if (type == "FRIEND_NOTIFICATION") {
      // ✅ YENİ: Arkadaşlık bildirimleri için notification screen'e git
      debugPrint(
        "👥 Arkadaşlık bildirimine tıklandı, notification screen'e yönlendiriliyor",
      );

      // NotificationProvider'ı refresh et
      final notifProvider = Provider.of<NotificationProvider>(
        context,
        listen: false,
      );
      await notifProvider.refreshNotifications(
        authProvider.currentUser!.userId!,
        authProvider.token!,
        apiService,
      );

      // Notification screen'e git
      await navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/notifications'),
          builder: (_) => const NotificationScreen(), // Tab 1 = Notifications
        ),
        (route) => route.isFirst,
      );

      debugPrint("✅ Notification screen açıldı");
    } else if (type == "P2P_VIDEO_CALL" || type == "GROUP_VIDEO_CALL") {
      // ✅ YENİ: Video Call Navigation (Killed durumu için)
      debugPrint("📞 Video Call bildirimine tıklandı (Killed state): $type");

      final String roomId = message.data['roomId']?.toString() ?? '';
      final String starterId = message.data['starterId']?.toString() ?? '';
      final String starterName =
          message.data['starterName']?.toString() ?? 'Bilinmeyen';
      final String? groupId = message.data['groupId']?.toString();
      final String? groupName = message.data['groupName']?.toString();
      final String chatId = message.data['chatId']?.toString() ?? '';

      if (roomId.isEmpty) {
        debugPrint("❌ Video call roomId boş, navigation iptal edildi");
        return;
      }

      final conferenceProvider = Provider.of<ConferenceProvider>(
        context,
        listen: false,
      );

      // ConferenceProvider'a incoming call bilgisini set et
      conferenceProvider.setIncomingCallFromNotification(
        roomId: roomId,
        starterId: starterId,
        groupId: groupId,
        isGroup: type == 'GROUP_VIDEO_CALL',
      );
      debugPrint("✅ ConferenceProvider'a call data set edildi");

      if (type == 'GROUP_VIDEO_CALL' && groupId != null) {
        // Grup video call
        debugPrint("📞 Grup video call'a yönlendiriliyor: $groupId");

        try {
          // ✅ KRİTİK: Gruba JOIN yap ve tamamlanmasını bekle
          await signalr.methods?.joinMultipleGroups([groupId]);
          debugPrint("✅ Grup SignalR'a katıldı: $groupId");

          // ✅ KRİTİK: Grup sync'in tamamlanması için ek bekleme
          await Future.delayed(const Duration(milliseconds: 500));
          debugPrint("✅ Grup sync tamamlandı, mesajlar yükleniyor...");

          final dbMessages = await apiService.messageApi.getGroupMessagesFromDb(
            groupId,
            authProvider.token!,
          );
          if (dbMessages.isNotEmpty) {
            chatProvider.setMessages(groupId, dbMessages);
            debugPrint(
              "✅ Grup mesajları önceden yüklendi: ${dbMessages.length} adet",
            );
          }
        } catch (e) {
          debugPrint("❌ Grup mesaj yükleme hatası: $e");
        }

        final group = GroupItem(
          id: groupId,
          name: groupName ?? 'Grup',
          imageUrl: '',
          members: [],
        );

        await navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            settings: RouteSettings(name: '/chat_$groupId'),
            builder: (_) =>
                GroupChatScreen(groupModel: group, signalRService: signalr),
          ),
          (route) => route.isFirst,
        );

        debugPrint("✅ Grup Chat sayfası açıldı (Video call için)");
      } else {
        // P2P video call
        debugPrint("📞 P2P video call'a yönlendiriliyor: $chatId");

        try {
          final dbMessages = await apiService.messageApi.getMessagesFromDb(
            authProvider.currentUser!.userId!,
            chatId,
            authProvider.token!,
          );
          if (dbMessages.isNotEmpty) {
            chatProvider.setMessages(chatId, dbMessages);
            debugPrint(
              "✅ P2P mesajları önceden yüklendi: ${dbMessages.length} adet",
            );
          }
        } catch (e) {
          debugPrint("❌ P2P mesaj yükleme hatası: $e");
        }

        final friend = FriendModel(
          id: chatId,
          userName: starterName,
          firstName: starterName,
          lastName: '',
          imageUrl: null,
        );

        await navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            settings: RouteSettings(name: '/chat_$chatId'),
            builder: (_) =>
                ChatScreen(friendModel: friend, signalRService: signalr),
          ),
          (route) => route.isFirst,
        );

        debugPrint("✅ P2P Chat sayfası açıldı (Video call için)");
      }
    } else {
      debugPrint("⚠️ Bilinmeyen bildirim tipi: $type");
    }
  }

  Future<void> showVideoCallNotification({
    required String callerId,
    required String callerName,
    required String roomId,
    required bool isGroup,
    String? groupId,
    String? groupName,
  }) async {
    final FlutterLocalNotificationsPlugin localNotif =
        FlutterLocalNotificationsPlugin();

    // ✅ BİLDİRİM DETAYLARI
    final AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'video_call_channel_v2', // Eğer butonlar gelmezse bu ismi 'video_call_channel_v2' yap
      'Video Calls',
      channelDescription: 'Incoming video call notifications',

      // 1️⃣ ANA İKON: Beyaz kare hatasını önlemek için default Flutter ikonunu kullanıyoruz
      icon: '@mipmap/launcher_icon',

      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true, // Kilit ekranında tam sayfa uyarı için
      category: AndroidNotificationCategory.call,

      // 2️⃣ BUTONLAR (ACTIONS)
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept_call',
          'Kabul Et',
          // ✅ Senin eklediğin ikon: drawable/ic_call_accept.png
          icon: const DrawableResourceAndroidBitmap('ic_call_accept'),
          contextual: true,
          showsUserInterface: true,
          cancelNotification: true, // Basınca bildirimi kapatır
        ),
      ],
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await localNotif.show(
      roomId.hashCode,
      isGroup ? (groupName ?? 'Grup Araması') : callerName,
      isGroup ? 'Grup video konferansı başladı' : 'Sizi arıyor...',
      notificationDetails,
      payload: jsonEncode({
        'type': isGroup ? 'GROUP_VIDEO_CALL' : 'P2P_VIDEO_CALL',
        'roomId': roomId,
        'starterId': callerId,
        'starterName': callerName,
        'groupId': groupId,
        'groupName': groupName,
        'chatId': isGroup ? groupId : callerId,
      }),
    );
  }

  void _handleNotificationAction(NotificationResponse response) async {
    debugPrint("🔔 Notification Action: ${response.actionId}");
    debugPrint("🔔 Payload: ${response.payload}");
    debugPrint("🔔 Notification ID: ${response.id}");

    if (response.payload == null) {
      debugPrint("⚠️ Payload null, işlem iptal");
      return;
    }

    final Map<String, dynamic> data = jsonDecode(response.payload!);
    final String type = data['type'] ?? '';

    if (type == 'P2P_VIDEO_CALL' || type == 'GROUP_VIDEO_CALL') {
      final String roomId = data['roomId'] ?? '';

      // ✅ Video call bildirimi için özel işlem
      if (type == 'P2P_VIDEO_CALL' || type == 'GROUP_VIDEO_CALL') {
        final String roomId = data['roomId'] ?? '';
        final String starterId = data['starterId'] ?? '';
        final String starterName = data['starterName'] ?? '';
        final String? groupId = data['groupId'];
        final String? groupName = data['groupName'];
        final String chatId = data['chatId'] ?? '';

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = navigatorKey.currentContext;
          if (context == null) return;

          final conferenceProvider = Provider.of<ConferenceProvider>(
            context,
            listen: false,
          );
          final signalr = Provider.of<SignalrService>(context, listen: false);

          // ✅ KABUL EDILDI
          if (response.actionId == 'accept_call') {
            debugPrint("✅ Video call kabul edildi");

            // 1. ConferenceProvider'a incoming call data'yı set et
            conferenceProvider.setIncomingCallFromNotification(
              roomId: roomId,
              starterId: starterId,
              groupId: groupId,
              isGroup: type == 'GROUP_VIDEO_CALL',
            );

            // 2. İlgili chat sayfasına git
            if (type == 'GROUP_VIDEO_CALL' && groupId != null) {
              final group = GroupItem(
                id: groupId,
                name: groupName ?? 'Grup',
                imageUrl: '',
                members: [],
              );
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  settings: RouteSettings(name: '/chat_$groupId'),
                  builder: (_) => GroupChatScreen(
                    groupModel: group,
                    signalRService: signalr,
                  ),
                ),
                (route) => route.isFirst,
              );
            } else {
              final friend = FriendModel(
                id: chatId,
                userName: starterName,
                firstName: starterName,
                lastName: '',
                imageUrl: null,
              );
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  settings: RouteSettings(name: '/chat_$chatId'),
                  builder: (_) =>
                      ChatScreen(friendModel: friend, signalRService: signalr),
                ),
                (route) => route.isFirst,
              );
            }
          }
          // 📱 Bildirime tıklama (action değil)
          else if (response.actionId == null) {
            debugPrint("📱 Video call bildirimine tıklandı (direkt katılım)");

            // Direkt tıklamada da kabul et gibi davran
            conferenceProvider.setIncomingCallFromNotification(
              roomId: roomId,
              starterId: starterId,
              groupId: groupId,
              isGroup: type == 'GROUP_VIDEO_CALL',
            );

            if (type == 'GROUP_VIDEO_CALL' && groupId != null) {
              final group = GroupItem(
                id: groupId,
                name: groupName ?? 'Grup',
                imageUrl: '',
                members: [],
              );
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  settings: RouteSettings(name: '/chat_$groupId'),
                  builder: (_) => GroupChatScreen(
                    groupModel: group,
                    signalRService: signalr,
                  ),
                ),
                (route) => route.isFirst,
              );
            } else {
              final friend = FriendModel(
                id: chatId,
                userName: starterName,
                firstName: starterName,
                lastName: '',
                imageUrl: null,
              );
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  settings: RouteSettings(name: '/chat_$chatId'),
                  builder: (_) =>
                      ChatScreen(friendModel: friend, signalRService: signalr),
                ),
                (route) => route.isFirst,
              );
            }
          }
        });
      } else {
        // Normal chat mesajı için mevcut navigation
        _handleNavigation(RemoteMessage(data: data));
      }
    }
  }
}
