import 'dart:async';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/screens/login_page.dart';
import 'package:my_first_flutterapp/screens/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';
import 'package:my_first_flutterapp/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_first_flutterapp/services/signalr/signalr_service.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/models/friend.dart';
import 'package:my_first_flutterapp/screens/chat_screen.dart';
import 'package:my_first_flutterapp/providers/chat_provider.dart';
import 'package:my_first_flutterapp/screens/create_group_screen.dart';
import 'package:my_first_flutterapp/models/chat_list_item.dart';
import '../providers/discovery_provider.dart';
import '../providers/notification_provider.dart';
import '../services/fcm_service.dart';
import '../widgets/fullscreen_image_page.dart';
import '../widgets/user_detail_modal.dart';
import 'discovery_screen.dart';
import 'empty_friends_state.dart';
import 'group_chat_screen.dart';
import 'notification_screen.dart';

/// ------------------------------------------------------------
/// GEÇİCİ BOŞ SAYFALAR
/// ------------------------------------------------------------
class EmptyPage extends StatelessWidget {
  final String title;
  const EmptyPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text("$title Sayfası Henüz Hazır Değil")),
    );
  }
}

/// ------------------------------------------------------------
/// ASIL EKRAN – ExploreUsersScreen
/// ------------------------------------------------------------
class ExploreUsersScreen extends StatefulWidget {
  const ExploreUsersScreen({super.key});

  @override
  State<ExploreUsersScreen> createState() => _ExploreUsersScreenState();
}

class _ExploreUsersScreenState extends State<ExploreUsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedIndices = {};
  final SecureStorageService _storageService = SecureStorageService();
  final ApiService _apiService = ApiService();
  StreamSubscription? _friendEventSubscription;
  StreamSubscription? _signalrReconnectSubscription;
  StreamSubscription<void>? _appResumedSubscription;

  List<ChatListItem> _fullList = [];
  List<ChatListItem> _filteredUsers = [];

  bool _isLoadingData = true;
  bool _isFetching = false; // ✅ Duplicate fetch guard için ayrı flag

  void _toggleSelection(int index) {
    final item = _filteredUsers[index];
    if (item is! UserItem && item is! GroupItem) return;

    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  @override
  void initState() {
    super.initState();

    final signalr = context.read<SignalrService>();

    // 1. 📢 Arkadaş ve Grup Etkinliklerini Dinle (SignalR Events)
    _friendEventSubscription = signalr.friendEventStream.listen((data) {
      if (!mounted) return;

      final String? type = data['type'];
      final String? eventUserId = data['userId']?.toString();
      final String? groupId = data['groupId']?.toString();

      debugPrint("📡 ExploreUsersScreen: SignalR Event - type: $type");

      // ✅ FIX: Liste yapısı değiştiğinde API'ye git
      if (type == 'FriendListChanged' ||
          type == 'GroupCreated' ||
          type == 'GroupDeleted' ||
          type == 'GroupInfoUpdated') {
        debugPrint(
          "🔄 Liste yapısı değişti (grup silindi/eklendi), API'den yükleniyor...",
        );

        // ✅ YENİ: Grup oluşturuldu/eklendi ise SignalR grubuna JOIN yap
        if (type == 'GroupCreated' && groupId != null) {
          debugPrint("🔗 SignalR: Yeni gruba katılınıyor - GroupId: $groupId");
          signalr.methods?.joinMultipleGroups([groupId]).then((success) {
            if (success == true) {
              debugPrint("✅ SignalR: Yeni gruba başarıyla katıldı: $groupId");
            } else {
              debugPrint("⚠️ SignalR: Gruba katılma başarısız: $groupId");
            }
          });
        }

        _fetchInitialData(); // Listeyi tazele
      }
      // ✅ YENİ: UserLeftGroup için özel kontrol
      else if (type == 'UserLeftGroup') {
        debugPrint("🚪 UserLeftGroup eventi alındı");
        debugPrint("   GroupId: $groupId");
        debugPrint("   UserId (atılan): $eventUserId");

        // Kendi ID'mizi alalım
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final String myId = authProvider.currentUser?.userId ?? "";

        debugPrint("   MyId: $myId");

        // ✅ Eğer atılan kişi BİZSEK, listeyi yenile
        if (eventUserId != null &&
            eventUserId.toLowerCase() == myId.toLowerCase()) {
          debugPrint("✅ BEN gruptan atıldım/ayrıldım, liste yenileniyor...");
          _fetchInitialData();
        } else {
          debugPrint("ℹ️ Başkası gruptan ayrıldı, beni ilgilendirmiyor");
        }
      }
      // ✅ FIX: Sadece bilgi güncellenmesi - API'ye gitme
      else if (type == 'InfoUpdated' || type == 'GroupInfoUpdated') {
        debugPrint(
          "🔄 Kullanıcı/Grup bilgisi güncellendi, sadece UI güncelleniyor...",
        );
        if (groupId != null) {
          _refreshGroupInfo(groupId); // Sadece o grubu güncelle
        } else if (eventUserId != null) {
          _refreshUserImage(eventUserId); // Sadece o kullanıcıyı güncelle
        }
      }
      // ✅ Profil fotoğrafı güncellendi
      else if (type == 'ReceiveUserInfoUpdated' || type == 'MyInfo') {
        _refreshUserImage(eventUserId);
      }
    });

    // 2. 🔌 ✅ YENİ: SignalR Reconnect Listener (Hatasız Versiyon)
    // Eski addListener(...) as StreamSubscription hatasını bu yapı çözer.
    _signalrReconnectSubscription = signalr.connectionStateStream.listen((
      isConnected,
    ) {
      if (isConnected && mounted) {
        debugPrint(
          "🔄 MessagesScreen: SignalR reconnect algılandı! Gruplara yeniden katılınıyor...",
        );

        // Mevcut listedeki grupları bulup ID'lerini alıyoruz
        final currentGroups = _fullList.whereType<GroupItem>().toList();
        if (currentGroups.isNotEmpty) {
          final groupIds = currentGroups.map((g) => g.id).toList();

          debugPrint(
            "🔄 Reconnect: ${groupIds.length} gruba yeniden katılınıyor...",
          );

          // SignalR üzerinden gruplara tekrar abone ol
          signalr.methods?.joinMultipleGroups(groupIds).then((success) {
            if (success) {
              debugPrint("✅ Reconnect: Tüm gruplara başarıyla yeniden katıldı");
            } else {
              debugPrint("⚠️ Reconnect: Gruplara katılma başarısız");
            }
          });
        }

        // Bağlantı gelince verileri bir kez tazelemek her zaman iyidir
        _fetchInitialData();
      }
    });
    _appResumedSubscription = signalr.appResumedStream.listen((_) {
      if (mounted) {
        debugPrint("📱 Uygulama ön plana geldi, liste tazeleniyor...");
        _fetchInitialData(); // API'den arkadaş ve grup listesini yeniden çek

        // SignalR gruplarına yeniden katıl
        final currentGroups = _fullList.whereType<GroupItem>().toList();
        if (currentGroups.isNotEmpty) {
          final groupIds = currentGroups.map((g) => g.id).toList();
          signalr.methods?.joinMultipleGroups(groupIds);
        }
      }
    });

    // 3. 🚀 Başlangıç Servislerini ve Verilerini Başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServicesAndData();
    });

    // 4. 🔍 Arama Çubuğu Filtreleme Dinleyicisi
    _searchController.addListener(_applyFilters);
  }

  Future<void> _refreshGroupInfo(String groupId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;

    if (token == null) return;

    try {
      // Sadece o grubu API'den çek
      final freshData = await _apiService.group.getFreshGroupInfo(
        groupId,
        token,
      );

      if (freshData != null && mounted) {
        // Listedeki o grubu bul ve güncelle
        final groupIndex = _fullList.indexWhere(
          (item) => item is GroupItem && item.id == groupId,
        );

        if (groupIndex != -1) {
          final group = _fullList[groupIndex] as GroupItem;
          setState(() {
            group.name = freshData.name ?? group.name;
            group.imageUrl =
                "${freshData.imageUrl}?t=${DateTime.now().millisecondsSinceEpoch}";
          });
          debugPrint("✅ Grup bilgisi güncellendi: ${group.name}");
        }
      }
    } catch (e) {
      debugPrint("❌ Grup bilgisi güncelleme hatası: $e");
    }
  }

  Future<void> _refreshUserImage(String? userId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;

    if (token == null) return;

    // Eğer userId belirtilmişse sadece o kullanıcıyı güncelle
    if (userId != null && userId.isNotEmpty) {
      final users = _fullList.whereType<UserItem>().toList();

      for (var user in users) {
        if (user.id.toLowerCase() == userId.toLowerCase()) {
          try {
            final newUrl = await _apiService.profile.getProfileImageUrl(
              user.id,
              token,
            );
            if (mounted && newUrl != null) {
              setState(() {
                user.imageUrl =
                    "$newUrl?t=${DateTime.now().millisecondsSinceEpoch}";
              });
              debugPrint("✅ Kullanıcı fotoğrafı güncellendi: ${user.name}");
            }
          } catch (e) {
            debugPrint("❌ Kullanıcı resmi yenileme hatası: $e");
          }
          break; // Kullanıcıyı bulduk, döngüden çık
        }
      }
    }
    // userId yoksa tüm kullanıcıları güncelle (genel güncelleme)
    else {
      final users = _fullList.whereType<UserItem>().toList();

      for (var user in users) {
        try {
          final newUrl = await _apiService.profile.getProfileImageUrl(
            user.id,
            token,
          );
          if (mounted && newUrl != null) {
            setState(() {
              user.imageUrl =
                  "$newUrl?t=${DateTime.now().millisecondsSinceEpoch}";
            });
          }
        } catch (e) {
          debugPrint("❌ Kullanıcı resmi yenileme hatası: $e");
        }
      }
    }
  }

  // Mevcut grup fotoğrafı güncelleme metodu (değişiklik yok)
  Future<void> _refreshGroupImages() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    // Listedeki tüm grupları bul
    final groups = _fullList.whereType<GroupItem>().toList();

    for (var group in groups) {
      try {
        final freshData = await _apiService.group.getFreshGroupInfo(
          group.id,
          token,
        );
        if (freshData != null && mounted) {
          setState(() {
            // 🚀 Timestamp ekleyerek Flutter'ın cache'ini kırmayı garanti ediyoruz
            group.imageUrl =
                "${freshData.imageUrl}?t=${DateTime.now().millisecondsSinceEpoch}";
            group.name = freshData.name ?? group.name;
          });
        }
      } catch (e) {
        debugPrint("❌ Grup resmi tazeleme hatası: $e");
      }
    }
  }

  Future<void> _initializeServicesAndData() async {
    await _fetchInitialData();
  }

  // 4. KRİTİK METOT: API'den veri çekme ve SignalR'ı başlatma
  Future<void> _fetchInitialData() async {
    debugPrint("🔵 _fetchInitialData ÇAĞRILDI - _isFetching: $_isFetching");

    // ✅ FIX: Duplicate fetch engelleme - Paralel çağrıları önle
    if (_isFetching) {
      debugPrint("⚠️ _fetchInitialData zaten çalışıyor, duplicate engellendi");
      return;
    }

    // Set fetching flag immediately
    _isFetching = true;
    debugPrint("🟢 _fetchInitialData BAŞLADI - Flag set edildi");

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final signalrService = Provider.of<SignalrService>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );

    final token = authProvider.token;
    final userId = authProvider.currentUser?.userId;

    if (userId == null || token == null || token.isEmpty) {
      _isFetching = false;
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
      await _handleLogout();
      return;
    }

    try {
      // 1. ADIM: Bildirimleri Tazele (Hata alsa bile devam et)
      try {
        debugPrint("🔔 Bildirimler tazeleniyor...");
        await notificationProvider.refreshNotifications(
          userId,
          token,
          _apiService,
        );
      } catch (e) {
        debugPrint("⚠️ Bildirim tazeleme hatası (Önemli değil): $e");
      }

      // 2. ADIM: SignalR Bağlantısı
      if (!signalrService.isConnected) {
        await signalrService.start(
          userId,
          token,
          chatProvider,
          notificationProvider,
        );
      }
      FcmService().initialize(userId);
      // 3. ADIM: Ana Verileri Çek (Arkadaşlar ve Gruplar)
      final results = await Future.wait([
        _apiService.beginApi.getMyFriends(userId, token),
        _apiService.beginApi.getMyGroups(userId, token),
        _apiService.beginApi.getOnlineUsersList(token),
      ]).timeout(const Duration(seconds: 10), onTimeout: () => [[], [], []]);

      final friends = results[0] as List<UserItem>;
      final groups = results[1] as List<GroupItem>;

      debugPrint(
        "📊 API'den gelen veri: ${friends.length} arkadaş, ${groups.length} grup",
      );
      debugPrint("📋 Arkadaşlar: ${friends.map((f) => f.name).toList()}");
      debugPrint("📋 Gruplar: ${groups.map((g) => g.name).toList()}");

      chatProvider.updateUserNameCache(friends);
      if (groups.isNotEmpty) {
        chatProvider.updateGroupMetadataFromItems(groups);
        // 🚀 KRİTİK: SignalR Gruplarına Kaydol (Grup mesajları almak için)
        final List<String> groupIdList = groups.map((g) => g.id).toList();
        signalrService.methods?.joinMultipleGroups(groupIdList).then((success) {
          if (success) {
            debugPrint(
              "✅ SignalR: ${groupIdList.length} gruba başarıyla abone olundu.",
            );
          } else {
            debugPrint("❌ SignalR: Gruplara abone olma başarısız!");
          }
        });
      }

      signalrService.setInitialOnlineUsers(results[2] as List<String>);

      // 4. ADIM: UI GÜNCELLEME (Burası resimlerden önce çalışmalı!)
      if (mounted) {
        setState(() {
          _fullList = [...friends, ...groups];
          _filteredUsers = [..._fullList];
          _isLoadingData = false;
        });
      }

      // ExploreUsersScreen.dart içinde resim yükleme döngüsünü şu şekilde güncelle:
      for (var user in friends) {
        _apiService.profile
            .getProfileImageUrl(user.id, token)
            .then((url) {
              if (mounted && url != null) {
                setState(() {
                  // URL'nin sonuna benzersiz bir sayı ekleyerek önbelleği kırıyoruz
                  user.imageUrl =
                      "$url?t=${DateTime.now().millisecondsSinceEpoch}";
                });
              }
            })
            .catchError((e) => debugPrint("🖼️ Resim Hatası: $e"));
      }
      await signalrService.syncGroupSubscriptions();
    } catch (e) {
      debugPrint("💥 Kritik Veri Çekme Hatası: $e");
    } finally {
      _isFetching = false; // ✅ Fetch guard'ı temizle
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  // ✅ YENİ: Alert ile çıkış onayı alan metod
  Future<void> _handleLogout() async {
    // Alert göster
    bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Çıkış Yap',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(
              'Çıkış Yap',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    // Kullanıcı onayladıysa çıkış yap
    if (shouldLogout == true) {
      if (mounted) {
        Provider.of<SignalrService>(context, listen: false).stop();
      }
      await _storageService.deleteToken();
      await _storageService.deleteUserId();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_email');

      if (mounted) {
        Provider.of<AuthProvider>(context, listen: false).logout();
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredUsers = _fullList.where((item) {
        return item.name.toLowerCase().contains(query) ||
            item.subTitle.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _handleTap(int index) async {
    final item = _filteredUsers[index];
    final signalr = Provider.of<SignalrService>(context, listen: false);

    // 1. DURUM: EĞER BİR GRUBA TIKLANDIYSA
    if (item is GroupItem) {
      // 🚀 DÜZELTME: await ekledik ve dönen sonucu 'result' değişkenine aldık.
      // GroupScreen içindeki pop(true) buraya true olarak düşer.
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GroupChatScreen(groupModel: item, signalRService: signalr),
        ),
      );

      // 🚀 KRİTİK: Eğer sayfadan 'true' gelmişse grup silinmiş veya ayrılınmıştır.
      if (result == true && mounted) {
        debugPrint(
          "🔄 ExploreUsersScreen: Gruptan çıkış/silme tespit edildi, liste yenileniyor...",
        );
        await _fetchInitialData(); // Listeyi API'den tekrar çeker
      }
    }
    // 2. DURUM: EĞER BİR KULLANICIYA TIKLANDIYSA
    else if (item is UserItem) {
      final friend = FriendModel(
        id: item.id,
        userName: item.name,
        firstName: item.name.split(' ').first,
        lastName: item.name.contains(' ') ? item.name.split(' ').last : '',
        imageUrl: item.imageUrl,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(friendModel: friend, signalRService: signalr),
        ),
      );
    }

    // Sayfadan geri dönüldüğünde aktif sohbeti temizle
    if (mounted) {
      context.read<ChatProvider>().setActiveChat(null);
    }
  }

  // Sohbetleri Silme (Gizleme) İşlemi
  Future<void> _deleteSelectedChats() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    // Onay Al
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Sohbetleri Sil"),
        content: const Text(
          "Seçili sohbetleri silmek istediğinizden emin misiniz?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoadingData = true); // İşlem sırasında loading göster

    try {
      // Seçilen her bir index için işlem yap
      for (int index in _selectedIndices) {
        final item = _filteredUsers[index];

        if (item is UserItem) {
          // P2P Sohbeti Gizle
          await _apiService.messageApi.hidePrivateChat(item.id, token);
        } else if (item is GroupItem) {
          // Grup Sohbetini Gizle
          await _apiService.messageApi.hideGroupChat(item.id, token);
        }
      }

      // Başarılı uyarısı
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sohbetler başarıyla silindi.")),
        );
      }
    } catch (e) {
      debugPrint("❌ Sohbet silme hatası: $e");
    } finally {
      if (mounted) {
        setState(() {
          _selectedIndices.clear();
          _fullList.clear(); // Listeyi tamamen boşalt
          _filteredUsers.clear();
        });
        await _fetchInitialData(); // Yeni veriyi taze çek
      }
    }
  }

  Widget _buildNotificationListItem(
    BuildContext context,
    dynamic item,
    AuthProvider auth,
    DiscoveryProvider discovery,
    NotificationProvider notifProvider,
  ) {
    // ✅ DÜZELTME: Provider'daki 'senderName' normalizasyonu ile tam uyumlu
    final String senderId = (item['senderId'] ?? "").toString();
    final String senderName = item['senderName'] ?? "Bilinmeyen Kullanıcı";
    final String message = item['message'] ?? "";
    final String senderImageUrl = item['senderImageUrl'] ?? "";
    final String token = auth.token ?? "";
    final String currentUserId = auth.currentUser?.userId ?? "";

    final bool isActionableRequest = item['isRequest'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundImage: senderImageUrl.isNotEmpty
              ? NetworkImage(senderImageUrl)
              : null,
          child: senderImageUrl.isEmpty ? const Icon(Icons.person) : null,
        ),
        title: Text(
          item.senderName, // 👈 Değiştirildi
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(message, style: const TextStyle(fontSize: 12)),
        trailing: isActionableRequest
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () async {
                      await discovery.handleFriendAction(
                        senderId,
                        token,
                        "accept",
                        currentUserId,
                        notifProvider,
                      );
                      notifProvider.removeNotification(senderId);
                      _fetchInitialData();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () async {
                      await discovery.handleFriendAction(
                        senderId,
                        token,
                        "reject",
                        currentUserId,
                        notifProvider,
                      );
                      notifProvider.removeNotification(senderId);
                    },
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildLoadMoreButton(
    NotificationProvider provider,
    AuthProvider auth,
    ApiService api,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: provider.isLoading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : TextButton.icon(
                onPressed: () {
                  final userId = auth.currentUser?.userId;
                  final token = auth.token;
                  if (userId != null && token != null) {
                    // ✅ loadMoreNotifications metodu artık provider'da tanımlı
                    provider.loadMoreNotifications(userId, token, api);
                  }
                },
                icon: const Icon(Icons.history, size: 18),
                label: const Text("Daha eski bildirimleri gör..."),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signalrService = Provider.of<SignalrService>(context, listen: true);

    // ✅ YENİ: Liste boş mu kontrolü
    final bool isEmpty = _filteredUsers.isEmpty && !_isLoadingData;

    List<UserItem> selectedUserItems = _selectedIndices
        .where((index) => _filteredUsers[index] is UserItem)
        .map((index) => _filteredUsers[index] as UserItem)
        .toList();

    if (_isLoadingData) {
      return const Scaffold(
        appBar: null,
        body: Center(
          child: CircularProgressIndicator(color: Colors.deepPurple),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedIndices.isEmpty
              ? "Kullanıcılar"
              : "${_selectedIndices.length} Seçildi",
        ),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, notifProvider, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded),
                    onPressed: () {
                      context.read<NotificationProvider>().resetPendingCount();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationScreen(),
                        ),
                      );
                    },
                  ),
                  if (notifProvider.pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          notifProvider.pendingCount > 9
                              ? "9+"
                              : "${notifProvider.pendingCount}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_selectedIndices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedIndices.clear()),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == "keşfet")
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DiscoveryScreen()),
                );
              if (v == "profil")
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              if (v == "logout") _handleLogout();
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: "keşfet",
                child: ListTile(
                  leading: Icon(Icons.explore),
                  title: Text('Keşfet'),
                ),
              ),
              const PopupMenuItem<String>(
                value: "profil",
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('Profil'),
                ),
              ),
              const PopupMenuItem<String>(
                value: "logout",
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Çıkış Yap'),
                  iconColor: Colors.red,
                  textColor: Colors.red,
                ),
              ),
            ],
          ),
        ],
        // ✅ YENİ: Arama çubuğunu sadece liste doluysa göster
        bottom: isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      filled: true,
                      hintText: "Ara...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      floatingActionButton: _selectedIndices.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Builder(
                builder: (context) {
                  final bool onlyUsersSelected =
                      selectedUserItems.length == _selectedIndices.length;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FloatingActionButton.extended(
                        heroTag: "deleteBtn",
                        onPressed: _deleteSelectedChats,
                        label: const Text("Sohbeti Sil"),
                        icon: const Icon(Icons.delete_sweep),
                        backgroundColor: Colors.redAccent,
                      ),
                      const SizedBox(width: 10),
                      if (_selectedIndices.length >= 2 && onlyUsersSelected)
                        FloatingActionButton.extended(
                          heroTag: "groupBtn",
                          onPressed: () async {
                            final List<UserItem> pureFriendList = _fullList
                                .whereType<UserItem>()
                                .toList();
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateGroupScreen(
                                  selectedUsers: selectedUserItems,
                                  allFriends: pureFriendList,
                                ),
                              ),
                            );
                            if (result == true) _fetchInitialData();
                          },
                          label: const Text("Grup Oluştur"),
                          icon: const Icon(Icons.group_add),
                          backgroundColor: Colors.deepPurple,
                        ),
                    ],
                  );
                },
              ),
            )
          : null,
      // ✅ YENİ: Body'yi koşullu göster
      body: isEmpty
          ? EmptyFriendsState(
              onDiscoverTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DiscoveryScreen()),
                );
              },
            )
          : ListView.builder(
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final item = _filteredUsers[index];
                final isSelected = _selectedIndices.contains(index);
                final bool isUserOnline =
                    item is UserItem &&
                    signalrService.onlineUserIds.contains(
                      item.id.toLowerCase(),
                    );
                final Color statusColor = (item is UserItem && isUserOnline)
                    ? Colors.green
                    : Colors.grey;

                return Card(
                  color: isSelected ? Colors.deepPurple.shade50 : Colors.white,
                  elevation: isSelected ? 4 : 1,
                  child: ListTile(
                    leading: GestureDetector(
                      onTap: () {
                        if (item is UserItem) {
                          final auth = context.read<AuthProvider>();
                          final bool isMe =
                              item.id.toLowerCase() ==
                              auth.currentUser?.userId?.toLowerCase();
                          UserDetailModal.show(
                            context,
                            item.id,
                            showActions: !isMe,
                          );
                        } else if (item is GroupItem) {
                          if (item.imageUrl != null &&
                              item.imageUrl!.isNotEmpty) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullscreenImagePage(
                                  imageUrl:
                                      "${item.imageUrl}?t=${DateTime.now().millisecondsSinceEpoch}",
                                  tag: 'group_image_list_${item.id}',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: Hero(
                        tag: item is GroupItem
                            ? 'group_image_list_${item.id}'
                            : 'user_image_list_${item.id}',
                        child: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: statusColor.withAlpha(
                                (0.1 * 255).toInt(),
                              ),
                              child:
                                  (item.imageUrl != null &&
                                      item.imageUrl!.isNotEmpty)
                                  ? ClipOval(
                                      child: Image.network(
                                        item.imageUrl!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                              if (loadingProgress == null)
                                                return child;
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              );
                                            },
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Icon(
                                                  item is UserItem
                                                      ? Icons.person
                                                      : Icons.group,
                                                  color: statusColor,
                                                ),
                                      ),
                                    )
                                  : Icon(
                                      item is UserItem
                                          ? Icons.person
                                          : Icons.group,
                                      color: statusColor,
                                    ),
                            ),
                            if (isSelected)
                              const Positioned(
                                right: 0,
                                bottom: 0,
                                child: CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.deepPurple,
                                  child: Icon(
                                    Icons.check,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: [
                          TextSpan(text: item.subTitle),
                          if (item is UserItem)
                            TextSpan(
                              text: isUserOnline
                                  ? " ● Çevrimiçi"
                                  : " (Çevrimdışı)",
                              style: TextStyle(
                                color: isUserOnline
                                    ? Colors.green
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                    trailing: isSelected
                        ? null
                        : Consumer<ChatProvider>(
                            builder: (context, chatProvider, child) {
                              final bool isGroup = item is GroupItem;
                              final int unreadCount = isGroup
                                  ? chatProvider.getUnreadGroupCount(item.id)
                                  : chatProvider.getUnreadCount(item.id);

                              if (unreadCount > 0) {
                                return Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 20,
                                    minHeight: 20,
                                  ),
                                  child: Text(
                                    unreadCount > 99
                                        ? "99+"
                                        : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                    onTap: () {
                      if (_selectedIndices.isNotEmpty)
                        _toggleSelection(index);
                      else
                        _handleTap(index);
                    },
                    onLongPress: () => _toggleSelection(index),
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _friendEventSubscription?.cancel();
    _signalrReconnectSubscription?.cancel();
    _appResumedSubscription?.cancel();
    super.dispose();
  }
}
