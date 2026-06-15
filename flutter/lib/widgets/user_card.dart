import 'dart:async';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/widgets/user_detail_modal.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/discovery_provider.dart';
import '../providers/notification_provider.dart';
import '../screens/chat_screen.dart';
import '../services/auth_provider.dart';
import '../services/signalr/signalr_service.dart';
import '../models/friend.dart';
import '../providers/chat_provider.dart';

class UserCard extends StatefulWidget {
  final User user;
  const UserCard({super.key, required this.user});

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  bool _isProcessing = false;
  StreamSubscription? _signalrSubscription;

  @override
  void initState() {
    super.initState();
    _setupSignalRListener();
  }

  void _setupSignalRListener() {
    final signalr = context.read<SignalrService>();
    final auth = context.read<AuthProvider>();

    _signalrSubscription = signalr.friendEventStream.listen((data) async {
      if (!mounted) return;
      final String? type = data['type'];
      final String? eventUserId = data['userId']?.toString();

      if (eventUserId != null &&
          eventUserId.toLowerCase() == widget.user.id.toLowerCase()) {
        if (type == 'InfoUpdated' || type == 'ReceiveUserInfoUpdated') {
          debugPrint("📡 Card: DB'den taze veri çekiliyor...");

          // 🚀 DATABASE'den YENİ VERİYİ ÇEK (DetailModal'daki gibi)
          final discoveryProvider = context.read<DiscoveryProvider>();

          // Bu metodun Provider içinde API'ye gidip o kullanıcıyı tazelediğinden emin olmalıyız
          await discoveryProvider.fetchAndRefreshUser(
            eventUserId,
            auth.token ?? "",
          );

          if (mounted) setState(() {}); // UI'ı zorla yenile
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🚀 ÖNEMLİ: DiscoveryProvider'ı Consumer ile dinleyelim ki
    // Provider notifyListeners() dediğinde kart kendini yenilesin.
    return Consumer<DiscoveryProvider>(
      builder: (context, discoveryProvider, child) {
        // Provider içindeki güncel kullanıcı verisini bulalım
        final currentUser = discoveryProvider.users.firstWhere(
          (u) => u.id == widget.user.id,
          orElse: () => widget.user,
        );

        final bool hasImage =
            currentUser.profileImageUrl != null &&
            currentUser.profileImageUrl!.isNotEmpty;

        // 📸 Cache kırma mekanizması
        final String displayImageUrl = hasImage
            ? (currentUser.profileImageUrl!.contains('?t=')
                  ? currentUser.profileImageUrl!
                  : "${currentUser.profileImageUrl}?t=${DateTime.now().millisecondsSinceEpoch}")
            : "";

        return GestureDetector(
          onTap: () => UserDetailModal.show(context, currentUser.id),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. FOTOĞRAF ALANI
                Expanded(
                  flex: 6,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: hasImage
                        ? Image.network(
                            displayImageUrl,
                            // 🚀 KRİTİK: Sadece displayImageUrl yetmez, yanına milisaniye ekleyerek
                            // Flutter'ın önbelleği (cache) tamamen yok saymasını sağlıyoruz.
                            key: ValueKey(
                              "$displayImageUrl-${DateTime.now().millisecondsSinceEpoch}",
                            ),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              // Hata durumunda inatçı önbelleği temizle
                              PaintingBinding.instance.imageCache.evict(
                                NetworkImage(displayImageUrl),
                              );
                              return _buildPlaceholder();
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              );
                            },
                          )
                        : _buildPlaceholder(),
                  ),
                ),

                // 2. BİLGİ ALANI
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${currentUser.firstName}, ${currentUser.age}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "@${currentUser.username}",
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                currentUser.city,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 6, thickness: 0.5),
                        _buildActionButtons(context, currentUser),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.person, size: 50, color: Colors.white70),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, User user) {
    final auth = context.read<AuthProvider>();
    final discoveryProvider = context.read<DiscoveryProvider>();
    final notifProvider = context.read<NotificationProvider>();

    if (_isProcessing) {
      return const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Center(
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          if (user.status == 1)
            _smallActionButton(
              Icons.close,
              Colors.red,
              "İptal",
              () => discoveryProvider.handleFriendAction(
                user.id,
                auth.token ?? "",
                "remove_request",
                auth.currentUser?.userId ?? "",
                notifProvider,
              ),
            )
          else if (user.status == 2) ...[
            _smallActionButton(
              Icons.close,
              Colors.red,
              "Red",
              () => discoveryProvider.handleFriendAction(
                user.id,
                auth.token ?? "",
                "reject",
                auth.currentUser?.userId ?? "",
                notifProvider,
              ),
            ),
            _smallActionButton(
              Icons.check,
              Colors.green,
              "Kabul",
              () => discoveryProvider.handleFriendAction(
                user.id,
                auth.token ?? "",
                "accept",
                auth.currentUser?.userId ?? "",
                notifProvider,
              ),
            ),
          ] else if (user.status == 3) ...[
            _smallActionButton(Icons.message, Colors.blue, "Mesaj", () async {
              final friend = FriendModel(
                id: user.id,
                userName: user.username,
                firstName: user.firstName,
                lastName: user.lastName,
                imageUrl: user.profileImageUrl,
              );
              context.read<ChatProvider>().setActiveChat(user.id);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    friendModel: friend,
                    signalRService: context.read<SignalrService>(),
                  ),
                ),
              );
              if (mounted) context.read<ChatProvider>().setActiveChat(null);
            }),
            _smallActionButton(
              Icons.person_remove,
              Colors.orange,
              "Çıkar",
              () => discoveryProvider.handleFriendAction(
                user.id,
                auth.token ?? "",
                "remove_friend",
                auth.currentUser?.userId ?? "",
                notifProvider,
              ),
            ),
          ] else
            _smallActionButton(
              Icons.person_add,
              Colors.blue,
              "Ekle",
              () => discoveryProvider.handleFriendAction(
                user.id,
                auth.token ?? "",
                "send",
                auth.currentUser?.userId ?? "",
                notifProvider,
              ),
            ),
        ],
      ),
    );
  }

  Widget _smallActionButton(
    IconData icon,
    Color color,
    String tooltip,
    Future<void> Function() onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          setState(() => _isProcessing = true);
          await onTap();
          if (mounted) setState(() => _isProcessing = false);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5), width: 0.5),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _signalrSubscription?.cancel();
    super.dispose();
  }
}
