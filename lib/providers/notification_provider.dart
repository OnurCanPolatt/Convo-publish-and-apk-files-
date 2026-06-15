import 'dart:async';
import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/signalr/signalr_service.dart';

class NotificationProvider with ChangeNotifier {
  List<NotificationModel> _requests = [];
  List<NotificationModel> _infoNotifications = [];
  int _pendingCount = 0;
  bool _isLoading = false;

  int get pendingCount => _pendingCount;
  bool get isLoading => _isLoading;

  // Tüm bildirimleri tek listede birleştirir (UI burayı okur)
  List<NotificationModel> get allNotifications => [
    ..._requests,
    ..._infoNotifications,
  ];

  StreamSubscription? _signalrSubscription;

  // 1. SignalR Merkezi Dinleyicisi
  void ensureListenerStarted(
    SignalrService signalr,
    String token,
    dynamic apiService,
  ) {
    // Listener zaten başlatılmışsa bir şey yapma
    if (_signalrSubscription != null) {
      debugPrint("✅ NotificationProvider listener zaten aktif");
      return;
    }

    debugPrint("🚀 NotificationProvider listener başlatılıyor...");

    _signalrSubscription = signalr.friendEventStream.listen((data) async {
      final String? type = data['type'];
      final String? eventUserId = data['userId']?.toString();

      // Profil güncelleme sinyali geldiğinde
      if ((type == 'InfoUpdated' ||
              type == 'ReceiveUserInfoUpdated' ||
              type == 'MyInfo') &&
          eventUserId != null) {
        debugPrint(
          "📡 Provider Sinyal (Arka Planda): $eventUserId için güncelleme...",
        );

        // Backend'in resmi diske/DB'ye yazması için tolerans süresi
        await Future.delayed(const Duration(milliseconds: 1500));

        try {
          // 🚀 KRİTİK: getUserDetail yerine getProfileImageUrl kullan
          final String? newImageUrl = await apiService.profile
              .getProfileImageUrl(eventUserId, token);

          // İsim için kullanıcı detayını çek (isteğe bağlı)
          final freshUser = await apiService.profile.getUserDetail(
            eventUserId,
            token,
          );

          if (freshUser != null) {
            // Cache temizliği
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();

            updateUserInfoInNotifications(
              eventUserId,
              freshUser.username,
              newImageUrl, // MinIO'dan gelen URL
            );

            debugPrint(
              "✅ Provider: Arka planda güncelleme tamamlandı - ${freshUser.username}",
            );
          }
        } catch (e) {
          debugPrint("❌ Provider Sync Hatası: $e");
        }
      }
    });
  }

  // 2. 🚀 NESNE BAZLI GÜNCELLEME (En Kritik Metot)
  void updateUserInfoInNotifications(
    String userId,
    String newName,
    String? newImageUrl,
  ) {
    final String tag = DateTime.now().millisecondsSinceEpoch.toString();
    bool changed = false;

    // URL'yi temizle ve Base URL ekle
    String? finalImageUrl;
    if (newImageUrl != null && newImageUrl.isNotEmpty) {
      if (!newImageUrl.startsWith('http')) {
        finalImageUrl = "https://convoapp.app$newImageUrl";
      } else {
        finalImageUrl = newImageUrl.split('?').first;
      }
      finalImageUrl = "$finalImageUrl?t=$tag"; // Cache-buster
    }

    // Bilgi bildirimlerini güncelle (Immutable yapı)
    _infoNotifications = _infoNotifications.map((model) {
      if (model.senderId.toLowerCase() == userId.toLowerCase()) {
        changed = true;
        // NESNE REFERANSI DEĞİŞTİRİLİYOR - copyWith yeni nesne döner!
        model.senderName = newName;
        model.senderImageUrl = finalImageUrl ?? model.senderImageUrl;
        model.lastUpdate = tag;
        notifyListeners(); // Her değişiklikte bildir
        return model;
      }
      return model;
    }).toList();

    // İstekleri güncelle
    _requests = _requests.map((model) {
      if (model.senderId.toLowerCase() == userId.toLowerCase()) {
        changed = true;
        model.senderName = newName;
        model.senderImageUrl = finalImageUrl ?? model.senderImageUrl;
        model.lastUpdate = tag;
        notifyListeners(); // Her değişiklikte bildir
        return model;
      }
      return model;
    }).toList();

    if (changed) {
      debugPrint(
        "✅ Provider: $newName bilgileri Object referansıyla yenilendi.",
      );
      _updateTotalCount(); // notifyListeners() bunun içindedir
    }
  }

  // 3. Bildirimleri API'den Refresh Etme
  Future<void> refreshNotifications(
    String userId,
    String token,
    dynamic apiService,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Normal Bildirimler
      final results = await apiService.notification.getMyNotifications(
        token,
        skip: 0,
      );
      if (results is Map<String, dynamic>) {
        final List<dynamic> raw = results['notifications'] ?? [];

        // Kendimizden gelenleri temizle
        raw.removeWhere(
          (item) =>
              (item['senderId'] ?? "").toString().toLowerCase() ==
              userId.toLowerCase(),
        );

        // Resimlerini tek tek çek (Model'e çevirmeden önce)
        for (var item in raw) {
          final sId = (item['senderId'] ?? "").toString();
          if (sId.isNotEmpty) {
            item['senderImageUrl'] = await apiService.profile
                .getProfileImageUrl(sId, token);
          }
        }
        _infoNotifications = raw
            .map((e) => NotificationModel.fromMap(e))
            .toList();
        _infoNotifications.sort((a, b) => b.date.compareTo(a.date));
      }

      // Arkadaşlık İstekleri
      final reqResult = await apiService.request.getFriendRequests(
        userId,
        token,
      );
      if (reqResult is List) {
        reqResult.removeWhere(
          (req) =>
              (req['senderId'] ?? "").toString().toLowerCase() ==
              userId.toLowerCase(),
        );

        for (var req in reqResult) {
          final sId = (req['senderId'] ?? "").toString();
          if (sId.isNotEmpty) {
            req['senderImageUrl'] = await apiService.profile.getProfileImageUrl(
              sId,
              token,
            );
          }
        }
        _requests = reqResult
            .map((e) => NotificationModel.fromMap(e, isRequest: true))
            .toList();
      }

      _updateTotalCount();
    } catch (e) {
      debugPrint("❌ Provider Refresh Hatası: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 4. Daha Fazla Yükleme (Pagination)
  Future<void> loadMoreNotifications(
    String userId,
    String token,
    dynamic apiService,
  ) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      int skipCount = _infoNotifications.length;
      final results = await apiService.notification.getMyNotifications(
        token,
        skip: skipCount,
      );

      if (results is Map<String, dynamic>) {
        final List<dynamic> raw = results['notifications'] ?? [];

        List<NotificationModel> newModels = [];
        for (var item in raw) {
          final sId = (item['senderId'] ?? "").toString();
          if (sId.isNotEmpty) {
            item['senderImageUrl'] = await apiService.profile
                .getProfileImageUrl(sId, token);
          }
          newModels.add(NotificationModel.fromMap(item));
        }

        _infoNotifications.addAll(newModels);
        _infoNotifications.sort((a, b) => b.date.compareTo(a.date));
        _updateTotalCount();
      }
    } catch (e) {
      debugPrint("❌ loadMoreNotifications Hatası: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addSingleNotification(
    Map<String, dynamic> data,
    String myId,
    dynamic apiService,
    String token,
  ) async {
    final String senderId = (data['senderId'] ?? "").toString();
    if (senderId.toLowerCase() == myId.toLowerCase()) return;

    // 🚀 KRİTİK: Kullanıcı bilgilerini MinIO'dan çek
    if (senderId.isNotEmpty) {
      try {
        final String? imageUrl = await apiService.profile.getProfileImageUrl(
          senderId,
          token,
        );

        // Kullanıcı detaylarını da çek (isim için)
        final user = await apiService.profile.getUserDetail(senderId, token);

        if (user != null) {
          data['senderName'] = user.username;
        }

        if (imageUrl != null) {
          data['senderImageUrl'] = imageUrl;
        }

        debugPrint(
          "✅ Bildirim kullanıcı bilgileri yüklendi: ${data['senderName']}",
        );
      } catch (e) {
        debugPrint("❌ Bildirim kullanıcı bilgileri yüklenemedi: $e");
        data['senderName'] = data['senderName'] ?? "Bilinmeyen";
        data['senderImageUrl'] = "";
      }
    }

    bool isReq = data['isRequest'] ?? false;
    final newNotif = NotificationModel.fromMap(data, isRequest: isReq);

    if (isReq) {
      // 🚀 DUPLICATE KONTROL: Hem senderId hem de ID kontrolü
      if (!_requests.any(
        (r) =>
            r.senderId.toLowerCase() == newNotif.senderId.toLowerCase() ||
            r.id == newNotif.id,
      )) {
        _requests.insert(0, newNotif);
        debugPrint("📬 Yeni arkadaşlık isteği eklendi: ${newNotif.senderName}");
      } else {
        debugPrint("⚠️ Duplicate istek engellendi: ${newNotif.senderName}");
      }
    } else {
      // Normal bildirimler için duplicate kontrolü
      if (!_infoNotifications.any((n) => n.id == newNotif.id)) {
        _infoNotifications.insert(0, newNotif);
      }
    }
    _updateTotalCount();
  }

  void markRequestAsAccepted(String senderId) {
    final index = _requests.indexWhere((n) => n.senderId == senderId);
    if (index != -1) {
      final NotificationModel item = _requests[index];
      // İstekten çıkart, info listesine "Arkadaş oldunuz" mesajıyla ekle
      item.lastUpdate = "accepted";
      item.isRead = true;

      _requests.removeAt(index);
      _infoNotifications.insert(0, item);
      _updateTotalCount();
    }
  }

  void _updateTotalCount() {
    int unreadInfo = _infoNotifications.where((n) => !n.isRead).length;
    _pendingCount = _requests.length + unreadInfo;
    notifyListeners();
  }

  void removeNotification(String senderId) {
    _requests.removeWhere((n) => n.senderId == senderId);
    _updateTotalCount();
  }

  void resetPendingCount() {
    _pendingCount = 0;
    notifyListeners();
  }

  Future<void> markAllAsReadInDb(dynamic apiService, String token) async {
    final unreadIds = _infoNotifications
        .where((n) => !n.isRead)
        .map((n) => n.id)
        .toList();
    if (unreadIds.isNotEmpty) {
      try {
        await apiService.notification.markAsRead(unreadIds, token);
        for (var n in _infoNotifications) {
          n.isRead = true;
        }
        _updateTotalCount();
      } catch (e) {
        debugPrint(e.toString());
      }
    }
  }

  Future<void> deleteSelectedNotifications(
    List<String> ids,
    dynamic api,
    String token,
  ) async {
    if (await api.notification.deleteNotifications(ids, token)) {
      _infoNotifications.removeWhere((n) => ids.contains(n.id));
      _updateTotalCount();
    }
  }

  Future<void> clearAllNotifications(
    String userId,
    dynamic api,
    String token,
  ) async {
    if (await api.notification.deleteAllNotifications(userId, token)) {
      _infoNotifications.clear();
      _updateTotalCount();
    }
  }

  void setRequests(List<dynamic> list, int count) {
    _requests = list
        .map((e) => NotificationModel.fromMap(e, isRequest: true))
        .toList();
    _updateTotalCount();
  }

  void setNotifications(List<dynamic> list, int count) {
    _infoNotifications = list.map((e) => NotificationModel.fromMap(e)).toList();
    _infoNotifications.sort((a, b) => b.date.compareTo(a.date));
    _updateTotalCount();
  }

  @override
  void dispose() {
    _signalrSubscription?.cancel();
    super.dispose();
  }
}
