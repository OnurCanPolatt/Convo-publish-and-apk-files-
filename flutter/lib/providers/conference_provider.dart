// lib/providers/conference_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/janus/video_room_service.dart';
import '../services/signalr/signalr_service.dart';

enum ConferenceState { idle, connecting, inCall, failed }

class ConferenceProvider with ChangeNotifier {
  final SignalrService _signalRService;
  VideoRoomService? _videoRoomService;
  StreamSubscription? _signalRSubscription;

  // Durum Yönetimi
  ConferenceState _state = ConferenceState.idle;
  int? _activeRoomId;
  String? _targetId;
  bool _isGroupCall = false;

  // Gelen Arama Bilgileri
  bool _hasIncomingCall = false;
  Map<String, dynamic>? _incomingCallData;

  // Getters
  ConferenceState get state => _state;
  bool get isInCall => _state == ConferenceState.inCall;
  bool get hasIncomingCall => _hasIncomingCall;
  Map<String, dynamic>? get incomingCallData => _incomingCallData;
  VideoRoomService? get videoService => _videoRoomService;
  int? get activeRoomId => _activeRoomId;

  ConferenceProvider(this._signalRService) {
    _signalRSubscription = _signalRService.conferenceEventStream.listen((data) {
      _handleSignalREvent(data);
    });
  }

  void _handleSignalREvent(Map<String, dynamic> data) {
    final type = data['type'];

    switch (type) {
      case 'p2p_started':
      case 'group_started':
        _incomingCallData = data;
        _activeRoomId = int.tryParse(data['roomId'].toString());
        _isGroupCall = (type == 'group_started');
        _hasIncomingCall = true;
        notifyListeners();
        debugPrint("📞 Provider: Gelen arama yakalandı: Room $_activeRoomId");
        break;

      case 'ended':
        debugPrint("🔴 ConferenceEnded sinyali alındı: ${data['roomId']}");

        // ✅ YENİ: Eğer biz konferansta değilsek (rejoin durumu) direkt state temizle
        if (_state != ConferenceState.inCall) {
          debugPrint(
            "✅ Biz zaten konferansta değiliz, sadece state temizleniyor",
          );
          _activeRoomId = null;
          _targetId = null;
          _isGroupCall = false;
          _incomingCallData = null;
          _hasIncomingCall = false;
          notifyListeners();
        } else {
          // Biz konferanstaysak normal leave işlemi
          leaveConference(notifyHub: false);
        }
        break;

      case 'user_joined':
        debugPrint("👤 Provider: Kullanıcı odaya katıldı: ${data['userId']}");
        notifyListeners();
        break;
      case 'user_left':
        debugPrint(
          "👋 Provider: Kullanıcı ayrıldı sinyali alındı: ${data['userId']}",
        );

        // ✅ YENİ: Eğer biz konferansta değilsek (rejoin durumu) ve grup konferansıysa
        // Backend'e sor: Hala aktif konferans var mı?
        if (_state != ConferenceState.inCall &&
            _isGroupCall &&
            _targetId != null &&
            _activeRoomId != null) {
          debugPrint(
            "🔍 Biz konferansta değiliz, aktif konferans kontrolü yapılıyor...",
          );
          _checkIfConferenceStillActive();
        }

        notifyListeners();
        break;
    }
  }

  Future<void> _checkIfConferenceStillActive() async {
    if (_targetId == null || !_isGroupCall) {
      debugPrint("⚠️ TargetId yok veya grup konferansı değil, kontrol atlandı");
      return;
    }

    try {
      debugPrint(
        "📡 Backend'e sorgu: Grup $_targetId için aktif konferans var mı?",
      );

      final activeRoomId = await _signalRService.methods?.getActiveRoomForGroup(
        _targetId!,
      );

      if (activeRoomId == null || activeRoomId == 0) {
        // Konferans bitmiş
        debugPrint("✅ Konferans bitmiş! activeRoomId temizleniyor");
        debugPrint("   Eski _activeRoomId: $_activeRoomId → Yeni: null");

        _activeRoomId = null;
        _targetId = null;
        _isGroupCall = false;
        _incomingCallData = null;

        notifyListeners();
        debugPrint("🎉 Icon kamera moduna döndü");
      } else if (activeRoomId != _activeRoomId) {
        // Farklı bir konferans başlamış
        debugPrint(
          "🔄 Farklı konferans algılandı: $_activeRoomId → $activeRoomId",
        );
        _activeRoomId = activeRoomId;
        notifyListeners();
      } else {
        // Konferans hala aktif
        debugPrint(
          "ℹ️ Konferans hala aktif: Room $activeRoomId (rejoin mümkün)",
        );
      }
    } catch (e) {
      debugPrint("❌ Konferans aktiflik kontrolü hatası: $e");
      // Hata durumunda güvenli tarafta kal, activeRoomId'yi temizle
      _activeRoomId = null;
      notifyListeners();
    }
  }

  /// 1. ARAMA BAŞLAT
  Future<bool> startNewCall({
    required String janusUrl,
    required String myId,
    required String myName,
    required String targetId,
    required bool isGroup,
  }) async {
    print("═══════════════════════════════════════");
    print("📞 START NEW CALL BAŞLADI!");
    print("   JanusUrl: $janusUrl");
    print("   MyId: $myId");
    print("   MyName: $myName");
    print("   TargetId: $targetId");
    print("   IsGroup: $isGroup");
    print("═══════════════════════════════════════");

    try {
      print("🔄 State: connecting olarak ayarlanıyor...");
      _state = ConferenceState.connecting;
      _isGroupCall = isGroup;
      _targetId = targetId;
      notifyListeners();

      _activeRoomId = isGroup
          ? targetId.hashCode.abs()
          : (myId.hashCode + targetId.hashCode).abs();

      print("🏠 Room ID hesaplandı: $_activeRoomId");

      print("🔧 VideoRoomService oluşturuluyor...");
      _videoRoomService = VideoRoomService(janusUrl: janusUrl);

      print("📡 Janus initialize ediliyor...");
      final initialized = await _videoRoomService!.initialize().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print("❌ TIMEOUT: Janus initialize 10 saniyede tamamlanamadı!");
          return false;
        },
      );

      print("📡 Initialize sonucu: $initialized");

      if (!initialized) {
        print("❌ Janus initialize başarısız!");
        _state = ConferenceState.failed;
        notifyListeners();
        return false;
      }

      print("✅ Janus initialized, callback'ler bağlanıyor...");

      // Callback'leri bağla
      _videoRoomService!.onRemoteJoined = (id, renderer) {
        print("📺 Remote joined callback: $id");
        notifyListeners();
      };
      _videoRoomService!.onRemoteLeft = (id) {
        print("📺 Remote left callback: $id");
        notifyListeners();
      };
      _videoRoomService!.onLocalStreamReady = () {
        print("📺 Local stream ready callback");
        notifyListeners();
      };

      print(
        "🏠 createRoom çağrılıyor... RoomId: $_activeRoomId, Name: $myName",
      );

      // Oda oluştur ve katıl
      bool success = await _videoRoomService!
          .createRoom(_activeRoomId!, myName)
          .timeout(
            Duration(seconds: 15),
            onTimeout: () {
              print("❌ TIMEOUT: createRoom 15 saniyede tamamlanamadı!");
              return false;
            },
          );

      print("🏠 createRoom sonucu: $success");

      if (success) {
        _state = ConferenceState.inCall;
        print("✅ State: inCall olarak ayarlandı");

        // SignalR ile karşı tarafa bildir
        print("📡 SignalR bildirimi gönderiliyor...");
        if (isGroup) {
          await _signalRService.methods?.notifyGroupConferenceStarted(
            _activeRoomId!.toString(),
            myId,
            targetId,
          );
        } else {
          await _signalRService.methods?.notifyConferenceStarted(
            _activeRoomId!.toString(),
            myId,
            targetId,
          );
        }
        print("✅ Arama başlatıldı: Room $_activeRoomId");
      } else {
        print("❌ createRoom başarısız, state: failed");
        _state = ConferenceState.failed;
      }

      notifyListeners();
      return success;
    } catch (e, stackTrace) {
      print("❌❌❌ EXCEPTION in startNewCall ❌❌❌");
      print("Error: $e");
      print("StackTrace: $stackTrace");
      _state = ConferenceState.failed;
      notifyListeners();
      return false;
    }
  }

  /// 2. GELEN ARAMAYI KABUL ET
  Future<bool> acceptIncomingCall({
    required String janusUrl,
    required String myId,
    required String myName,
  }) async {
    if (_activeRoomId == null) return false;

    try {
      _state = ConferenceState.connecting;
      _hasIncomingCall = false;

      // ✅ DÜZELTME: targetId'yi hemen set et
      final starterId = _incomingCallData?['starterId'];
      final groupId = _incomingCallData?['groupId'];

      if (_isGroupCall && groupId != null) {
        _targetId = groupId; // ← Grup ID'si
      } else if (starterId != null) {
        _targetId = starterId; // ← Karşı tarafın ID'si
      }

      notifyListeners();

      _videoRoomService = VideoRoomService(janusUrl: janusUrl);
      final initialized = await _videoRoomService!.initialize();

      if (!initialized) {
        _state = ConferenceState.failed;
        notifyListeners();
        return false;
      }

      _videoRoomService!.onRemoteJoined = (id, renderer) {
        debugPrint("📺 Remote joined: $id");
        notifyListeners();
      };
      _videoRoomService!.onRemoteLeft = (id) {
        debugPrint("📺 Remote left: $id");
        notifyListeners();
      };
      _videoRoomService!.onLocalStreamReady = () {
        debugPrint("📺 Local stream ready");
        notifyListeners();
      };

      // Odaya katıl
      bool success = await _videoRoomService!.joinRoom(_activeRoomId!, myName);

      if (success) {
        _state = ConferenceState.inCall;

        // Hub'a katıldığımızı bildir
        if (_isGroupCall && groupId != null) {
          await _signalRService.methods?.notifyGroupUserJoined(
            _activeRoomId!.toString(),
            myId,
            groupId,
          );
        } else if (starterId != null) {
          await _signalRService.methods?.notifyUserJoined(
            _activeRoomId!.toString(),
            myId,
            starterId,
          );
        }
        debugPrint(
          "✅ Aramaya katıldı: Room $_activeRoomId, Target: $_targetId",
        );
      } else {
        _state = ConferenceState.failed;
      }

      notifyListeners();
      return success;
    } catch (e) {
      debugPrint("❌ acceptIncomingCall hatası: $e");
      _state = ConferenceState.failed;
      notifyListeners();
      return false;
    }
  }

  /// 3. ARAMAYI REDDET
  void declineCall() {
    _hasIncomingCall = false;
    _incomingCallData = null;
    _activeRoomId = null;
    notifyListeners();
    debugPrint("🚫 Arama reddedildi");
  }

  /// 4. ARAMAYI SONLANDIR
  // ConferenceProvider.dart içindeki metodu bununla değiştirin
  Future<void> leaveConference({bool notifyHub = true}) async {
    if (_state == ConferenceState.idle || _videoRoomService == null) return;

    debugPrint("🚪 Konferanstan ayrılma süreci başlatıldı...");

    // ✅ isLastParticipant'ı metodun başında tanımla
    bool isLastParticipant = false;

    try {
      // 1. ADIM: Sunucudan gerçek katılımcı sayısını al (Bekleyerek)
      int pCount = _videoRoomService!.getParticipantCount();
      isLastParticipant = pCount <= 1;

      debugPrint(
        "📊 Karar: Kişi Sayısı=$pCount | Son Kişi mi=$isLastParticipant",
      );

      // 2. ADIM: Janus Odasını Kapat veya Ayrıl
      if (isLastParticipant) {
        debugPrint("🏠 Son kullanıcıyım, oda yok ediliyor...");
        await _videoRoomService!.destroyRoom();
        // Küçük bir gecikme: Janus'un mesajı işlemesi için
        await Future.delayed(Duration(milliseconds: 500));
      } else {
        await _videoRoomService!.leaveRoom();
      }
      // 3. ADIM: SignalR Hub'a bildir
      if (notifyHub && _activeRoomId != null) {
        final roomIdStr = _activeRoomId!.toString();
        final methods = _signalRService.methods;

        if (_isGroupCall && _targetId != null) {
          if (isLastParticipant) {
            await methods?.notifyGroupConferenceEnded(roomIdStr, _targetId!);
            debugPrint("📡 SignalR: GroupConferenceEnded (Oda kapandı)");
          } else {
            final myId = methods?.currentUserId ?? "";
            await methods?.notifyGroupUserLeft(roomIdStr, myId, _targetId!);
            debugPrint("📡 SignalR: GroupUserLeft (Sadece ben çıktım)");
          }
        } else if (!_isGroupCall && _targetId != null) {
          // P2P ise her zaman bitti sinyali gönderilebilir
          await methods?.notifyConferenceEnded(_targetId!);
        }
      }
    } catch (e) {
      debugPrint("❌ leaveConference hatası: $e");
    } finally {
      await _cleanupStateAndQueryRoom(forceCleanup: isLastParticipant);
    }
  }

  Future<void> _cleanupStateAndQueryRoom({bool forceCleanup = false}) async {
    // ✅ Eğer son kişi isek (forceCleanup=true), sunucuya sormadan direkt temizle
    if (_isGroupCall && _targetId != null && !forceCleanup) {
      try {
        final activeRoomId = await _signalRService.methods
            ?.getActiveRoomForGroup(_targetId!);

        if (activeRoomId != null && activeRoomId > 0) {
          debugPrint("✅ Odadan ayrıldım ama oda hala aktif: $activeRoomId");
          _activeRoomId = activeRoomId;
        } else {
          debugPrint("✅ Odadan ayrıldım ve oda kapandı.");
          _activeRoomId = null;
        }
      } catch (e) {
        debugPrint("⚠️ Oda durumu sorgulanamadı: $e");
        _activeRoomId = null;
      }
    } else {
      // P2P veya son kişi (forceCleanup=true) ise direkt null yap
      debugPrint(
        "✅ ${forceCleanup ? 'Son kişi olarak' : 'P2P olduğu için'} roomId direkt null yapılıyor",
      );
      _activeRoomId = null;
    }

    // Diğer state'leri temizle
    _videoRoomService = null;
    _state = ConferenceState.idle;
    _targetId = null;
    _hasIncomingCall = false;
    _incomingCallData = null;
    _isGroupCall = false;

    notifyListeners();
    debugPrint("✅ Konferans state temizlendi.");
  }

  /// 5. MEVCUT GRUP ARAMASINA KATIL
  Future<bool> joinExistingGroupCall({
    required String janusUrl,
    required int roomId,
    required String myName,
    required String groupId,
  }) async {
    try {
      debugPrint("═══════════════════════════════════════");
      debugPrint("🚪 MEVCUT GRUP ARAMASINA KATILINIYOR");
      debugPrint("   Room: $roomId, Group: $groupId");
      debugPrint("═══════════════════════════════════════");

      _state = ConferenceState.connecting;
      _isGroupCall = true;
      _targetId = groupId;
      _activeRoomId = roomId;
      notifyListeners();

      _videoRoomService = VideoRoomService(janusUrl: janusUrl);
      final initialized = await _videoRoomService!.initialize();

      if (!initialized) {
        debugPrint("❌ VideoRoomService initialize başarısız!");
        _state = ConferenceState.failed;
        notifyListeners();
        return false;
      }

      // Callback'leri bağla
      _videoRoomService!.onRemoteJoined = (id, renderer) {
        debugPrint("📺 Remote joined: $id");
        notifyListeners();
      };
      _videoRoomService!.onRemoteLeft = (id) {
        debugPrint("📺 Remote left: $id");
        notifyListeners();
      };
      _videoRoomService!.onLocalStreamReady = () {
        debugPrint("📺 Local stream ready");
        notifyListeners();
      };

      // Mevcut odaya katıl
      bool success = await _videoRoomService!.joinRoom(roomId, myName);

      if (success) {
        _state = ConferenceState.inCall;

        // Hub'a katıldığımızı bildir
        await _signalRService.methods?.notifyGroupUserJoined(
          roomId.toString(),
          myName,
          groupId,
        );

        debugPrint("✅ Mevcut grup aramasına katıldı: Room $roomId");
      } else {
        _state = ConferenceState.failed;
      }

      notifyListeners();
      return success;
    } catch (e) {
      debugPrint("❌ joinExistingGroupCall hatası: $e");
      _state = ConferenceState.failed;
      notifyListeners();
      return false;
    }
  }

  // Media Controls
  Future<void> toggleMic(bool enabled) async {
    await _videoRoomService?.toggleAudio(enabled);
  }

  Future<void> toggleCamera(bool enabled) async {
    await _videoRoomService?.toggleVideo(enabled);
  }

  Future<void> switchCamera() async {
    await _videoRoomService?.switchCamera();
  }

  void setIncomingCallFromNotification({
    required String roomId,
    required String starterId,
    String? groupId,
    required bool isGroup,
  }) {
    _incomingCallData = {
      'roomId': roomId,
      'starterId': starterId,
      'groupId': groupId,
      'isGroup': isGroup,
    };
    _activeRoomId = int.tryParse(roomId);
    _isGroupCall = isGroup;
    _hasIncomingCall = true;
    notifyListeners();
    debugPrint("✅ FCM Notification'dan call data set edildi: RoomId=$roomId");
  }

  /// ✅ YENİ: Aktif room'u temizle (UI senkronizasyonu için)
  void clearActiveRoom() {
    debugPrint("🧹 clearActiveRoom çağrıldı - $_activeRoomId → null");
    _activeRoomId = null;
    _targetId = null;
    _isGroupCall = false;
    notifyListeners();
  }

  /// ✅ YENİ: Backend'den gelen aktif room'u set et
  void setActiveRoomFromBackend(int roomId, String groupId) {
    debugPrint(
      "📞 setActiveRoomFromBackend çağrıldı - Room: $roomId, Group: $groupId",
    );
    _activeRoomId = roomId;
    _targetId = groupId;
    _isGroupCall = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _signalRSubscription?.cancel();
    _videoRoomService?.dispose();
    super.dispose();
  }
}
