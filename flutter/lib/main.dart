import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/providers/conference_provider.dart';
import 'package:my_first_flutterapp/providers/notification_provider.dart';
import 'package:my_first_flutterapp/screens/chat_screen.dart';
import 'package:my_first_flutterapp/screens/group_chat_screen.dart';
import 'package:my_first_flutterapp/screens/messages_screen.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/services/fcm_service.dart';
import 'package:provider/provider.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';
import 'package:my_first_flutterapp/services/signalr/signalr_service.dart';
import 'package:my_first_flutterapp/screens/login_page.dart';
import 'dart:io';
import 'package:my_first_flutterapp/providers/chat_provider.dart';
import 'package:my_first_flutterapp/providers/discovery_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:my_first_flutterapp/widgets/incoming_call_overlay.dart';
import 'package:my_first_flutterapp/screens/video_call_screen.dart';

import 'models/chat_list_item.dart';
import 'models/friend.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");

  final String type = message.data['type'] ?? '';

  if (type == 'P2P_VIDEO_CALL' || type == 'GROUP_VIDEO_CALL') {
    final FlutterLocalNotificationsPlugin localNotif =
        FlutterLocalNotificationsPlugin();

    // ✅ DÜZELTME 1: Channel'ı önce oluşturmalıyız
    const videoCallChannel = AndroidNotificationChannel(
      'video_call_channel_v2',
      'Video Calls',
      description: 'Incoming video call notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await localNotif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(videoCallChannel);

    // ✅ DÜZELTME 2: Initialize ayarlarını da yapmalıyız
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await localNotif.initialize(initSettings);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'video_call_channel_v2',
          'Video Calls',
          channelDescription: 'Incoming video call notifications',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          // ✅ DÜZELTME: Small icon için app_logo kullan
          icon: 'app_logo', // Drawable'daki app_logo.png'yi kullan
          largeIcon: DrawableResourceAndroidBitmap('app_logo'), // Büyük ikon
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'accept_call',
              'Kabul Et',
              showsUserInterface: true,
            ),
          ],
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    final String roomId = message.data['roomId'] ?? '';
    final String callerId = message.data['starterId'] ?? '';
    final String callerName =
        message.data['starterName'] ?? message.data['title'] ?? 'Bilinmeyen';
    final String? groupId = message.data['groupId'];
    final String? groupName = message.data['groupName'];
    final bool isGroup = type == 'GROUP_VIDEO_CALL';

    await localNotif.show(
      roomId.hashCode,
      isGroup ? (groupName ?? 'Grup Araması') : callerName,
      isGroup ? 'Grup video konferansı başladı' : 'Sizi arıyor...',
      notificationDetails,
      payload: jsonEncode({
        'type': type,
        'roomId': roomId,
        'starterId': callerId,
        'starterName': callerName,
        'groupId': groupId,
        'groupName': groupName,
        'chatId': isGroup ? groupId : callerId,
      }),
    );

    debugPrint("✅ Video call notification displayed in background");
  }
}

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ YENİ: Local notification'ı early initialize et (video call için)
  await _initializeLocalNotifications();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider()..initializeAuth(),
        ),
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<SignalrService>(create: (_) => SignalrService()),
        ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider<DiscoveryProvider>(
          create: (context) => DiscoveryProvider(context.read<ApiService>()),
        ),
        ChangeNotifierProvider<ConferenceProvider>(
          lazy: false,
          create: (context) =>
              ConferenceProvider(context.read<SignalrService>()),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> _initializeLocalNotifications() async {
  final FlutterLocalNotificationsPlugin localNotif =
      FlutterLocalNotificationsPlugin();

  // Channel'ları oluştur
  const videoCallChannel = AndroidNotificationChannel(
    'video_call_channel_v2',
    'Video Calls',
    description: 'Incoming video call notifications',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  await localNotif
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(videoCallChannel);

  // Initialize settings
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/launcher_icon');

  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
  );

  // ✅ KRİTİK: Notification action handler'ı register et
  await localNotif.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint(
        "🔔 Local notification tıklandı (KILLED STATE): ${response.payload}",
      );
      _handleLocalNotificationClick(response);
    },
  );

  // ✅ KRİTİK: Uygulama killed state'den açıldıysa notification detaylarını kontrol et
  final NotificationAppLaunchDetails? launchDetails = await localNotif
      .getNotificationAppLaunchDetails();

  if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
    debugPrint("🚀 Uygulama notification'dan açıldı (KILLED STATE)");

    if (launchDetails.notificationResponse != null) {
      final response = launchDetails.notificationResponse!;
      debugPrint("📦 Notification payload: ${response.payload}");

      // Payload varsa ve navigation gerekiyorsa işle
      if (response.payload != null && response.payload!.isNotEmpty) {
        // Navigation'ı scheduler'a ekle (widget tree hazır olunca çalışır)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleLocalNotificationClick(response);
        });
      }
    }
  }
}

// ✅ YENİ: Local notification click handler
void _handleLocalNotificationClick(NotificationResponse response) {
  if (response.payload == null || response.payload!.isEmpty) {
    debugPrint("⚠️ Notification payload boş");
    return;
  }

  try {
    final Map<String, dynamic> data = jsonDecode(response.payload!);
    final String type = data['type'] ?? '';

    debugPrint("🎯 Local notification işleniyor - Type: $type");

    // Video call bildirimi mi kontrol et
    if (type == 'P2P_VIDEO_CALL' || type == 'GROUP_VIDEO_CALL') {
      final String roomId = data['roomId'] ?? '';
      final String starterId = data['starterId'] ?? '';
      final String starterName = data['starterName'] ?? '';
      final String? groupId = data['groupId'];
      final String? groupName = data['groupName'];
      final String chatId = data['chatId'] ?? '';

      debugPrint("📞 Video call navigation başlatılıyor: $type");

      // Navigator ve Auth hazır olana kadar bekle
      _waitForNavigationReady().then((_) {
        _navigateToVideoCall(
          type: type,
          roomId: roomId,
          starterId: starterId,
          starterName: starterName,
          groupId: groupId,
          groupName: groupName,
          chatId: chatId,
          actionId: response.actionId,
        );
      });
    }
  } catch (e) {
    debugPrint("❌ Notification payload parse hatası: $e");
  }
}

// ✅ YENİ: Navigator ve Auth hazır olana kadar bekle
Future<void> _waitForNavigationReady() async {
  // Navigator'ı bekle
  int attempts = 0;
  while (navigatorKey.currentState == null && attempts < 50) {
    debugPrint("⏳ Navigator bekleniyor... (${attempts + 1}/50)");
    await Future.delayed(const Duration(milliseconds: 100));
    attempts++;
  }

  if (navigatorKey.currentState == null) {
    debugPrint("❌ Navigator timeout!");
    return;
  }

  debugPrint("✅ Navigator hazır");

  // Auth'u bekle
  attempts = 0;
  while (attempts < 50) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.token != null &&
            authProvider.currentUser != null &&
            !authProvider.isLoading) {
          debugPrint("✅ Auth hazır");
          return;
        }
      } catch (e) {
        // Provider henüz erişilebilir değil
      }
    }

    await Future.delayed(const Duration(milliseconds: 100));
    attempts++;
  }

  debugPrint("❌ Auth timeout!");
}

// ✅ YENİ: Video call navigation işlemi
Future<void> _navigateToVideoCall({
  required String type,
  required String roomId,
  required String starterId,
  required String starterName,
  String? groupId,
  String? groupName,
  required String chatId,
  String? actionId,
}) async {
  final context = navigatorKey.currentContext;
  if (context == null) {
    debugPrint("❌ Context null, navigation iptal");
    return;
  }

  final signalr = Provider.of<SignalrService>(context, listen: false);
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final chatProvider = Provider.of<ChatProvider>(context, listen: false);
  final notifProvider = Provider.of<NotificationProvider>(
    context,
    listen: false,
  );
  final conferenceProvider = Provider.of<ConferenceProvider>(
    context,
    listen: false,
  );

  // SignalR başlat
  if (!signalr.isConnected) {
    debugPrint("⚠️ SignalR başlatılıyor...");
    await signalr.start(
      authProvider.currentUser!.userId!,
      authProvider.token!,
      chatProvider,
      notifProvider,
    );
    await signalr.syncGroupSubscriptions();
    debugPrint("✅ SignalR başlatıldı");
  }

  // ConferenceProvider'a call data'yı set et
  conferenceProvider.setIncomingCallFromNotification(
    roomId: roomId,
    starterId: starterId,
    groupId: groupId,
    isGroup: type == 'GROUP_VIDEO_CALL',
  );

  debugPrint("✅ ConferenceProvider set edildi");

  final ApiService apiService = ApiService();

  if (type == 'GROUP_VIDEO_CALL' && groupId != null) {
    // Grup video call
    debugPrint("📞 Grup video call'a navigate ediliyor: $groupId");

    try {
      await signalr.methods?.joinMultipleGroups([groupId]);
      final dbMessages = await apiService.messageApi.getGroupMessagesFromDb(
        groupId,
        authProvider.token!,
      );
      if (dbMessages.isNotEmpty) {
        chatProvider.setMessages(groupId, dbMessages);
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

    debugPrint("✅ Grup Chat sayfası açıldı (Video call)");
  } else {
    // P2P video call
    debugPrint("📞 P2P video call'a navigate ediliyor: $chatId");

    try {
      final dbMessages = await apiService.messageApi.getMessagesFromDb(
        authProvider.currentUser!.userId!,
        chatId,
        authProvider.token!,
      );
      if (dbMessages.isNotEmpty) {
        chatProvider.setMessages(chatId, dbMessages);
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

    debugPrint("✅ P2P Chat sayfası açıldı (Video call)");
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ✅ YENİ: FCM setup'ı hemen başlat (token kontrolü FcmService içinde yapılacak)
    // Bu sayede killed/resume durumlarında bildirim navigation'ı kaçmaz
    FcmService().setupInteractedMessages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    final signalrService = Provider.of<SignalrService>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    // 🚩 paused: Uygulama arka plana atıldı
    if (state == AppLifecycleState.paused) {
      debugPrint("📴 Uygulama arka plana geçti, SignalR kesiliyor...");
      signalrService.stop();
    }
    // 🚩 resumed: Kullanıcı uygulamaya geri döndü
    else if (state == AppLifecycleState.resumed) {
      debugPrint("🔄 Uygulama geri geldi, kontrol ediliyor...");

      if (auth.isAuthenticated) {
        // 1. SignalR bağlantısını geri yükle
        if (!signalrService.isConnected) {
          await signalrService.start(
            auth.currentUser!.userId!,
            auth.token!,
            Provider.of<ChatProvider>(context, listen: false),
            Provider.of<NotificationProvider>(context, listen: false),
          );
        }

        // 2. Aktif chat sayfasına "Verileri DB'den tazele" sinyali gönder
        // Bu sinyal ChatScreen ve GroupChatScreen içindeki dinleyiciyi tetikler
        signalrService.notifyAppResumed();
        debugPrint("📡 Aktif sayfalara senkronizasyon sinyali gönderildi.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Stack(
        children: [
          child!,
          const IncomingCallOverlay(),
          const VideoCallOverlay(),
        ],
      ),
      home: const AuthenticationWrapper(),
    );
  }
}

class AuthenticationWrapper extends StatelessWidget {
  const AuthenticationWrapper({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return auth.isAuthenticated
        ? const ExploreUsersScreen()
        : const LoginPage();
  }
}
