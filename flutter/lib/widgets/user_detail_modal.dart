import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';

// Modeller, Enumlar ve Servisler
import '../enums/friendship_status.dart';
import '../models/notification_model.dart';
import '../models/user.dart';
import '../models/friend.dart';
import '../services/profile_service.dart';
import '../services/auth_provider.dart';
import '../services/signalr/signalr_service.dart';

// Providerlar ve Ekranlar
import '../providers/discovery_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/chat_provider.dart';
import '../screens/chat_screen.dart';
import 'fullscreen_image_page.dart';

class UserDetailModal extends StatefulWidget {
  final String userId;
  final bool showActions;

  const UserDetailModal({
    super.key,
    required this.userId,
    this.showActions = true,
  });

  static void show(
    BuildContext context,
    String userId, {
    bool showActions = true,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "UserDetail",
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Center(
        child: UserDetailModal(userId: userId, showActions: showActions),
      ),
    );
  }

  @override
  State<UserDetailModal> createState() => _UserDetailModalState();
}

class _UserDetailModalState extends State<UserDetailModal>
    with SingleTickerProviderStateMixin {
  late Future<User?> _userFuture;
  StreamSubscription? _signalrSubscription;

  late AnimationController _controller;
  double _angle = 0.0;

  @override
  void initState() {
    super.initState();
    _userFuture = _loadUserDetails();
    _setupSignalRListener();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _setupSignalRListener() {
    final signalr = context.read<SignalrService>();
    _signalrSubscription = signalr.friendEventStream.listen((data) async {
      final type = data['type'];
      final eventUserId = data['userId']?.toString();

      if ((type == 'FriendListChanged' ||
              type == 'InfoUpdated' ||
              type == 'ReceiveUserInfoUpdated') &&
          eventUserId?.toLowerCase() == widget.userId.toLowerCase()) {
        if (mounted) {
          debugPrint("📡 Modal: Anlık güncelleme tetiklendi!");

          // 🚀 KRİTİK: Eğer resim güncellendiyse önbelleği temizle
          // (API'den yeni URL gelmeden önce eskisini siliyoruz)
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();

          setState(() {
            // Future'ı yenileyerek build'i tetikliyoruz
            _userFuture = _loadUserDetails();
          });
        }
      }
    });
  }

  Future<User?> _loadUserDetails() async {
    final auth = context.read<AuthProvider>();
    final profileService = ProfileService(Dio());
    final chatProvider = context.read<ChatProvider>();
    final discoveryProvider = context.read<DiscoveryProvider>();
    final notifProvider = context.read<NotificationProvider>();

    try {
      final user = await profileService.getUserDetail(
        widget.userId,
        auth.token ?? "",
      );
      if (user != null) {
        // ✅ Statü Senkronizasyonu
        if (chatProvider.chatCache.containsKey(user.id.toLowerCase())) {
          user.status = 3;
        } else {
          try {
            final liveUser = discoveryProvider.users.firstWhere(
              (u) => u.id.toLowerCase() == user.id.toLowerCase(),
            );
            user.status = liveUser.status;
          } catch (_) {
            final hasIncomingReq = notifProvider.allNotifications.any(
              (n) =>
                  n is NotificationModel && // Tip kontrolü ekle
                  n.senderId.toLowerCase() == user.id.toLowerCase() &&
                  n.isRequest == true,
            );
            if (hasIncomingReq) user.status = 2;
          }
        }
        user.profileImageUrl = await profileService.getProfileImageUrl(
          widget.userId,
          auth.token ?? "",
        );
      }
      return user;
    } catch (e) {
      return null;
    }
  }

  // 🚀 Buton İşlemlerini Yöneten Metot
  Future<void> _handleFriendAction(User user, String action) async {
    final auth = context.read<AuthProvider>();
    final discoveryProvider = context.read<DiscoveryProvider>();
    final notifProvider = context.read<NotificationProvider>();

    // Backend işlemini başlat
    await discoveryProvider.handleFriendAction(
      user.id,
      auth.token ?? "",
      action,
      auth.currentUser?.userId ?? "",
      notifProvider,
    );

    // ✅ İşlem sonrası UI'ı güncellemek için veriyi tekrar yükle
    if (mounted) {
      setState(() {
        _userFuture = _loadUserDetails();
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _angle -= details.delta.dx * 0.01;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    double targetAngle = (_angle / pi).round() * pi;
    final Animation<double> animation = Tween<double>(
      begin: _angle,
      end: targetAngle,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    animation.addListener(() {
      setState(() {
        _angle = animation.value;
      });
    });
    _controller.forward(from: 0);
  }

  bool _isBackSide() {
    double normalizedAngle = _angle.abs() % (2 * pi);
    return normalizedAngle > pi / 2 && normalizedAngle < 1.5 * pi;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        height: MediaQuery.of(context).size.height * 0.6,
        // ✅ Consumer'ı tekrar ekledik ki provider değişimlerinde butonlar anlık güncellensin
        child: Consumer<DiscoveryProvider>(
          builder: (context, discoveryProvider, child) {
            return FutureBuilder<User?>(
              future: _userFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final user = snapshot.data!;

                return GestureDetector(
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(_angle),
                    child: _isBackSide()
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(pi),
                            child: _buildBackCard(user),
                          )
                        : _buildFrontCard(user),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildFrontCard(User user) {
    // Profil resmi var mı kontrolü
    final bool hasImage =
        user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty;

    final String imageUrl = hasImage
        ? "${user.profileImageUrl}?t=${DateTime.now().millisecondsSinceEpoch}"
        : "";

    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: GestureDetector(
                onTap: () {
                  // 🚀 EĞER RESİM VARSA FULLSCREEN AÇ, YOKSA HİÇBİR ŞEY YAPMA
                  if (hasImage) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullscreenImagePage(
                          imageUrl: imageUrl,
                          tag: 'modal_image_${user.id}',
                        ),
                      ),
                    );
                  }
                },
                child: Hero(
                  tag: 'modal_image_${user.id}',
                  child: hasImage
                      ? Image.network(
                          user.profileImageUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildPlaceholderIcon(),
                        )
                      : _buildPlaceholderIcon(), // 🚀 Resim yoksa sadece ikon bas
                ),
              ),
            ),
          ),
          // ... (Expanded flex 4 kısmı aynı kalıyor)
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  if (widget.showActions)
                    _buildActionArea(user)
                  else
                    const SizedBox(height: 10),
                  const Spacer(),
                  Text(
                    "${user.firstName}, ${user.age}",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "${user.city}, ${user.country}",
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "🔄 Çevirmek için parmağınızla kaydırın",
                    style: TextStyle(fontSize: 10, color: Colors.blueAccent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🚀 Placeholder helper metodu
  Widget _buildPlaceholderIcon() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[300],
      child: const Center(
        child: Icon(
          Icons.person,
          size: 80,
          color: Colors.white70, // Biraz daha yumuşak bir renk
        ),
      ),
    );
  }

  Widget _buildActionArea(User user) {
    final status = FriendshipStatus.values[user.status];
    switch (status) {
      case FriendshipStatus.areFriends:
        return Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: () => _navigateToChat(user),
                style: _btnStyle(Colors.blueAccent),
                icon: const Icon(Icons.send, size: 16),
                label: const Text("Mesaj"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: ElevatedButton(
                onPressed: () => _handleFriendAction(user, "remove_friend"),
                style: _btnStyle(Colors.orange),
                child: const Icon(Icons.person_remove, size: 18),
              ),
            ),
          ],
        );
      case FriendshipStatus.sentByMe:
        return ElevatedButton.icon(
          onPressed: () => _handleFriendAction(user, "remove_request"),
          style: _btnStyle(Colors.redAccent),
          icon: const Icon(Icons.close, size: 18),
          label: const Text("İsteği İptal Et"),
        );
      case FriendshipStatus.sentToMe:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleFriendAction(user, "accept"),
                style: _btnStyle(Colors.green),
                child: const Text("Kabul Et"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleFriendAction(user, "reject"),
                style: _btnStyle(Colors.red),
                child: const Text("Reddet"),
              ),
            ),
          ],
        );
      default:
        return ElevatedButton.icon(
          onPressed: () => _handleFriendAction(user, "send"),
          style: _btnStyle(Colors.blue),
          icon: const Icon(Icons.person_add),
          label: const Text("Arkadaş Ekle"),
        );
    }
  }

  ButtonStyle _btnStyle(Color color) => ElevatedButton.styleFrom(
    backgroundColor: color,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _buildBackCard(User user) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      color: Colors.blueGrey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              "Hakkımda",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  user.about ?? "Hakkında bilgisi yok.",
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const Text(
              "🔄 Geri dönmek için parmağınızla kaydırın",
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: const Center(child: Text("Kullanıcı bilgileri alınamadı.")),
  );

  void _navigateToChat(User user) {
    final friend = FriendModel(
      id: user.id,
      userName: user.username,
      firstName: user.firstName,
      lastName: user.lastName,
      imageUrl: user.profileImageUrl,
    );
    context.read<ChatProvider>().setActiveChat(user.id);
    Navigator.of(context).pop();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          friendModel: friend,
          signalRService: context.read<SignalrService>(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _signalrSubscription?.cancel();
    super.dispose();
  }
}
