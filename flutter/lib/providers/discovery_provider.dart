import 'dart:async';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/signalr/signalr_service.dart';
import 'notification_provider.dart';

class DiscoveryProvider with ChangeNotifier {
  final ApiService _apiService;

  // 🚀 Arka plan dinleyicisi için subscription değişkeni
  StreamSubscription? _signalrSubscription;

  DiscoveryProvider(this._apiService);

  List<User> _users = [];
  int _currentPage = 1;
  final int _pageSize = 4;
  bool _isLoading = false;
  bool _hasMore = true;
  String _currentSearchTerm = "";

  List<User> get users => _users;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  void listenToSignalR(SignalrService signalr, String token, String userId) {
    if (_signalrSubscription != null) return;

    _signalrSubscription = signalr.friendEventStream.listen((data) async {
      final String? type = data['type'];
      final String? eventUserId = data['userId']?.toString();
      final int? newStatus = data['newStatus'];

      // 🚀 BİLGİ GÜNCELLEME (İsim/Resim) DURUMU
      if (type == 'InfoUpdated' || type == 'ReceiveUserInfoUpdated') {
        final int index = _users.indexWhere(
          (u) => u.id.toLowerCase() == eventUserId?.toLowerCase(),
        );

        if (index != -1 && eventUserId != null) {
          // ✅ HATANIN ÇÖZÜMÜ: Önce mevcut statüyü değişkene alıyoruz
          int currentFriendshipStatus = _users[index].status;

          final freshUser = await _apiService.profile.getUserDetail(
            eventUserId,
            token,
          );

          if (freshUser != null) {
            // 🛡️ Statü ve Resim Sync
            freshUser.status = currentFriendshipStatus;

            // 📸 Timestamp ekle (URL sonundaki eski t parametrelerini temizleyerek)
            if (freshUser.profileImageUrl != null &&
                freshUser.profileImageUrl!.isNotEmpty) {
              String baseUrl = freshUser.profileImageUrl!.split('?').first;
              freshUser.profileImageUrl =
                  "$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}";
            }

            // 🔥 LİSTEYİ YENİLE VE TETİKLE (Immutable Update)
            final List<User> newList = List.from(_users);
            newList[index] = freshUser;
            _users = newList; // Referans değiştiği için Consumer tetiklenir

            notifyListeners();
            debugPrint("📡 Discovery: ${freshUser.username} güncellendi.");
          }
        }
      }
      // 🤝 ARKADAŞLIK DURUMU DEĞİŞİMİ
      else if (type == 'FriendListChanged' &&
          eventUserId != null &&
          newStatus != null) {
        final index = _users.indexWhere(
          (u) => u.id.toLowerCase() == eventUserId.toLowerCase(),
        );
        if (index != -1) {
          final List<User> newList = List.from(_users);
          newList[index].status = newStatus;
          _users = newList;
          notifyListeners();
        }
      }
    });
  }

  Future<void> loadNextPage(String token, String currentUserId) async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.discovery.getDiscoveryUsers(
        _currentPage,
        _pageSize,
        token,
        searchTerm: _currentSearchTerm,
      );

      if (response.users.isNotEmpty) {
        _users.addAll(response.users);
        _currentPage++;
        if (response.users.length < _pageSize ||
            _users.length >= response.totalCount) {
          _hasMore = false;
        }
      } else {
        _hasMore = false;
      }
    } catch (e) {
      _hasMore = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSearch(
    String query,
    String token,
    String currentUserId,
  ) async {
    if (_currentSearchTerm == query && _users.isNotEmpty) return;
    _currentSearchTerm = query;
    _users = [];
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();
    await loadNextPage(token, currentUserId);
  }

  Future<void> refreshList(
    String token,
    String currentUserId, {
    bool clearSearch = true,
  }) async {
    if (_isLoading) return;

    if (clearSearch) {
      _currentSearchTerm = "";
    }

    _currentPage = 1;
    _hasMore = true;
    _users = [];
    await loadNextPage(token, currentUserId);
  }

  Future<void> handleFriendAction(
    String targetUserId,
    String token,
    String actionType,
    String currentUserId,
    NotificationProvider notificationProvider,
  ) async {
    debugPrint("🛠️ handleFriendAction: $actionType -> $targetUserId");
    bool success = false;

    if (actionType == "send") {
      success = await _apiService.request.sendFriendRequest(
        targetUserId,
        token,
      );
    } else if (actionType == "accept") {
      success = await _apiService.request.acceptFriendRequest(
        targetUserId,
        token,
      );
    } else if (actionType == "reject") {
      success = await _apiService.request.rejectFriendRequest(
        targetUserId,
        token,
      );
    } else if (actionType == "remove_request") {
      success = await _apiService.request.removeOrRejectRequest(
        targetUserId,
        token,
      );
    } else if (actionType == "remove_friend") {
      success = await _apiService.request.removeFriend(targetUserId, token);
    }

    if (success) {
      notificationProvider.removeNotification(targetUserId);
      _updateUserStatusLocal(targetUserId, actionType);
      debugPrint("✅ Durum yerel olarak güncellendi.");
    }
  }

  void _updateUserStatusLocal(String userId, String actionType) {
    final index = _users.indexWhere((u) => u.id == userId);
    if (index != -1) {
      int newStatus = 0;
      switch (actionType) {
        case "send":
          newStatus = 1;
          break;
        case "accept":
          newStatus = 3;
          break;
        case "reject":
        case "remove_request":
        case "remove_friend":
          newStatus = 0;
          break;
      }
      _users[index].status = newStatus;
      notifyListeners();
    }
  }

  Future<void> fetchAndRefreshUser(String userId, String token) async {
    try {
      // 1. Kullanıcının temel bilgilerini çek (getUserDetail)
      final freshUser = await _apiService.profile.getUserDetail(userId, token);

      if (freshUser != null) {
        final index = _users.indexWhere((u) => u.id == userId);
        if (index != -1) {
          // 2. MinIO'dan profil fotoğrafını ayrıca çek
          final String? imageUrl = await _apiService.profile.getProfileImageUrl(
            userId,
            token,
          );

          if (imageUrl != null) {
            // Cache kırmak için timestamp ekle
            freshUser.profileImageUrl =
                "${imageUrl.split('?').first}?t=${DateTime.now().millisecondsSinceEpoch}";
            debugPrint(
              "📸 DiscoveryProvider: Fotoğraf MinIO'dan çekildi - $imageUrl",
            );
          } else {
            freshUser.profileImageUrl = null;
            debugPrint("⚠️ DiscoveryProvider: Kullanıcının fotoğrafı yok");
          }

          _users[index] = freshUser;
          _users = List.from(_users); // Referans değiştir
          notifyListeners();
          debugPrint(
            "✅ DiscoveryProvider: ${freshUser.username} bilgileri güncellendi",
          );
        }
      }
    } catch (e) {
      debugPrint("❌ DB Refresh Hatası: $e");
    }
  }

  @override
  void dispose() {
    _signalrSubscription?.cancel(); // Provider yok edilirse aboneliği bitir
    super.dispose();
  }
}
