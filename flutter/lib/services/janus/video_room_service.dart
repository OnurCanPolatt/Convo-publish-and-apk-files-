// lib/services/janus/video_room_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/janus_client.dart';

class VideoRoomService {
  final String janusUrl;

  JanusClient? _client;
  JanusSession? _session;
  JanusVideoRoomPlugin? _videoRoom;

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  Map<int, RTCVideoRenderer> remoteRenderers = {};
  int? currentRoom;
  int? _myFeedId;
  bool _isPublishing = false;
  int get participantCount => remoteRenderers.length + 1; //

  // Stream subscriptions
  StreamSubscription? _typedMessagesSubscription;
  StreamSubscription? _rawMessagesSubscription; // ← EKLE
  StreamSubscription? _remoteStreamSubscription;
  final Map<int, StreamSubscription<MediaStream>>
  _subscriberStreamSubscriptions = {};

  final Map<int, JanusVideoRoomPlugin> _subscriberHandles = {};

  // Event callbacks
  Function(int publisherId, RTCVideoRenderer renderer)? onRemoteJoined;
  Function(int publisherId)? onRemoteLeft;
  Function()? onLocalStreamReady;

  VideoRoomService({required this.janusUrl});

  Future<bool> initialize() async {
    print('═══════════════════════════════════════');
    print('📡 JANUS INITIALIZE BAŞLADI');
    print('═══════════════════════════════════════');

    try {
      print('🎥 LocalRenderer initialize ediliyor...');
      await localRenderer.initialize();
      print('✅ LocalRenderer initialized');

      final String safeUrl = janusUrl.toString().trim();
      print('🌐 Janus URL: $safeUrl');

      print('🔌 JanusClient oluşturuluyor...');
      _client = JanusClient(
        transport: WebSocketJanusTransport(url: safeUrl),
        iceServers: [
          RTCIceServer(urls: "stun:stun.l.google.com:19302"),
          RTCIceServer(urls: "stun:stun1.l.google.com:19302"),
          RTCIceServer(urls: "stun:convoapp.app:3478"),
        ],
        isUnifiedPlan: true,
      );
      print('✅ JanusClient oluşturuldu');

      print('✅ JANUS INITIALIZE BAŞARILI');
      return true;
    } catch (e, stackTrace) {
      print('❌❌❌ JANUS INIT EXCEPTION ❌❌❌');
      print('Error: $e');
      print('StackTrace: $stackTrace');
      return false;
    }
  }

  Future<bool> createRoom(int roomId, String displayName) async {
    try {
      print('═══════════════════════════════════════');
      print('🏠 CREATE ROOM BAŞLADI');
      print('   RoomId: $roomId');
      print('   DisplayName: $displayName');
      print('═══════════════════════════════════════');

      _session = await _client!.createSession();
      debugPrint('✅ Session oluşturuldu');

      _videoRoom = await _session!.attach<JanusVideoRoomPlugin>();
      debugPrint('✅ VideoRoom plugin attach edildi');

      currentRoom = roomId;

      // Oda oluştur
      try {
        await _videoRoom!.send(
          data: {
            "request": "create",
            "room": roomId,
            "publishers": 10,
            "permanent": false,
            "videocodec": "vp8",
            "audiocodec": "opus",
          },
        );
        debugPrint('✅ Oda oluşturuldu: $roomId');
      } catch (e) {
        debugPrint('⚠️ Oda zaten var: $e');
      }

      return await _joinAsPublisher(roomId, displayName);
    } catch (e) {
      debugPrint('❌ CREATE ROOM HATASI: $e');
      return false;
    }
  }

  Future<bool> joinRoom(int roomId, String displayName) async {
    try {
      debugPrint('═══════════════════════════════════════');
      debugPrint('🚪 ODAYA KATILINIYOR: $roomId');
      debugPrint('═══════════════════════════════════════');

      if (_session == null) {
        _session = await _client!.createSession();
        debugPrint('✅ Session oluşturuldu');
      }

      if (_videoRoom == null) {
        _videoRoom = await _session!.attach<JanusVideoRoomPlugin>();
        debugPrint('✅ VideoRoom plugin attach edildi');
      }

      currentRoom = roomId;
      return await _joinAsPublisher(roomId, displayName);
    } catch (e) {
      debugPrint('❌ JOIN ROOM HATASI: $e');
      return false;
    }
  }

  Future<bool> _joinAsPublisher(int roomId, String displayName) async {
    try {
      final plugin = _videoRoom!;

      // ═══════════════════════════════════════════════════════════
      // 1. EVENT LISTENER'LARI KUR
      // ═══════════════════════════════════════════════════════════
      debugPrint('📡 Event listener\'lar kuruluyor...');

      // TypedMessages dinle
      _typedMessagesSubscription?.cancel();
      _typedMessagesSubscription = plugin.typedMessages?.listen((message) {
        _onTypedMessage(message);
      });

      // ✅ RAW Messages dinle (leaving/unpublished için KRİTİK!)
      _rawMessagesSubscription?.cancel();
      _rawMessagesSubscription = plugin.messages?.listen((msg) {
        _onRawMessage(msg);
      });

      // RemoteStream dinle (publisher için)
      _remoteStreamSubscription?.cancel();
      _remoteStreamSubscription = plugin.remoteStream?.listen((stream) {
        debugPrint('📺 PUBLISHER REMOTE STREAM GELDİ');
      });

      // ═══════════════════════════════════════════════════════════
      // 2. PUBLISHER OLARAK KATIL
      // ═══════════════════════════════════════════════════════════
      debugPrint('🎯 Publisher olarak katılınıyor...');
      await plugin.joinPublisher(roomId, displayName: displayName);
      debugPrint('✅ joinPublisher çağrıldı');

      return true;
    } catch (e) {
      debugPrint('❌ JOIN AS PUBLISHER HATASI: $e');
      return false;
    }
  }

  void _onRawMessage(dynamic msg) {
    try {
      if (msg == null) return;

      debugPrint('📨 RAW MESSAGE: ${msg.toString()}');

      // EventMessage nesnesinden event objesini al
      Map<String, dynamic>? eventMap;

      if (msg is Map) {
        eventMap = Map<String, dynamic>.from(msg);
      } else {
        // EventMessage objesi ise toString'den parse et veya reflection kullan
        // Ama genelde msg.event şeklinde erişilebilir
        try {
          eventMap = (msg as dynamic).event as Map<String, dynamic>?;
        } catch (e) {
          debugPrint('⚠️ EventMessage parse edilemedi: $e');
          return;
        }
      }

      if (eventMap == null) return;

      // plugindata.data'ya eriş (nested yapı)
      final plugindata = eventMap['plugindata'] as Map<String, dynamic>?;
      if (plugindata == null) return;

      final data = plugindata['data'] as Map<String, dynamic>?;
      if (data == null) return;

      // ✅ DOĞRU: Artık doğru seviyedeyiz - data içinde leaving/unpublished var

      // Leaving kontrolü
      if (data['leaving'] != null) {
        final leavingId = data['leaving'] is int
            ? data['leaving'] as int
            : int.tryParse(data['leaving'].toString());

        if (leavingId != null && leavingId != _myFeedId) {
          debugPrint(
            '🚪🚪🚪 RAW MESSAGE: KULLANICI AYRILIYOR: $leavingId 🚪🚪🚪',
          );
          _removeRemoteRenderer(leavingId);
        }
        return;
      }

      // Unpublished kontrolü
      if (data['unpublished'] != null) {
        final unpublishedId = data['unpublished'] is int
            ? data['unpublished'] as int
            : int.tryParse(data['unpublished'].toString());

        if (unpublishedId != null && unpublishedId != _myFeedId) {
          debugPrint(
            '📹 RAW MESSAGE: KULLANICI UNPUBLISH OLDU: $unpublishedId',
          );
          _removeRemoteRenderer(unpublishedId);
        }
        return;
      }
    } catch (e) {
      debugPrint('❌ _onRawMessage error: $e');
    }
  }

  void _onTypedMessage(dynamic message) {
    try {
      debugPrint('🔔 ANALİZ EDİLEN MESAJ: ${message.toString()}');

      // 1. JSEP (Answer) Paketini Yakala - EN KRİTİK KISIM
      if (message.jsep != null) {
        debugPrint('📩 Janus JSEP (Answer) gönderdi, işleniyor...');
        _videoRoom?.handleRemoteJsep(
          message.jsep,
        ); // Bu satır bağlantıyı kurar!
      }

      // 2. Veriyi sarmallardan ayıkla
      final dynamic eventData = (message is JanusEvent)
          ? message.plugindata?.data
          : message?.event?.plugindata?.data;

      if (eventData == null) return;
      String msgStr = message.toString();

      // 3. ODAYA KATILDIK MI? (Kamerayı açan kısım)
      if (msgStr.contains('videoroom: joined')) {
        debugPrint('✅ Odaya Giriş Onaylandı!');

        // Feed ID ve Publisher listesini nesne üzerinden güvenle al
        if (eventData is VideoRoomJoinedEvent) {
          _myFeedId = eventData.id;
          if (eventData.publishers != null) {
            for (var pub in eventData.publishers!) {
              if (pub.id != null && pub.id != _myFeedId) {
                debugPrint(
                  '👥 Mevcut kullanıcı bulundu, abone olunuyor: ${pub.id}',
                );
                _subscribeTo(pub.id!);
              }
            }
          }
        }

        _startPublishing();
        return;
      }

      // 4. YENİ BİRİ GELDİ Mİ? (Siz içerideyken başkası girerse)
      if (eventData is VideoRoomNewPublisherEvent) {
        if (eventData.publishers != null) {
          for (var pub in eventData.publishers!) {
            if (pub.id != null && !remoteRenderers.containsKey(pub.id)) {
              debugPrint('👤 YENİ YAYINCI: ${pub.id}, ABONE OLUNUYOR...');
              _subscribeTo(pub.id!);
            }
          }
        }
        return; // ← EKLE
      }
    } catch (e) {
      debugPrint('❌ _onTypedMessage Hata: $e');
    }
  }

  void _handleJoinedEvent(VideoRoomJoinedEvent event) {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║     JOINED EVENT İŞLENİYOR           ║');
    debugPrint('╚═══════════════════════════════════════╝');

    // Kendi Feed ID'mizi al
    _myFeedId = event.id;
    debugPrint('🆔 Benim Feed ID: $_myFeedId');

    // Mevcut publisher'ları kontrol et
    final publishers = event.publishers;
    debugPrint('👥 Mevcut publisher listesi: $publishers');

    if (publishers != null && publishers.isNotEmpty) {
      debugPrint('👥 ${publishers.length} mevcut publisher var!');
      for (var pub in publishers) {
        debugPrint('  👤 Publisher: id=${pub.id}, display=${pub.display}');
        if (pub.id != null && pub.id != _myFeedId) {
          debugPrint('  🔔 ABONE OLUNACAK: ${pub.id}');
          _subscribeTo(pub.id!);
        }
      }
    } else {
      debugPrint('ℹ️ Odada başka kimse yok, ilk katılan biziz.');
    }

    // Yayını başlat
    _startPublishing();
  }

  void _handleNewPublisherEvent(VideoRoomNewPublisherEvent event) {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║   NEW PUBLISHER EVENT İŞLENİYOR      ║');
    debugPrint('╚═══════════════════════════════════════╝');

    final publishers = event.publishers;
    debugPrint('👥 Yeni publisher listesi: $publishers');

    if (publishers != null) {
      for (var pub in publishers) {
        debugPrint('  👤 Yeni Publisher: id=${pub.id}, display=${pub.display}');
        if (pub.id != null &&
            pub.id != _myFeedId &&
            !remoteRenderers.containsKey(pub.id)) {
          debugPrint('  🔔 YENİ KULLANICI - ABONE OLUNACAK: ${pub.id}');
          _subscribeTo(pub.id!);
        }
      }
    }
  }

  void _handleLeavingEvent(VideoRoomLeavingEvent event) {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║     LEAVING EVENT İŞLENİYOR          ║');
    debugPrint('╚═══════════════════════════════════════╝');

    final leavingId = event.leaving;
    debugPrint('👋 Ayrılan kullanıcı ID: $leavingId');

    if (leavingId != null) {
      _removeRemoteRenderer(leavingId);
    }
  }

  void _handleUnpublishedEvent(VideoRoomUnPublishedEvent event) {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║   UNPUBLISHED EVENT İŞLENİYOR        ║');
    debugPrint('╚═══════════════════════════════════════╝');

    final unpublishedId = event.unpublished;
    debugPrint('📴 Yayını durduran ID: $unpublishedId');

    if (unpublishedId != null) {
      _removeRemoteRenderer(unpublishedId);
    }
  }

  // VideoRoomService.dart içinde bul ve değiştir
  // VideoRoomService.dart içinde _startPublishing metodu
  Future<void> _startPublishing() async {
    if (_isPublishing) return;
    try {
      debugPrint('📹 Kamera başlatılıyor...');
      final plugin = _videoRoom;
      if (plugin == null) return;

      _isPublishing = true;

      // 1. Önce Medya Cihazlarını Başlat
      final stream = await plugin.initializeMediaDevices(
        mediaConstraints: {
          "audio": true, // Buranın true olduğundan emin ol
          "video": {
            "width": {"ideal": 480},
            "height": {"ideal": 640},
            "frameRate": {"ideal": 20},
          },
        },
      );

      if (stream != null) {
        localRenderer.srcObject = stream;

        // ✅ KRİTİK ADIM 1: Track'leri tek tek elle aktif et
        for (var track in stream.getTracks()) {
          track.enabled = true;
          debugPrint('✅ Track aktif edildi: ${track.kind}');
        }

        // ✅ KRİTİK ADIM 2: Publish ederken ses ve görüntüyü açık istediğini belirt
        // Janus'un bazı sürümlerinde publishMedia parametre alabilir, almasa bile configure ile zorlayacağız
        await plugin.publishMedia(bitrate: 512000);

        // ✅ KRİTİK ADIM 3: Publish sonrası beklemeden konfigürasyonu zorla gönder
        // P2P'de bu genelde otomatik hallolur ama grup odalarında (VideoRoom) manuel göndermek daha sağlıklıdır
        await plugin.send(
          data: {"request": "configure", "audio": true, "video": true},
        );

        // UI'daki butonları da senkronize et (isMicOpen ve isCamOpen değişkenlerini true yap)
        debugPrint('🚀 Grup yayını SES ve GÖRÜNTÜ AÇIK olarak başlatıldı.');

        if (onLocalStreamReady != null) {
          onLocalStreamReady!();
        }
      }
    } catch (e) {
      _isPublishing = false;
      debugPrint('❌ KAMERA HATASI: $e');
    }
  }

  Future<void> _subscribeTo(int publisherId) async {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║   SUBSCRIBER OLUŞTURULUYOR: $publisherId');
    debugPrint('╚═══════════════════════════════════════╝');

    try {
      final session = _session;
      if (session == null || currentRoom == null) {
        debugPrint('❌ Session veya oda bilgisi eksik!');
        return;
      }

      if (remoteRenderers.containsKey(publisherId)) {
        debugPrint('⚠️ Zaten abone: $publisherId');
        return;
      }

      // 1. Yeni plugin handle (Subscriber) oluştur
      debugPrint('🔌 Yeni VideoRoom handle (Subscriber) oluşturuluyor...');
      final subscriberHandle = await session.attach<JanusVideoRoomPlugin>();
      _subscriberHandles[publisherId] = subscriberHandle;

      // 2. Renderer (Görüntü Kutusu) oluştur ve başlat
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      remoteRenderers[publisherId] = renderer;

      // 3. JSEP (Offer) ve Plugin Mesajlarını Dinleyici
      subscriberHandle.typedMessages?.listen((message) async {
        // ✅ DÜZELTME: plugindata hatası burada giderildi
        // TypedEvent içindeki asıl event'e erişmek için '.event' kullanılır
        final dynamic eventData = message.event?.plugindata?.data;

        if (eventData != null) {
          String msgStr = message.toString().toLowerCase();

          // Janus yayıncı kamerasını kapattığında 'video: false' veya 'substream: null' gönderir
          if (msgStr.contains('video: false') ||
              msgStr.contains('substream: null')) {
            debugPrint(
              '📢 Janus Sinyali Yakalandı: SİYAH EKRANA GEÇİLİYOR -> $publisherId',
            );

            // Renderer'ı tamamen sıfırla
            renderer.srcObject = null;

            // Callback'i tetikle
            onRemoteJoined?.call(publisherId, renderer);

            // UI'ı anında haberdar et
            if (onLocalStreamReady != null) onLocalStreamReady!();
          }
          // Kamera tekrar açıldığında
          else if (msgStr.contains('video: true') ||
              msgStr.contains('substream: 0') ||
              msgStr.contains('substream: 1')) {
            debugPrint(
              '📢 Janus Sinyali: Kullanıcı kamerasını açtı! -> $publisherId',
            );
          }
        }

        if (message.jsep != null) {
          debugPrint(
            '📩 Subscriber için JSEP (Offer) geldi, Answer hazırlanıyor...',
          );
          await subscriberHandle.handleRemoteJsep(message.jsep!);
          var answer = await subscriberHandle.createAnswer();

          await subscriberHandle.send(
            data: {"request": "start", "room": currentRoom},
            jsep: answer,
          );
          debugPrint('✅ Subscriber Answer gönderildi! Bağlantı tamam.');
        }
      });

      // 4. Remote Stream (Gelen Görüntü/Ses) Dinle
      // _subscribeTo metodundaki "subscription" kısmını bu blokla TAMAMEN değiştir:
      final subscription = subscriberHandle.remoteStream?.listen((stream) {
        debugPrint('🎉🎉🎉 REMOTE STREAM ALINDI: $publisherId 🎉🎉🎉');
        renderer.srcObject = stream;

        for (var track in stream.getTracks()) {
          if (track.kind == 'video') {
            int lastFrameCount = -1;
            int freezeSeconds = 0;

            // ✅ GERÇEK WATCHDOG: Kare sayısını takip eder
            Timer.periodic(const Duration(seconds: 1), (timer) async {
              // Eğer kullanıcı odadan çıktıysa timer'ı durdur
              if (!_subscriberHandles.containsKey(publisherId)) {
                timer.cancel();
                return;
              }

              // WebRTC istatistiklerinden alınan kare sayısını çek
              var stats = await subscriberHandle.webRTCHandle?.peerConnection
                  ?.getStats();
              int currentFrames = 0;

              if (stats != null) {
                for (var report in stats) {
                  if (report.type == 'inbound-rtp' &&
                      report.values['kind'] == 'video') {
                    currentFrames = report.values['framesReceived'] ?? 0;
                  }
                }
              }

              // KONTROL MANTIĞI (Web'deki currentTime kontrolü ile aynı)
              if (currentFrames == lastFrameCount && lastFrameCount != -1) {
                freezeSeconds++;
                if (freezeSeconds >= 2) {
                  // 2 saniye boyunca yeni kare gelmediyse DONMUŞTUR
                  if (renderer.srcObject != null) {
                    debugPrint(
                      '❄️ GÖRÜNTÜ DONMASI TESPİT EDİLDİ (FPS Watchdog): $publisherId',
                    );
                    renderer.srcObject = null; // UI'daki siyah maskeyi tetikler
                    onRemoteJoined?.call(publisherId, renderer);
                  }
                }
              } else {
                freezeSeconds = 0; // Görüntü akıyor
                if (renderer.srcObject == null &&
                    currentFrames > lastFrameCount) {
                  debugPrint('▶️ GÖRÜNTÜ GERİ GELDİ: $publisherId');
                  renderer.srcObject = stream; // Yayını geri bağla
                  onRemoteJoined?.call(publisherId, renderer);
                }
              }
              lastFrameCount = currentFrames;
            });
          }

          // Klasik Mute/Unmute sinyallerini de yedek olarak tutabilirsin
          track.onMute = () {
            if (track.kind == 'video' && renderer.srcObject != null) {
              renderer.srcObject = null;
              onRemoteJoined?.call(publisherId, renderer);
            }
          };
        }

        onRemoteJoined?.call(publisherId, renderer);
      });

      if (subscription != null) {
        _subscriberStreamSubscriptions[publisherId] = subscription;
      }

      // 5. Janus'a abone olma isteğini gönder
      debugPrint(
        '🔗 joinSubscriber çağrılıyor... Room: $currentRoom, Feed: $publisherId',
      );
      await subscriberHandle.joinSubscriber(currentRoom!, feedId: publisherId);

      // Bağlantı Durumu İzleme
      subscriberHandle.webRTCHandle?.peerConnection?.onIceConnectionState =
          (state) {
            debugPrint('🧊 SUBSCRIBER ICE State ($publisherId): $state');
          };
    } catch (e, stack) {
      debugPrint('❌ SUBSCRIBE HATASI ($publisherId): $e');
      _removeRemoteRenderer(publisherId);
    }
  }

  void _removeRemoteRenderer(int publisherId) {
    debugPrint('🗑️ Renderer siliniyor: $publisherId');

    _subscriberStreamSubscriptions[publisherId]?.cancel();
    _subscriberStreamSubscriptions.remove(publisherId);

    final handle = _subscriberHandles.remove(publisherId);
    try {
      handle?.dispose();
    } catch (e) {
      debugPrint('⚠️ Handle dispose hatası: $e');
    }

    final renderer = remoteRenderers.remove(publisherId);
    if (renderer != null) {
      renderer.srcObject = null;
      try {
        renderer.dispose();
      } catch (e) {
        debugPrint('⚠️ Renderer dispose hatası: $e');
      }
      debugPrint('✅ Renderer silindi: $publisherId');
      onRemoteLeft?.call(publisherId);
    }
  }

  Future<void> destroyRoom() async {
    if (currentRoom == null || _videoRoom == null) return;

    try {
      await _videoRoom!.send(data: {"request": "destroy", "room": currentRoom});
      debugPrint("🏠 Janus Odası Kapatıldı: $currentRoom");
    } catch (e) {
      debugPrint("❌ Oda kapatılırken hata: $e");
    }
  }
  // ═══════════════════════════════════════════════════════════
  // MEDIA CONTROLS
  // ═══════════════════════════════════════════════════════════

  Future<void> toggleAudio(bool isEnabled) async {
    try {
      // ✅ FİX: Önce track'i değiştir, sonra Janus'a bildir
      localRenderer.srcObject?.getAudioTracks().forEach(
        (t) => t.enabled = isEnabled,
      );

      // Sonra Janus'a configure mesajı gönder
      await _videoRoom?.send(
        data: {"request": "configure", "audio": isEnabled},
      );

      debugPrint('🎤 Mikrofon: ${isEnabled ? "AÇIK" : "KAPALI"}');
    } catch (e) {
      debugPrint('❌ toggleAudio hatası: $e');
    }
  }

  Future<void> toggleVideo(bool isEnabled) async {
    try {
      final videoTracks = localRenderer.srcObject?.getVideoTracks();

      if (videoTracks == null || videoTracks.isEmpty) {
        debugPrint('⚠️ Video track bulunamadı, işlem yapılamıyor.');
        return;
      }

      // 1. Yerel Track durumunu güncelle
      for (var track in videoTracks) {
        track.enabled = isEnabled;
      }

      // 2. Kendi ekranında donmayı önle: (yorum satırı...)

      // 3. Janus'a yapılandırma mesajı gönder
      await _videoRoom?.send(
        data: {"request": "configure", "video": isEnabled},
      );

      // 4. UI'ı bilgilendir
      if (onLocalStreamReady != null) {
        onLocalStreamReady!();
      }

      debugPrint(
        '📹 Kamera durumu Janus ve Yerel olarak güncellendi: ${isEnabled ? "AÇIK" : "KAPALI"}',
      );
    } catch (e) {
      debugPrint('❌ toggleVideo hatası: $e');
    }
  }

  bool isFrontCamera = true;
  Future<void> switchCamera() async {
    try {
      final tracks = _videoRoom?.webRTCHandle?.localStream?.getVideoTracks();
      if (tracks != null && tracks.isNotEmpty) {
        // flutter_webrtc Helper sınıfını kullanarak kamerayı değiştir
        await Helper.switchCamera(tracks[0]);

        // ✅ DURUMU GÜNCELLE: Ön ise arka, arka ise ön yap
        isFrontCamera = !isFrontCamera;

        debugPrint('✅ Kamera değiştirildi. Ön kamera mı: $isFrontCamera');
      }
    } catch (e) {
      debugPrint('❌ switchCamera hatası: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════

  Future<void> leaveRoom() async {
    debugPrint('');
    debugPrint('╔═══════════════════════════════════════╗');
    debugPrint('║       ODADAN AYRILIYOR               ║');
    debugPrint('╚═══════════════════════════════════════╝');

    try {
      _typedMessagesSubscription?.cancel();
      _typedMessagesSubscription = null;

      _rawMessagesSubscription?.cancel(); // ← EKLE
      _rawMessagesSubscription = null;

      _remoteStreamSubscription?.cancel();
      _remoteStreamSubscription = null;

      for (var sub in _subscriberStreamSubscriptions.values) {
        sub.cancel();
      }
      _subscriberStreamSubscriptions.clear();

      for (var handle in _subscriberHandles.values) {
        try {
          handle.dispose();
        } catch (e) {}
      }
      _subscriberHandles.clear();

      if (_videoRoom != null) {
        try {
          _videoRoom!.hangup();
        } catch (e) {}
        try {
          _videoRoom!.dispose();
        } catch (e) {}
      }

      final localStream = localRenderer.srcObject;
      if (localStream != null) {
        for (var track in localStream.getTracks()) {
          track.stop();
        }
        localRenderer.srcObject = null;
      }

      for (var renderer in remoteRenderers.values) {
        renderer.srcObject = null;
        try {
          renderer.dispose();
        } catch (e) {}
      }
      remoteRenderers.clear();

      try {
        _session?.dispose();
      } catch (e) {}

      _videoRoom = null;
      _session = null;
      currentRoom = null;
      _myFeedId = null;
      _isPublishing = false;

      debugPrint('✅ ODADAN AYRILDI');
    } catch (e) {
      debugPrint('❌ leaveRoom hatası: $e');
    }
  }

  int getParticipantCount() {
    // remoteRenderers: bizim dışımızdaki diğer katılımcılar
    final remoteCount = remoteRenderers.length;

    // _isPublishing: bizim feed'imiz aktif mi?
    final selfCount = _isPublishing ? 1 : 0;

    final totalCount = remoteCount + selfCount;

    debugPrint(
      "📊 Katılımcı Sayısı: $totalCount (Ben: $selfCount, Diğerleri: $remoteCount)",
    );

    return totalCount;
  }

  Future<void> dispose() async {
    await leaveRoom();
    try {
      await localRenderer.dispose();
    } catch (e) {}
  }
}
