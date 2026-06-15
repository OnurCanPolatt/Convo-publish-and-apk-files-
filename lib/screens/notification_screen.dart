import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notification_model.dart';
import '../models/user.dart';
import '../providers/notification_provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../providers/discovery_provider.dart';
import '../services/signalr/signalr_service.dart';
import '../widgets/user_detail_modal.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  final ApiService _apiService = ApiService();

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  @override
  void initState() {
    super.initState();

    // Provider'ın listener'ının başlatıldığından emin ol
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final signalr = context.read<SignalrService>();
      final notifProvider = context.read<NotificationProvider>();

      // Provider'da listener yoksa başlat
      notifProvider.ensureListenerStarted(
        signalr,
        auth.token ?? "",
        _apiService,
      );
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "";
    try {
      DateTime dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final isToday =
          dt.day == now.day && dt.month == now.month && dt.year == now.year;
      final String hour = dt.hour.toString().padLeft(2, '0');
      final String minute = dt.minute.toString().padLeft(2, '0');

      if (isToday) return "$hour:$minute";
      return "${dt.day}.${dt.month}.${dt.year} $hour:$minute";
    } catch (e) {
      debugPrint("⚠️ Tarih formatı hatası: $dateStr");
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);
    final discoveryProvider = Provider.of<DiscoveryProvider>(
      context,
      listen: false,
    );
    final String token = authProvider.token ?? "";
    final String currentUserId = authProvider.currentUser?.userId ?? "";

    // Bildirimleri okundu işaretle (sadece bir kez çalışır)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (token.isNotEmpty && mounted) {
        context.read<NotificationProvider>().markAllAsReadInDb(
          apiService,
          token,
        );
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          _isSelectionMode ? "${_selectedIds.length} Seçildi" : "Bildirimler",
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : const BackButton(),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () => _handleDeleteSelected(apiService, token),
            )
          else
            TextButton(
              onPressed: () =>
                  _handleClearAll(apiService, token, currentUserId),
              child: const Text(
                "Tümünü Temizle",
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, notifProvider, child) {
          final allNotifications = notifProvider.allNotifications;

          if (allNotifications.isEmpty && !notifProvider.isLoading) {
            return const Center(
              child: Text(
                "Henüz bildiriminiz yok.",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: allNotifications.length + 1,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, index) {
              if (index < allNotifications.length) {
                final item = allNotifications[index];
                final String senderId = item.senderId;

                // Kendi bildirimlerini gösterme
                if (senderId.toLowerCase() == currentUserId.toLowerCase()) {
                  return const SizedBox.shrink();
                }

                final String id = item.id;
                final bool isSelected = _selectedIds.contains(id);

                return GestureDetector(
                  onLongPress: () => _toggleSelection(id),
                  onTap: () {
                    if (_isSelectionMode) _toggleSelection(id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.red.withOpacity(0.05)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isSelected
                            ? Colors.red.shade200
                            : Colors.transparent,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildNotificationCard(
                      context,
                      item,
                      token,
                      currentUserId,
                      discoveryProvider,
                      notifProvider,
                      isSelected,
                    ),
                  ),
                );
              } else {
                return _buildLoadMoreButton(
                  notifProvider,
                  authProvider,
                  apiService,
                );
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _handleDeleteSelected(ApiService api, String token) async {
    bool confirm = await _showConfirmDialog(
      "Seçili bildirimler silinecek. Emin misiniz?",
    );
    if (confirm) {
      await context.read<NotificationProvider>().deleteSelectedNotifications(
        _selectedIds.toList(),
        api,
        token,
      );
      _clearSelection();
    }
  }

  Future<void> _handleClearAll(
    ApiService api,
    String token,
    String userId,
  ) async {
    bool confirm = await _showConfirmDialog(
      "Tüm bildirimler temizlenecek. Emin misiniz?",
    );
    if (confirm) {
      await context.read<NotificationProvider>().clearAllNotifications(
        userId,
        api,
        token,
      );
    }
  }

  Future<bool> _showConfirmDialog(String message) async {
    return await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Onay"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Vazgeç"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Sil", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildNotificationCard(
    BuildContext context,
    NotificationModel item,
    String token,
    String currentUserId,
    DiscoveryProvider discovery,
    NotificationProvider notifProvider,
    bool isSelected,
  ) {
    final String senderId = item.senderId;
    final String senderName = item.senderName;
    final String message = item.message;
    final String dateStr = item.date;
    final String senderImageUrl = item.senderImageUrl;
    final bool isRequest = item.isRequest;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: GestureDetector(
        onTap: () => senderId.isNotEmpty
            ? UserDetailModal.show(context, senderId)
            : null,
        child: CircleAvatar(
          radius: 26,
          // 🚀 KRİTİK: ValueKey - her lastUpdate değiştiğinde yeni widget
          key: ValueKey("avatar_${senderId}_${item.lastUpdate ?? '0'}"),

          backgroundColor: Colors.grey[200],
          child:
              (senderImageUrl.isNotEmpty && senderImageUrl.startsWith('http'))
              ? ClipOval(
                  child: Image.network(
                    senderImageUrl,
                    fit: BoxFit.cover,
                    width: 52,
                    height: 52,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        debugPrint("✅ UI: Resim yüklendi - $senderImageUrl");
                        return child;
                      }

                      final progress =
                          loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null;

                      if (progress != null) {
                        debugPrint(
                          "⏳ UI: Yükleniyor... ${(progress * 100).toInt()}%",
                        );
                      }

                      return Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress,
                          color: Colors.deepPurple,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                      debugPrint("❌ UI: RESİM HATASI!");
                      debugPrint("   URL: $senderImageUrl");
                      debugPrint("   SenderId: $senderId");
                      debugPrint("   Error: $error");
                      debugPrint("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

                      return const Icon(
                        Icons.person,
                        size: 30,
                        color: Colors.grey,
                      );
                    },
                    cacheWidth: 104, // 52 * 2 (retina için)
                    cacheHeight: 104,
                  ),
                )
              : Icon(Icons.person, size: 30, color: Colors.grey[600]),
        ),
      ),
      title: Text(
        senderName,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(dateStr),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      trailing: isRequest
          ? _buildRequestActions(
              senderId,
              token,
              currentUserId,
              discovery,
              notifProvider,
            )
          : null,
    );
  }

  Widget _buildRequestActions(
    String senderId,
    String token,
    String currentUserId,
    DiscoveryProvider discovery,
    NotificationProvider notifProvider,
  ) {
    return Row(
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
            notifProvider.markRequestAsAccepted(senderId);
          },
        ),
        IconButton(
          icon: const Icon(Icons.cancel, color: Colors.redAccent),
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
    );
  }

  Widget _buildLoadMoreButton(
    NotificationProvider provider,
    AuthProvider auth,
    ApiService api,
  ) {
    if (!provider.isLoading && provider.allNotifications.length < 5) {
      return const SizedBox.shrink();
    }

    return provider.isLoading
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        : TextButton(
            onPressed: () => provider.loadMoreNotifications(
              auth.currentUser!.userId!,
              auth.token!,
              api,
            ),
            child: const Text("Daha eski bildirimleri gör"),
          );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
