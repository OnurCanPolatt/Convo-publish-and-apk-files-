import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/screens/video_call_screen.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';

// Modeller ve Servisler
import 'package:my_first_flutterapp/models/chat_list_item.dart';
import 'package:my_first_flutterapp/services/signalr/signalr_service.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';
import 'package:my_first_flutterapp/providers/chat_provider.dart';
import 'package:my_first_flutterapp/services/file_upload_service.dart';
import 'package:my_first_flutterapp/services/download_service.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/players/video_player_page.dart';
import 'package:my_first_flutterapp/models/chat_message.dart';
import '../providers/conference_provider.dart';
import '../services/profile_service.dart';
import '../widgets/user_detail_modal.dart';
import 'group_info_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupItem groupModel;
  final SignalrService signalRService;

  const GroupChatScreen({
    super.key,
    required this.groupModel,
    required this.signalRService,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  late ProfileService _profileService;

  // ✅ YENİ: SignalR event subscription
  StreamSubscription? _groupUpdateSubscription;

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _currentTransferFileName;
  String? _currentlyPlayingUrl;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;

  String? _pendingFileMessageId;
  DateTime? _pendingFileMessageTime;

  String janus = "ws://convoapp.app:8188";
  StreamSubscription? _appResumedSubscription;
  @override
  void initState() {
    super.initState();

    _profileService = ProfileService(Dio());
    _setupAudioListeners();
    _setupSignalRListener();
    _loadInitialData();

    // 1. Arka plandan her dönüşte tazele
    _appResumedSubscription = widget.signalRService.appResumedStream.listen((
      _,
    ) {
      if (mounted) _refreshMessagesFromServer();
    });

    // 2. Sayfa İLK AÇILDIĞINDA (render sonrası) tazele
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndAcceptIncomingCall(); // ← ÖNCE BU BİTSİN
      _refreshMessagesFromServer();
      _syncConferenceState(); // ← SONRA BU ÇALIŞSIN
    });
  }

  Future<void> _syncConferenceState() async {
    try {
      final conferenceProvider = Provider.of<ConferenceProvider>(
        context,
        listen: false,
      );

      // 🚀 KRİTİK: Gelen arama varsa sync YAPMA!
      if (conferenceProvider.hasIncomingCall) {
        debugPrint(
          "📞 Gelen arama var, sync atlanıyor (çakışmayı önlemek için)",
        );
        return;
      }

      // Backend'den aktif konferans kontrolü
      final activeRoomId = await widget.signalRService.methods
          ?.getActiveRoomForGroup(widget.groupModel.id);

      debugPrint("🔄 Conference sync: Backend activeRoomId = $activeRoomId");
      debugPrint(
        "   Provider activeRoomId = ${conferenceProvider.activeRoomId}",
      );

      // Eğer provider'da roomId var ama backend'de yok, temizle
      if (conferenceProvider.activeRoomId != null &&
          (activeRoomId == null || activeRoomId == 0)) {
        debugPrint("🧹 Provider'da eski roomId var, temizleniyor...");
        conferenceProvider.clearActiveRoom();
      }
      // Eğer backend'de var ama provider'da yok, set et
      else if ((conferenceProvider.activeRoomId == null ||
              conferenceProvider.activeRoomId == 0) &&
          activeRoomId != null &&
          activeRoomId > 0) {
        debugPrint(
          "📞 Backend'de aktif konferans var, provider'a set ediliyor...",
        );
        conferenceProvider.setActiveRoomFromBackend(
          activeRoomId,
          widget.groupModel.id,
        );
      }
    } catch (e) {
      debugPrint("❌ Conference sync hatası: $e");
    }
  }

  // ✅ YENİ: SignalR Event Dinleyicisi
  void _setupSignalRListener() {
    final signalr = context.read<SignalrService>();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String myId = authProvider.currentUser?.userId ?? "";

    _groupUpdateSubscription = signalr.friendEventStream.listen((data) {
      if (!mounted) return;

      final String? type = data['type'];
      final String? groupId = data['groupId']?.toString();
      final String? eventUserId = data['userId']?.toString();

      if (type == 'InfoUpdated' || type == 'ReceiveUserInfoUpdated') {
        if (eventUserId != null) {
          // Eğer bu kullanıcı bizim grubumuzun bir üyesiyse listeyi tazele
          bool isMember = widget.groupModel.members.any(
            (m) => m.id.toLowerCase() == eventUserId.toLowerCase(),
          );

          if (isMember) {
            debugPrint(
              "👤 Gruptaki bir üye profilini güncelledi, liste tazeleniyor...",
            );
            _refreshMemberInfo(eventUserId);
          }
        }
      }
      // 🚀 KRİTİK: Gruptan Atılma Kontrolü
      if (type == 'UserLeftGroup') {
        // Eğer bu gruptan atılan kişi BENSEM
        if (groupId == widget.groupModel.id &&
            eventUserId?.toLowerCase() == myId.toLowerCase()) {
          debugPrint("🚫 SignalR: Bu gruptan atıldınız. Yönlendiriliyor...");

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Gruptan çıkarıldınız"),
                backgroundColor: Colors.redAccent,
              ),
            );
            // Tüm sayfa yığınını temizle ve ana ekrana (ExploreUsersScreen) dön
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        }
      }

      // ✅ Grup Silindi Kontrolü
      if (type == 'GroupDeleted' && groupId == widget.groupModel.id) {
        debugPrint("🗑️ SignalR: Grup silindi, message_screen'e dönülüyor...");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Grup silindi")));
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        return;
      }

      // ✅ Grup Bilgisi Güncellendi (İsim, Resim vb.)
      if (type == 'InfoUpdated' || type == 'GroupInfoUpdated') {
        if (groupId == null || groupId == widget.groupModel.id) {
          debugPrint("📡 SignalR: Grup bilgisi güncelleniyor...");
          _refreshGroupInfo();
        }
      }
    });
  }

  Future<void> _refreshMemberInfo(String userId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String token = authProvider.token ?? "";

    try {
      // API'den güncel resim ve isim bilgilerini alalım
      final String? newUrl = await _apiService.profile.getProfileImageUrl(
        userId,
        token,
      );
      // İsim için bir servis çağrısı yapabilirsin veya getFreshGroupInfo'yu komple çağırabilirsin

      if (mounted) {
        setState(() {
          // 1. Üye listesindeki bilgiyi bul ve güncelle
          for (var member in widget.groupModel.members) {
            if (member.id.toLowerCase() == userId.toLowerCase()) {
              if (newUrl != null) {
                member.imageUrl =
                    "$newUrl?t=${DateTime.now().millisecondsSinceEpoch}";
              }
            }
          }
          // UI'ın tetiklenmesi için listeyi provoke et
        });
      }
    } catch (e) {
      debugPrint("❌ Üye bilgisi tazelenemedi: $e");
    }
  }

  // ✅ YENİ: Grup bilgisini yenile
  Future<void> _refreshGroupInfo() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String token = authProvider.token ?? "";
    final String groupId = widget.groupModel.id;

    try {
      final detailedGroup = await _apiService.group.getFreshGroupInfo(
        groupId,
        token,
      );

      if (detailedGroup != null && mounted) {
        setState(() {
          // Grup fotoğrafını güncelle
          if (detailedGroup.imageUrl != null &&
              detailedGroup.imageUrl!.isNotEmpty) {
            widget.groupModel.imageUrl =
                "${detailedGroup.imageUrl}?t=${DateTime.now().millisecondsSinceEpoch}";
          }
          // Grup adını güncelle
          if (detailedGroup.name != null) {
            widget.groupModel.name = detailedGroup.name!;
          }
        });
        debugPrint(
          "✅ GroupChatScreen: Grup bilgisi güncellendi - ${widget.groupModel.imageUrl}",
        );
      }
    } catch (e) {
      debugPrint("❌ GroupChatScreen: Grup bilgisi yenileme hatası: $e");
    }
  }

  void _setupAudioListeners() {
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _position = p));
    _audioPlayer.onDurationChanged.listen((d) => setState(() => _duration = d));
    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _currentlyPlayingUrl = null;
        _position = Duration.zero;
      });
    });
  }

  void _loadInitialData() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final String token = authProvider.token ?? "";
      final String groupId = widget.groupModel.id;

      // 1. Provider'a aktif sohbeti bildir (Bildirimleri sıfırlar)
      chatProvider.setActiveChat(groupId);

      try {
        // 2. GRUP BİLGİLERİNİ GÜNCELLE (İsim, Üyeler, Fotoğraf)
        final detailedGroup = await _apiService.group.getFreshGroupInfo(
          groupId,
          token,
        );

        if (detailedGroup != null && mounted) {
          // Üye listesini UserItem formatına çevir
          List<UserItem> updatedMembers = detailedGroup.members
              .map(
                (m) => UserItem(
                  id: m.userId,
                  name: m.userName ?? "Bilinmeyen",
                  imageUrl: null,
                ),
              )
              .toList();

          setState(() {
            widget.groupModel.members.clear();
            widget.groupModel.members.addAll(updatedMembers);

            if (detailedGroup.name != null && detailedGroup.name!.isNotEmpty) {
              widget.groupModel.name = detailedGroup.name!;
            }
            if (detailedGroup.imageUrl != null &&
                detailedGroup.imageUrl!.isNotEmpty) {
              widget.groupModel.imageUrl =
                  "${detailedGroup.imageUrl}?t=${DateTime.now().millisecondsSinceEpoch}";
            }
          });

          // Üyelerin profil fotoğraflarını çek
          for (var member in widget.groupModel.members) {
            _apiService.profile.getProfileImageUrl(member.id, token).then((
              imgUrl,
            ) {
              if (imgUrl != null && mounted) {
                setState(() => member.imageUrl = imgUrl);
              }
            });
          }
        }
      } catch (e) {
        debugPrint("❌ [Grup Bilgi Hatası]: $e");
      }

      // --- 🚀 3. MESAJLARI ÇEKME MANTIĞI ---
      debugPrint("🔗 SignalR gruba katılma isteği gönderiliyor: $groupId");
      final signalR = widget.signalRService;

      // Eğer SignalR henüz bağlanmamışsa bekle (max 5 saniye)
      if (!signalR.isConnected) {
        debugPrint("⏳ SignalR bağlantısı bekleniyor...");
        int attempts = 0;
        while (!signalR.isConnected && attempts < 20 && mounted) {
          await Future.delayed(const Duration(milliseconds: 250));
          attempts++;
        }
        debugPrint(
          signalR.isConnected
              ? "✅ SignalR bağlandı"
              : "⚠️ SignalR bağlantısı zaman aşımına uğradı",
        );
      }

      // Gruba join yap
      if (signalR.isConnected) {
        try {
          final success = await signalR.methods?.joinMultipleGroups([groupId]);
          if (success == true) {
            debugPrint("✅ SignalR gruba başarıyla katıldı: $groupId");
          } else {
            debugPrint("⚠️ SignalR gruba katılma başarısız: $groupId");
          }
        } catch (e) {
          debugPrint("❌ SignalR join hatası: $e");
        }
      }

      // --- 🚀 4. MESAJLARI ÇEKME MANTIĞI ---
      final existingMessages = chatProvider.chatCache[groupId];

      // ✅ Cache boşsa veya bildirimden gelindiği varsayımıyla her zaman tazele
      if (existingMessages == null || existingMessages.isEmpty) {
        debugPrint("🔄 Grup Cache boş, DB'den mesajlar çekiliyor...");
        try {
          final dbMessages = await _apiService.messageApi
              .getGroupMessagesFromDb(groupId, token);

          if (dbMessages.isNotEmpty && mounted) {
            chatProvider.setMessages(groupId, dbMessages);
            _scrollToBottom();
            debugPrint("✅ DB'den ${dbMessages.length} grup mesajı yüklendi.");
          }
        } catch (e) {
          debugPrint("❌ [Grup Mesaj Çekme Hatası]: $e");
        }
      } else {
        debugPrint(
          "✅ Grup mesajları cache'de mevcut (${existingMessages.length} adet).",
        );
        _scrollToBottom();
      }
    });
  }

  // ... (Diğer metodlar aynı kalıyor - _isFileType, _formatFileSize, _handleSendMessage, _toggleAudio, vb.)

  bool _isFileType(String url, dynamic messageType, List<String> extensions) {
    final String cleanUrl = url.split('?').first.toLowerCase();
    final String ext = cleanUrl.split('.').last;
    if (extensions.contains(ext)) return true;

    MessageType type = ChatMessage.parseType(messageType);
    if (extensions.contains('mp3') && type == MessageType.Audio) return true;
    if (extensions.contains('mp4') && type == MessageType.Video) return true;
    if (extensions.contains('jpg') && type == MessageType.Image) return true;
    if (extensions.contains('pdf') && type == MessageType.Document) return true;
    return false;
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double num =
        bytes /
        (i == 0 ? 1 : (i == 1 ? 1024 : (i == 2 ? 1048576 : 1073741824)));
    return "${num.toStringAsFixed(1)} ${suffixes[i]}";
  }

  // ✅ P2P'DEKİ GİBİ: MIME type helper fonksiyonu
  String _getMimeType(String fileName) {
    String ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _handleSendMessage({
    String? text,
    String? fileUrl,
    int? fileSize,
  }) async {
    final String messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty && fileUrl == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // ✅ CRITICAL: Dosya mesajı ise pending zamanı kullan
    final String messageId = (fileUrl != null && _pendingFileMessageId != null)
        ? _pendingFileMessageId!
        : const Uuid().v4();

    final DateTime sentAt = (fileUrl != null && _pendingFileMessageTime != null)
        ? _pendingFileMessageTime!
        : DateTime.now().toUtc();

    MessageType messageType = MessageType.Text;
    if (fileUrl != null) {
      String ext = messageText.toLowerCase().split('.').last;
      if (['jpg', 'jpeg', 'png', 'webp'].contains(ext))
        messageType = MessageType.Image;
      else if (['mp4', 'mov', 'avi'].contains(ext))
        messageType = MessageType.Video;
      else if (['mp3', 'wav', 'm4a'].contains(ext))
        messageType = MessageType.Audio;
      else
        messageType = MessageType.Document;
    }

    final Map<String, dynamic> messageDto = {
      "Id": messageId,
      "SenderId": authProvider.currentUser?.userId,
      "ReceiverId": null,
      "ChatRoomId": widget.groupModel.id,
      "Content": messageText,
      "Type": messageType.index,
      "SentAt": sentAt.toIso8601String(),
      "IsRead": false,
      "FileUrl": fileUrl,
      "FileSize": fileSize,
      "IsGroupMessage": true,
    };

    // ✅ P2P'DEKİ GİBİ: Dosya mesajı ise FileData objesi ekle
    if (fileUrl != null) {
      messageDto["FileData"] = {
        "FileName": messageText,
        "ContentType": _getMimeType(messageText),
        "FileSize": fileSize ?? 0,
        "UploadedAt": sentAt.toIso8601String(),
        "FileType": messageType.index,
        "FilePath": fileUrl,
        "IsImage": messageType == MessageType.Image,
        "IsVideo": messageType == MessageType.Video,
        "IsAudio": messageType == MessageType.Audio,
        "IsDocument": messageType == MessageType.Document,
        "HasThumbnail": false,
      };
    }

    _messageController.clear();
    _scrollToBottom();

    try {
      bool isSaved = await _apiService.messageApi.saveMessageToDb(
        messageDto,
        authProvider.token ?? "",
      );

      if (isSaved) {
        // ✅ P2P'DEKİ GİBİ: Detaylı log
        debugPrint(
          "📤 Grup mesajı gönderiliyor - ID: $messageId, Type: ${messageType.name}, FileSize: $fileSize, SentAt: ${sentAt.toIso8601String()}",
        );
        chatProvider.addMessage(widget.groupModel.id, messageDto, false);

        await widget.signalRService.methods!.sendMessage(
          widget.groupModel.id,
          messageText,
          fileUrl ?? "",
          messageType.index.toString(),
          fileSize ?? 0,
          true, // isGroupMessage
          messageId,
          sentAt.toIso8601String(),
        );

        debugPrint(
          "✅ Grup mesajı başarıyla gönderildi ve local state'e eklendi - ID: $messageId",
        );

        // ✅ Pending değişkenleri temizle
        if (fileUrl != null) {
          _pendingFileMessageId = null;
          _pendingFileMessageTime = null;
        }
      } else {
        debugPrint("❌ Grup mesajı DB'ye kaydedilemedi!");
      }
    } catch (e) {
      debugPrint("❌ Grup Mesaj Hatası: $e");
    }
  }

  Future<void> _toggleAudio(String url) async {
    if (_currentlyPlayingUrl == url) {
      _audioPlayer.state == PlayerState.playing
          ? await _audioPlayer.pause()
          : await _audioPlayer.resume();
      setState(() {});
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
      setState(() => _currentlyPlayingUrl = url);
    }
  }

  void _togglePlaybackRate() async {
    _playbackRate = _playbackRate == 1.0
        ? 1.5
        : (_playbackRate == 1.5 ? 2.0 : 1.0);
    await _audioPlayer.setPlaybackRate(_playbackRate);
    setState(() {});
  }

  Future<void> _seekAudio(Duration position) async =>
      await _audioPlayer.seek(position);

  @override
  Widget build(BuildContext context) {
    // ✅ Geçerli image URL kontrolü
    final bool hasValidGroupImage =
        widget.groupModel.imageUrl != null &&
        widget.groupModel.imageUrl!.trim().isNotEmpty &&
        widget.groupModel.imageUrl!.startsWith('http');

    return Scaffold(
      // ✅ Klavye açıldığında listeyi yukarı kaydırır
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupScreen(groupId: widget.groupModel.id),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage: hasValidGroupImage
                    ? NetworkImage(widget.groupModel.imageUrl!)
                    : null,
                child: !hasValidGroupImage ? const Icon(Icons.group) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.groupModel.name,
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      "Grup bilgisi için tıkla",
                      style: TextStyle(fontSize: 10, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // ✅ YENİ: ConferenceProvider'ı dinle
          Consumer<ConferenceProvider>(
            builder: (context, conferenceProv, child) {
              // 🐛 DEBUG LOG
              debugPrint(
                "📹 GroupChatScreen: isInCall=${conferenceProv.isInCall}, state=${conferenceProv.state}, activeRoomId=${conferenceProv.activeRoomId}",
              );

              // 🚀 KRİTİK: Konferanstayken hiçbir ikon gösterme
              if (conferenceProv.isInCall) {
                debugPrint("✅ GroupChatScreen: İkon gizlendi");
                return const SizedBox.shrink();
              }

              debugPrint("📷 GroupChatScreen: İkon gösteriliyor");
              // Aktif konferans var mı kontrol et

              // Eğer _isGroupCall ve _targetId bu gruba aitse rejoin icon göster
              final bool hasActiveConference =
                  conferenceProv.activeRoomId != null &&
                  conferenceProv.activeRoomId! > 0;

              return IconButton(
                icon: Icon(
                  hasActiveConference ? Icons.phone_forwarded : Icons.videocam,
                  size: 28,
                  color: hasActiveConference ? Colors.green : Colors.black,
                ),
                onPressed: () async {
                  final signalRProv = Provider.of<SignalrService>(
                    context,
                    listen: false,
                  );
                  final authProv = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  );

                  // Backend'den güncel oda durumunu kontrol et
                  int activeRoomId =
                      await signalRProv.methods?.getActiveRoomForGroup(
                        widget.groupModel.id,
                      ) ??
                      0;

                  debugPrint(
                    "📞 Video icon tıklandı. Backend'den gelen activeRoomId: $activeRoomId",
                  );

                  if (activeRoomId != 0) {
                    // Aktif konferans var, rejoin
                    debugPrint("🔄 Aktif konferansa yeniden katılınıyor...");
                    await conferenceProv.joinExistingGroupCall(
                      janusUrl: janus,
                      roomId: activeRoomId,
                      myName: authProv.currentUser?.userName ?? "",
                      groupId: widget.groupModel.id,
                    );
                  } else {
                    // Konferans yok, yeni başlat
                    debugPrint("🆕 Yeni konferans başlatılıyor...");
                    await conferenceProv.startNewCall(
                      janusUrl: janus,
                      myId: authProv.currentUser?.userId ?? "",
                      myName: authProv.currentUser?.userName ?? "",
                      targetId: widget.groupModel.id,
                      isGroup: true,
                    );
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      // ✅ Tüm içeriği SafeArea içine alarak alt/üst çentik taşmalarını önlüyoruz
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, child) {
                  final List<Map<String, dynamic>> rawMessages =
                      chatProvider.chatCache[widget.groupModel.id] ?? [];
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: rawMessages.length,
                    itemBuilder: (context, index) {
                      final m = rawMessages[rawMessages.length - 1 - index];
                      final String myId =
                          Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          ).currentUser?.userId ??
                          "";

                      final chatMsg = ChatMessage(
                        text: m["content"] ?? m["Content"] ?? "",
                        isMe:
                            (m["senderId"] ?? m["SenderId"] ?? "")
                                .toString()
                                .toLowerCase() ==
                            myId.toLowerCase(),
                        time:
                            DateTime.tryParse(
                              m["sentAt"] ?? m["SentAt"] ?? "",
                            )?.toLocal() ??
                            DateTime.now(),
                        fileUrl: m["fileUrl"] ?? m["FileUrl"],
                        type: ChatMessage.parseType(m["type"] ?? m["Type"]),
                        fileSize: m["fileData"] != null
                            ? (m["fileData"]["fileSize"] ??
                                  m["fileData"]["FileSize"])
                            : (m["fileSize"] ?? m["FileSize"] ?? m["filesize"]),
                      );

                      return _buildMessageBubble(
                        chatMsg,
                        m["senderId"] ?? m["SenderId"],
                      );
                    },
                  );
                },
              ),
            ),
            if (_isUploading || _isDownloading) _buildProgressIndicator(),
            _buildInputArea(), // SafeArea desteği metodun içinde olmalı
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, String senderId) {
    // ✅ Doğru tarih formatı: HH:mm (saat:dakika)
    final timeText =
        "${message.time.day.toString().padLeft(2, '0')}.${message.time.month.toString().padLeft(2, '0')}.${message.time.year} ${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}";

    UserItem? senderMember;
    try {
      senderMember = widget.groupModel.members.firstWhere(
        (m) => m.id.toLowerCase() == senderId.toLowerCase(),
      );
    } catch (e) {
      senderMember = null;
    }

    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: message.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: message.isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!message.isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                  child: GestureDetector(
                    // 👈 Tıklama özelliği eklendi
                    onTap: () {
                      // Mesajı gönderen kişinin (senderId) detaylarını açar
                      UserDetailModal.show(context, senderId);
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundImage: senderMember?.imageUrl != null
                          ? NetworkImage(senderMember!.imageUrl!)
                          : null,
                      child: senderMember?.imageUrl == null
                          ? const Icon(Icons.person, size: 18)
                          : null,
                    ),
                  ),
                ),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: message.isMe ? Colors.blue : Colors.grey[300],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(message.isMe ? 16 : 0),
                      bottomRight: Radius.circular(message.isMe ? 0 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!message.isMe)
                        Text(
                          senderMember?.name ?? "Bilinmeyen",
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      _buildMessageContent(message),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              left: message.isMe ? 0 : 50,
              right: message.isMe ? 16 : 0,
              bottom: 8,
            ),
            child: Text(
              timeText,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(ChatMessage message) {
    if (message.fileUrl == null || message.fileUrl!.isEmpty) {
      return Text(
        message.text,
        style: TextStyle(color: message.isMe ? Colors.white : Colors.black),
      );
    }

    final String url = message.fileUrl!;
    final bool isMe = message.isMe;

    // ✅ ChatScreen'deki gibi: LayoutBuilder KALDIRILDI, direkt MediaQuery kullanıldı
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxImageWidth = screenWidth * 0.5; // Ekranın %50'si

    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.type == MessageType.Image ||
              _isFileType(url, message.type, ['jpg', 'jpeg', 'png', 'webp']))
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    body: Center(
                      child: InteractiveViewer(child: Image.network(url)),
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: maxImageWidth, // ✅ Sabit ekran genişliği kullanıldı
                  fit: BoxFit.cover,
                ),
              ),
            )
          else if (message.type == MessageType.Video ||
              _isFileType(url, message.type, ['mp4', 'mov', 'avi']))
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VideoPlayerPage(url: url)),
              ),
              child: Container(
                width: maxImageWidth, // ✅ Sabit ekran genişliği kullanıldı
                height: maxImageWidth * 0.75, // 4:3 aspect ratio
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            )
          else if (message.type == MessageType.Audio ||
              _isFileType(url, message.type, ['mp3', 'wav', 'm4a', 'ogg']))
            _buildAudioWidget(message, url) // ✅ GroupChat'te bu metod var
          else
            Row(
              children: [
                Icon(
                  Icons.insert_drive_file,
                  color: isMe ? Colors.white : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message.text,
                    style: TextStyle(color: isMe ? Colors.white : Colors.black),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 8),
          _buildDownloadButton(message, url), // ✅ GroupChat'te bu metod var
        ],
      ),
    );
  }

  Widget _buildAudioWidget(ChatMessage message, String url) {
    final bool isPlaying = _currentlyPlayingUrl == url;
    return Row(
      children: [
        IconButton(
          icon: Icon(
            isPlaying && _audioPlayer.state == PlayerState.playing
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
          ),
          color: message.isMe ? Colors.white : Colors.blue,
          iconSize: 35,
          onPressed: () => _toggleAudio(url),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              if (isPlaying)
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        activeColor: message.isMe ? Colors.white : Colors.blue,
                        value: _position.inMilliseconds.toDouble().clamp(
                          0,
                          _duration.inMilliseconds.toDouble(),
                        ),
                        max: _duration.inMilliseconds.toDouble() > 0
                            ? _duration.inMilliseconds.toDouble()
                            : 1.0,
                        onChanged: (v) =>
                            _seekAudio(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                    GestureDetector(
                      onTap: _togglePlaybackRate,
                      child: Text(
                        "${_playbackRate}x",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadButton(ChatMessage message, String url) {
    return InkWell(
      onTap: () => _startDownload(url, message.text),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: message.isMe ? Colors.white12 : Colors.black12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_download,
                  size: 16,
                  color: message.isMe ? Colors.white : Colors.blue,
                ),
                const SizedBox(width: 5),
                const Text(
                  "İndir",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (message.fileSize != null)
              Text(
                _formatFileSize(message.fileSize!),
                style: const TextStyle(fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final Color color = _isUploading ? Colors.green : Colors.blue;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _isUploading ? Icons.cloud_upload : Icons.cloud_download,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "${_isUploading ? "Yükleniyor" : "İndiriliyor"}: $_currentTransferFileName",
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                "%${((_isUploading ? _uploadProgress : _downloadProgress) * 100).toInt()}",
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _isUploading ? _uploadProgress : _downloadProgress,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      // Arka plan rengini SafeArea dışına taşmasın diye buraya veriyoruz
      color: Colors.white,
      child: SafeArea(
        // bottom: true ile ekranın en altındaki fiziksel çentiği hesaba katar
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade300, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _pickAndUploadFile,
              ),
              Expanded(
                child: ConstrainedBox(
                  // Mesaj çok uzarsa TextField'ın devasa büyümesini engeller
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: TextField(
                    controller: _messageController,
                    // Çok satırlı desteği ekleyerek taşmayı önleyelim
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: "Mesaj yaz...",
                      border: InputBorder.none,
                      isDense: true, // Daha kompakt bir giriş alanı sağlar
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                    ),
                    onSubmitted: (_) => _handleSendMessage(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: () => _handleSendMessage(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToBottom() => Future.delayed(
    const Duration(milliseconds: 200),
    () => _scrollController.hasClients
        ? _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          )
        : null,
  );

  Future<void> _pickAndUploadFile() async {
    // 1. Dosya Seçimi
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    File file = File(result.files.single.path!);
    int size = await file.length();
    final String fileName = result.files.single.name;

    // ✅ YENİ: Dosya tipi ve boyut kontrolü
    final String fileExt = fileName.split('.').last.toLowerCase();
    int maxSize;
    String fileTypeLabel;

    // Resim formatları: 50 MB
    if (['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'].contains(fileExt)) {
      maxSize = 50 * 1024 * 1024;
      fileTypeLabel = 'Resim';
    }
    // Video formatları: 500 MB
    else if (['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'].contains(fileExt)) {
      maxSize = 500 * 1024 * 1024;
      fileTypeLabel = 'Video';
    }
    // Diğer dosyalar: 200 MB
    else {
      maxSize = 200 * 1024 * 1024;
      fileTypeLabel = 'Dosya';
    }

    if (size > maxSize) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$fileTypeLabel çok büyük! Maksimum ${(maxSize / (1024 * 1024)).toStringAsFixed(0)} MB olabilir.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return; // Upload'u iptal et
    }

    // ✅ KRİTİK: Zaman ve ID sabitleme (Sıralama bozulmaması için)
    _pendingFileMessageId = const Uuid().v4();
    _pendingFileMessageTime = DateTime.now().toUtc();

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _currentTransferFileName = result.files.single.name;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);

    try {
      // 2. Dosya Yükleme (API'ye)
      String? url =
          await FileUploadService(
            baseUrl: "https://convoapp.app/api",
            token: auth.token ?? "",
          ).uploadFile(
            file,
            onProgress: (p) => setState(() => _uploadProgress = p),
          );

      setState(() => _isUploading = false);

      if (url != null) {
        debugPrint("📁 Dosya yüklendi, SignalR aboneliği kontrol ediliyor...");

        // 3. SIGNALR DURUM KONTROLÜ VE HIZLI JOIN
        // Uygulama arka plandan (galeriden) döndüğü için bağlantı anlık 'zombi' olabilir.
        if (!widget.signalRService.isConnected) {
          debugPrint("⏳ Bağlantı kopuk, reconnect bekleniyor...");
          int attempts = 0;
          while (!widget.signalRService.isConnected && attempts < 10) {
            await Future.delayed(const Duration(milliseconds: 300));
            attempts++;
          }
        }

        // 4. HUB ÜYELİĞİNİ TAZELE (EN ÖNEMLİ KISIM)
        // Mesaj gitmeden hemen önce Hub'a "bu gruptayım" diyoruz.
        // await kullanmıyoruz (ateşle ve unut), milisaniyeler içinde Hub bizi odaya geri alır.
        if (widget.signalRService.isConnected) {
          widget.signalRService.methods?.joinMultipleGroups([
            widget.groupModel.id,
          ]);

          // Hub'ın Join işlemini kaydetmesi için çok kısa bir bekleme (Sinyal çakışmasını önler)
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // 5. Mesajı Gönder
        await _handleSendMessage(
          text: result.files.single.name,
          fileUrl: url,
          fileSize: size,
        );

        debugPrint("✅ Dosya mesajı SignalR üzerinden başarıyla tetiklendi.");
      }
    } catch (e) {
      debugPrint("❌ Dosya gönderme sürecinde hata: $e");
      setState(() => _isUploading = false);
    }
    FocusScope.of(context).unfocus();
  }

  Future<void> _startDownload(String url, String fileName) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _currentTransferFileName = fileName;
    });
    try {
      String? path = await FileDownloadService().downloadFile(
        url,
        fileName,
        onProgress: (p) => setState(() => _downloadProgress = p),
      );
      if (path != null && mounted) await OpenFilex.open(path);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _checkAndAcceptIncomingCall() async {
    if (!mounted) return;

    final conferenceProvider = Provider.of<ConferenceProvider>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    debugPrint("═══════════════════════════════════════");
    debugPrint("🔍 GROUP: _checkAndAcceptIncomingCall çağrıldı");
    debugPrint("   hasIncomingCall: ${conferenceProvider.hasIncomingCall}");
    debugPrint("   incomingCallData: ${conferenceProvider.incomingCallData}");
    debugPrint("   widget.groupModel.id: ${widget.groupModel.id}");
    debugPrint("═══════════════════════════════════════");

    // Gelen arama varsa ve bu gruptan ise
    if (conferenceProvider.hasIncomingCall) {
      final callData = conferenceProvider.incomingCallData;
      final groupId = callData?['groupId']?.toString();
      final isGroup = callData?['isGroup'] ?? false;

      debugPrint("📞 Gelen arama var!");
      debugPrint("   groupId (callData): $groupId");
      debugPrint("   isGroup: $isGroup");
      debugPrint("   Eşleşme kontrolü: ${groupId == widget.groupModel.id}");

      // Grup call ve bu gruptan geliyorsa
      if (isGroup && groupId == widget.groupModel.id) {
        debugPrint("✅ Eşleşme BAŞARILI, otomatik katılım başlıyor...");

        await conferenceProvider.acceptIncomingCall(
          janusUrl: janus,
          myId: authProvider.currentUser?.userId ?? "",
          myName: authProvider.currentUser?.userName ?? "Kullanıcı",
        );
      } else {
        debugPrint("❌ Eşleşme BAŞARISIZ!");
        debugPrint(
          "   Sebep: isGroup=$isGroup, groupId match=${groupId == widget.groupModel.id}",
        );
      }
    } else {
      debugPrint("⚠️ hasIncomingCall = false, gelen arama yok");
    }
  }

  Future<void> _refreshMessagesFromServer() async {
    if (!mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    try {
      final dbMessages = await _apiService.messageApi.getGroupMessagesFromDb(
        widget.groupModel.id,
        auth.token!,
      );
      if (mounted && dbMessages.isNotEmpty) {
        chatProvider.syncMessages(widget.groupModel.id, dbMessages);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("❌ Grup Sync Hatası: $e");
    }
  }

  @override
  void dispose() {
    _appResumedSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _groupUpdateSubscription?.cancel();
    super.dispose();
  }
}
