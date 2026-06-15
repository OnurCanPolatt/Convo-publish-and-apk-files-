import 'dart:async';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/models/friend.dart';
import 'package:my_first_flutterapp/screens/video_call_screen.dart';
import 'package:my_first_flutterapp/services/signalr/signalr_service.dart';
import 'package:provider/provider.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';
import 'package:my_first_flutterapp/providers/chat_provider.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:my_first_flutterapp/services/file_upload_service.dart';
import 'package:my_first_flutterapp/services/download_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:open_filex/open_filex.dart';
import 'package:my_first_flutterapp/players/video_player_page.dart';
import 'package:flutter/cupertino.dart';

import '../models/chat_message.dart';
import '../providers/conference_provider.dart';
import '../widgets/user_detail_modal.dart';

class ChatScreen extends StatefulWidget {
  final FriendModel friendModel;
  final SignalrService signalRService;

  const ChatScreen({
    super.key,
    required this.friendModel,
    required this.signalRService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String? _currentTransferFileName;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingUrl;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  double _uploadProgress = 0.0;
  bool _isUploading = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  double _playbackRate = 1.0;

  String? _pendingFileMessageId;
  DateTime? _pendingFileMessageTime;

  String janus = "ws://convoapp.app:8188";

  // ✅ YENİ: SignalR event subscription
  StreamSubscription? _profileUpdateSubscription;
  StreamSubscription? _appResumedSubscription;

  // ✅ YENİ: Arkadaşın güncel fotoğraf URL'i (dinamik güncelleme için)
  String? _friendImageUrl;

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double num =
        bytes /
        (i == 0
            ? 1
            : (i == 1 ? 1024 : (i == 2 ? 1024 * 1024 : 1024 * 1024 * 1024)));
    return "${num.toStringAsFixed(1)} ${suffixes[i]}";
  }

  @override
  void initState() {
    super.initState();

    // 1. Ses Oynatıcı Listener'ları
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _position = p));
    _audioPlayer.onDurationChanged.listen((d) => setState(() => _duration = d));
    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _currentlyPlayingUrl = null;
        _position = Duration.zero;
      });
    });

    // 2. SignalR Dinleyicisini Başlat
    _setupSignalRListener();
    _appResumedSubscription = widget.signalRService.appResumedStream.listen((
      _,
    ) {
      if (mounted) {
        _refreshMessagesFromServer();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndAcceptIncomingCall();
      _refreshMessagesFromServer();
    });

    // 3. Fotoğraf Yükleme ve Mesaj Senkronizasyonu
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final String token = authProvider.token ?? "";
      final String friendId = widget.friendModel.id.toLowerCase();

      // Provider'a aktif sohbeti bildir (Bildirim sayaçlarını sıfırlar)
      chatProvider.setActiveChat(widget.friendModel.id);

      // --- FOTOĞRAF YÜKLEME MANTIĞI ---
      final String? cachedImage = chatProvider.userImageCache[friendId];
      if (cachedImage != null &&
          cachedImage.isNotEmpty &&
          !cachedImage.contains("assets/")) {
        setState(() => _friendImageUrl = cachedImage);
        debugPrint("📸 Fotoğraf Cache'den yüklendi.");
      } else {
        debugPrint("🔍 Fotoğraf Cache'de yok, API'den sorgulanıyor...");
        final String? realUrl = await _apiService.profile.getProfileImageUrl(
          widget.friendModel.id,
          token,
        );
        if (mounted && realUrl != null) {
          setState(() {
            _friendImageUrl = realUrl;
            widget.friendModel.imageUrl = realUrl;
          });
        }
      }

      // --- 🚀 MESAJLARI ÇEKME MANTIĞI (GÜNCELLENDİ) ---
      // Önce Cache kontrolü yapıyoruz
      final existingMessages = chatProvider.chatCache[friendId];

      // ✅ YENİ: Cache boşsa VEYA bildirimin dışarıdan geldiğini varsayıyorsak tazele
      if (existingMessages == null || existingMessages.isEmpty) {
        debugPrint("🔄 Cache boş, DB'den mesajlar çekiliyor...");
        try {
          final dbMessages = await _apiService.messageApi.getMessagesFromDb(
            authProvider.currentUser?.userId ?? "",
            widget.friendModel.id,
            token,
          );

          if (dbMessages.isNotEmpty && mounted) {
            chatProvider.setMessages(widget.friendModel.id, dbMessages);
            _scrollToBottom();
            debugPrint(
              "✅ DB'den ${dbMessages.length} mesaj alındı ve cache'lendi.",
            );
          } else if (mounted) {
            debugPrint("ℹ️ DB'de bu sohbet için mesaj yok.");
            _scrollToBottom();
          }
        } catch (e) {
          debugPrint("❌ Mesajlar çekilirken hata oluştu: $e");
        }
      } else {
        debugPrint(
          "✅ Mesajlar cache'de mevcut (${existingMessages.length} adet).",
        );
        _scrollToBottom();
      }
    });
  }

  // ✅ YENİ: SignalR Event Dinleyicisi - DOĞRU VERSİYON
  void _setupSignalRListener() {
    final signalr = context.read<SignalrService>();

    _profileUpdateSubscription = signalr.friendEventStream.listen((data) {
      if (!mounted) return;

      final String? type = data['type'];
      final String? eventUserId = data['userId']?.toString();
      final String? groupId = data['groupId']?.toString();

      debugPrint(
        "📡 ChatScreen: SignalR Event - type: $type, userId: $eventUserId",
      );

      // Kullanıcı profil fotoğrafı güncellendiğinde
      if (type == 'ReceiveUserInfoUpdated' ||
          type == 'MyInfo' ||
          type == 'InfoUpdated') {
        // groupId null/boş ise bu bir kullanıcı güncellemesi
        if (groupId == null || groupId.isEmpty) {
          // eventUserId varsa ve bu arkadaş için ise
          if (eventUserId != null &&
              eventUserId.toLowerCase() ==
                  widget.friendModel.id.toLowerCase()) {
            debugPrint(
              "🔄 ChatScreen: Arkadaş profili güncelleniyor - $eventUserId",
            );
            _refreshFriendProfile();
          }
          // eventUserId yoksa (eski client) genel güncelleme yap
          else if (eventUserId == null) {
            debugPrint("🔄 ChatScreen: Genel profil güncellemesi");
            _refreshFriendProfile();
          }
        }
      }
    });

    debugPrint("✅ ChatScreen: SignalR dinleyicisi kuruldu");
  }

  // ✅ YENİ: Arkadaş profilini yenile
  // ✅ GÜNCELLENMİŞ METOT: Arkadaşın hem adını hem fotoğrafını tazeler
  Future<void> _refreshFriendProfile() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String token = authProvider.token ?? "";
    final String friendId = widget.friendModel.id;

    try {
      // 1. Profil bilgilerini API'den tekrar çek (Ad ve diğer bilgiler için)
      // Not: getFreshUserInfo gibi bir metodun yoksa UserDetail için kullandığın servisi kullanabilirsin
      final dynamic freshUser = await _apiService.profile.getUserDetail(
        friendId,
        token,
      );

      if (mounted && freshUser != null) {
        setState(() {
          // Kullanıcı adını güncelle
          widget.friendModel.userName =
              freshUser['userName'] ?? widget.friendModel.userName;

          // Fotoğraf URL'ini güncelle ve cache kır
          if (freshUser['imageUrl'] != null) {
            _friendImageUrl =
                "${freshUser['imageUrl']}?t=${DateTime.now().millisecondsSinceEpoch}";
            widget.friendModel.imageUrl = _friendImageUrl;
          }
        });
        debugPrint(
          "✅ ChatScreen: Arkadaş bilgileri güncellendi - ${widget.friendModel.userName}",
        );
      }
    } catch (e) {
      // Sadece fotoğrafı denemeye devam et (yedek plan)
      debugPrint("⚠️ Detaylı profil çekilemedi, sadece fotoğraf deneniyor...");
      final String? newUrl = await _apiService.profile.getProfileImageUrl(
        friendId,
        token,
      );
      if (mounted && newUrl != null) {
        setState(() {
          _friendImageUrl =
              "$newUrl?t=${DateTime.now().millisecondsSinceEpoch}";
          widget.friendModel.imageUrl = _friendImageUrl;
        });
      }
    }
  }

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

  Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      final int fileSize = await file.length();
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

      if (fileSize > maxSize) {
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

      // ✅ CRITICAL: Dosya seçildiği anda zaman ve ID oluştur
      _pendingFileMessageId = const Uuid().v4();
      _pendingFileMessageTime = DateTime.now().toUtc();

      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
        _currentTransferFileName = result.files.single.name;
      });

      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final uploadService = FileUploadService(
        baseUrl: "https://convoapp.app/api",
        token: authProvider.token ?? "",
      );

      String? downloadUrl = await uploadService.uploadFile(
        file,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          _currentTransferFileName = null;
        });
      }

      if (downloadUrl != null) {
        // ✅ ÖNCEDEN OLUŞTURULMUŞ ID ve ZAMAN ile gönder
        await _handleSendMessage(
          text: result.files.single.name,
          fileUrl: downloadUrl,
          fileSize: fileSize,
        );
      }
    }
    FocusScope.of(context).unfocus();
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
    final String myId = authProvider.currentUser?.userId ?? "";
    final String token = authProvider.token ?? "";

    // ✅ CRITICAL: Dosya mesajı ise pending zamanı kullan, değilse yeni zaman oluştur
    final String messageId = (fileUrl != null && _pendingFileMessageId != null)
        ? _pendingFileMessageId!
        : const Uuid().v4();

    final DateTime sentAt = (fileUrl != null && _pendingFileMessageTime != null)
        ? _pendingFileMessageTime!
        : DateTime.now().toUtc();

    MessageType messageType = MessageType.Text;
    if (fileUrl != null) {
      String ext = messageText.toLowerCase().split('.').last;
      if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
        messageType = MessageType.Image;
      } else if (['mp4', 'mov', 'avi'].contains(ext)) {
        messageType = MessageType.Video;
      } else if (['mp3', 'wav', 'ogg', 'm4a'].contains(ext)) {
        messageType = MessageType.Audio;
      } else {
        messageType = MessageType.Document;
      }
    }

    final Map<String, dynamic> messageDto = {
      "Id": messageId,
      "SenderId": myId,
      "ReceiverId": widget.friendModel.id,
      "Content": messageText,
      "Type": messageType.index,
      "SentAt": sentAt.toIso8601String(),
      "IsRead": false,
      "FileUrl": fileUrl,
      "FileSize": fileSize,
    };

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
      final bool isSaved = await _apiService.messageApi.saveMessageToDb(
        messageDto,
        token,
      );
      chatProvider.addMessage(widget.friendModel.id, messageDto, false);

      if (isSaved) {
        await widget.signalRService.methods!.sendMessage(
          widget.friendModel.id,
          messageText,
          fileUrl ?? "",
          messageType.index.toString(),
          fileSize ?? 0,
          false,
          messageId,
          sentAt.toIso8601String(),
        );

        debugPrint(
          "✅ Mesaj gönderildi - ID: $messageId, SentAt: ${sentAt.toIso8601String()}",
        );

        // ✅ Pending değişkenleri temizle
        if (fileUrl != null) {
          _pendingFileMessageId = null;
          _pendingFileMessageTime = null;
        }
      } else {
        debugPrint("❌ Mesaj veritabanına kaydedilemedi!");
      }
    } catch (e) {
      debugPrint("❌ [HATA] _handleSendMessage: $e");
    }
  }

  String _getMimeType(String fileName) {
    String ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _seekAudio(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> _toggleAudio(String url) async {
    try {
      if (_currentlyPlayingUrl == url) {
        if (_audioPlayer.state == PlayerState.playing) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.resume();
        }
        setState(() {});
      } else {
        await _audioPlayer.stop();
        await _audioPlayer.play(UrlSource(url));
        setState(() {
          _currentlyPlayingUrl = url;
        });
      }
    } catch (e) {
      debugPrint("Ses Hatası: $e");
    }
  }

  Future<void> _startDownload(String url, String fileName) async {
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _currentTransferFileName = fileName;
    });

    try {
      final downloadService = FileDownloadService();
      String? localPath = await downloadService.downloadFile(
        url,
        fileName,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );

      if (localPath != null && mounted) {
        await OpenFilex.open(localPath);
      }
    } catch (e) {
      debugPrint("İndirme Hatası: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _currentTransferFileName = null;
        });
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showFullScreenImage(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Hero(tag: url, child: Image.network(url)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Geçerli image URL kontrolü
    final bool hasValidImage =
        _friendImageUrl != null &&
        _friendImageUrl!.trim().isNotEmpty &&
        _friendImageUrl!.startsWith('http');

    return Scaffold(
      // ✅ Klavye açıldığında içeriği yukarı iter, taşmayı önler
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            UserDetailModal.show(
              context,
              widget.friendModel.id,
              showActions: true,
            );
          },
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage:
                        (hasValidImage && _friendImageUrl != "assets/images/")
                        ? NetworkImage(_friendImageUrl!)
                        : null,
                    child:
                        (!hasValidImage || _friendImageUrl == "assets/images/")
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Consumer<SignalrService>(
                      builder: (context, signalr, child) {
                        final isOnline = signalr.onlineUserIds.contains(
                          widget.friendModel.id.toLowerCase(),
                        );
                        return Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.friendModel.userName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Consumer<ConferenceProvider>(
            builder: (context, conferenceProvider, child) {
              // 🐛 DEBUG LOG
              debugPrint(
                "📹 ChatScreen: isInCall=${conferenceProvider.isInCall}, state=${conferenceProvider.state}",
              );

              // Konferanstayken hiçbir ikon gösterme
              if (conferenceProvider.isInCall) {
                debugPrint("✅ ChatScreen: İkon gizlendi");
                return const SizedBox.shrink();
              }

              debugPrint("📷 ChatScreen: Kamera ikonu gösteriliyor");
              // Konferansta değilken kamera ikonu göster
              return IconButton(
                icon: const Icon(Icons.videocam, size: 28),
                onPressed: () async {
                  final conferenceProv = Provider.of<ConferenceProvider>(
                    context,
                    listen: false,
                  );
                  final authProv = Provider.of<AuthProvider>(
                    context,
                    listen: false,
                  );

                  if (authProv.currentUser == null) return;

                  bool success = await conferenceProv.startNewCall(
                    janusUrl: janus,
                    myId: authProv.currentUser!.userId!,
                    myName: authProv.currentUser!.userName!,
                    targetId: widget.friendModel.id,
                    isGroup: false,
                  );

                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Arama başlatılamadı.")),
                    );
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      // ✅ Alt kısımdaki taşmaları engellemek için SafeArea ile sarmalanmış Column
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, child) {
                  final List<Map<String, dynamic>> rawMessages =
                      chatProvider.chatCache[widget.friendModel.id] ?? [];
                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: rawMessages.length,
                    itemBuilder: (context, index) {
                      final m = rawMessages[rawMessages.length - 1 - index];
                      final String displayContent =
                          m["content"] ?? m["Content"] ?? m["newMessage"] ?? "";
                      final String myId =
                          Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          ).currentUser?.userId ??
                          "";

                      return _buildMessageBubble(
                        ChatMessage(
                          text: displayContent,
                          fileUrl: m["fileUrl"] ?? m["FileUrl"] ?? "",
                          type: ChatMessage.parseType(m["type"] ?? m["Type"]),
                          fileSize: m["fileData"] != null
                              ? (m["fileData"]["fileSize"] ??
                                    m["fileData"]["FileSize"])
                              : (m["fileSize"] ?? m["FileSize"]),
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
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _buildProgressIndicator(),
            _buildInputArea(), // Bu metodun içinde SafeArea ve ConstrainedBox olmalı
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    // ✅ Doğru tarih formatı: HH:mm (saat:dakika)
    final timeText =
        "${message.time.day.toString().padLeft(2, '0')}.${message.time.month.toString().padLeft(2, '0')}.${message.time.year} ${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}";

    // ✅ Dinamik URL kullan
    final bool hasValidImage =
        _friendImageUrl != null &&
        _friendImageUrl!.trim().isNotEmpty &&
        _friendImageUrl!.startsWith('http');

    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isMe)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 4.0),
              child: GestureDetector(
                // 👈 Tıklama algılayıcı eklendi
                onTap: () {
                  // ChatScreen'deki arkadaşın ID'sini gönderiyoruz
                  UserDetailModal.show(
                    context,
                    widget.friendModel.id,
                    showActions: true,
                  );
                },
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      (_friendImageUrl != null &&
                          _friendImageUrl!.startsWith('http') &&
                          _friendImageUrl != "assets/images/")
                      ? NetworkImage(_friendImageUrl!)
                      : null,
                  child:
                      (_friendImageUrl == null ||
                          !_friendImageUrl!.startsWith('http') ||
                          _friendImageUrl == "assets/images/")
                      ? const Icon(Icons.person, size: 18)
                      : null,
                ),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: message.isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () async {},
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
                    child: _buildMessageContent(message),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Text(
                    timeText,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    if (!_isUploading && !_isDownloading) return const SizedBox.shrink();

    final Color themeColor = _isUploading ? Colors.green : Colors.blue;
    final String statusText = _isUploading ? "Yükleniyor" : "İndiriliyor";
    final double progressValue = _isUploading
        ? _uploadProgress
        : _downloadProgress;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                _isUploading ? Icons.cloud_upload : Icons.cloud_download,
                color: themeColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "$statusText: ${_currentTransferFileName ?? 'Dosya...'}",
                  style: TextStyle(
                    color: themeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                "%${(progressValue * 100).toInt()}",
                style: TextStyle(
                  color: themeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progressValue,
              valueColor: AlwaysStoppedAnimation<Color>(themeColor),
              backgroundColor: themeColor.withOpacity(0.1),
              minHeight: 8,
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

    return LayoutBuilder(
      // ✅ YENİ: Parent genişliğini al
      builder: (context, constraints) {
        // ✅ Parent'ın genişliğini kullan (zaten %70 ile sınırlı)
        final double maxContentWidth = constraints.maxWidth;
        final double maxImageWidth =
            maxContentWidth * 0.9; // İç margin için %90
        final double maxSliderWidth = maxContentWidth * 0.7; // Slider için %70

        return IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  if (_isFileType(url, message.type, [
                    'jpg',
                    'jpeg',
                    'png',
                    'gif',
                    'webp',
                  ])) {
                    _showFullScreenImage(context, url);
                  } else if (_isFileType(url, message.type, [
                    'mp4',
                    'mov',
                    'avi',
                  ])) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoPlayerPage(url: url),
                      ),
                    );
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isFileType(url, message.type, [
                      'jpg',
                      'jpeg',
                      'png',
                      'gif',
                      'webp',
                    ]))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Hero(
                          tag: url,
                          child: Image.network(
                            url,
                            width: maxImageWidth, // ✅ Parent'a göre sınırlandı
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image, size: 50),
                          ),
                        ),
                      )
                    else if (_isFileType(url, message.type, [
                      'mp4',
                      'mov',
                      'avi',
                    ]))
                      Container(
                        width: maxImageWidth, // ✅ Parent'a göre sınırlandı
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
                  ],
                ),
              ),
              if (_isFileType(url, message.type, ['mp3', 'wav', 'm4a', 'ogg']))
                _buildAudioContent(message, url, isMe, maxSliderWidth),
              if (!_isFileType(url, message.type, [
                'jpg',
                'jpeg',
                'png',
                'gif',
                'webp',
                'mp4',
                'mov',
                'avi',
                'mp3',
                'wav',
                'm4a',
                'ogg',
              ]))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      color: isMe ? Colors.white : Colors.grey[700],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message.text,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _startDownload(url, message.text),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.white.withOpacity(0.15)
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.file_download,
                            size: 16,
                            color: isMe ? Colors.white : Colors.blue.shade700,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            "İndir",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isMe ? Colors.white : Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (message.fileSize != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            _formatFileSize(message.fileSize!),
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _togglePlaybackRate() async {
    double newRate;
    if (_playbackRate == 1.0) {
      newRate = 1.5;
    } else if (_playbackRate == 1.5) {
      newRate = 2.0;
    } else {
      newRate = 1.0;
    }

    await _audioPlayer.setPlaybackRate(newRate);
    setState(() {
      _playbackRate = newRate;
    });
  }

  // ✅ YENİ PARAMETRE: maxSliderWidth
  Widget _buildAudioContent(
    ChatMessage message,
    String url,
    bool isMe,
    double maxSliderWidth,
  ) {
    final bool isThisAudio = _currentlyPlayingUrl == url;

    IconData playIcon = Icons.play_circle_filled;
    if (isThisAudio && _audioPlayer.state == PlayerState.playing) {
      playIcon = Icons.pause_circle_filled;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            playIcon,
            color: isMe ? Colors.white : Colors.blue,
            size: 35,
          ),
          onPressed: () => _toggleAudio(url),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (isThisAudio)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          SizedBox(
                            width: maxSliderWidth, // ✅ SABİT 130 YERİNE DİNAMİK
                            height: 20,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                trackHeight: 2,
                              ),
                              child: Slider(
                                activeColor: isMe ? Colors.white : Colors.blue,
                                inactiveColor: isMe
                                    ? Colors.white24
                                    : Colors.black12,
                                min: 0,
                                max: _duration.inMilliseconds.toDouble() > 0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 1.0,
                                value: _position.inMilliseconds
                                    .toDouble()
                                    .clamp(
                                      0,
                                      _duration.inMilliseconds.toDouble(),
                                    ),
                                onChanged: (value) => _seekAudio(
                                  Duration(milliseconds: value.toInt()),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _togglePlaybackRate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "${_playbackRate}x",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isMe ? Colors.white : Colors.blue,
                          ),
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
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

  Future<void> _checkAndAcceptIncomingCall() async {
    if (!mounted) return;

    final conferenceProvider = Provider.of<ConferenceProvider>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    debugPrint("═══════════════════════════════════════");
    debugPrint("🔍 P2P: _checkAndAcceptIncomingCall çağrıldı");
    debugPrint("   hasIncomingCall: ${conferenceProvider.hasIncomingCall}");
    debugPrint("   incomingCallData: ${conferenceProvider.incomingCallData}");
    debugPrint("   widget.friendModel.id: ${widget.friendModel.id}");
    debugPrint("═══════════════════════════════════════");

    // Gelen arama varsa ve bu arkadaştan ise
    if (conferenceProvider.hasIncomingCall) {
      final callData = conferenceProvider.incomingCallData;
      final starterId = callData?['starterId']?.toString();
      final isGroup = callData?['isGroup'] ?? false;

      debugPrint("📞 Gelen arama var!");
      debugPrint("   starterId: $starterId");
      debugPrint("   isGroup: $isGroup");
      debugPrint("   Eşleşme kontrolü: ${starterId == widget.friendModel.id}");

      // P2P call ve bu arkadaştan geliyorsa
      if (!isGroup && starterId == widget.friendModel.id) {
        debugPrint("✅ Eşleşme BAŞARILI, otomatik katılım başlıyor...");

        await conferenceProvider.acceptIncomingCall(
          janusUrl: janus,
          myId: authProvider.currentUser?.userId ?? "",
          myName: authProvider.currentUser?.userName ?? "Kullanıcı",
        );
      } else {
        debugPrint("❌ Eşleşme BAŞARISIZ!");
        debugPrint(
          "   Sebep: isGroup=$isGroup, starterId match=${starterId == widget.friendModel.id}",
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
      final dbMessages = await _apiService.messageApi.getMessagesFromDb(
        auth.currentUser!.userId!,
        widget.friendModel.id,
        auth.token!,
      );
      if (mounted && dbMessages.isNotEmpty) {
        chatProvider.syncMessages(widget.friendModel.id, dbMessages);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("❌ P2P Sync Hatası: $e");
    }
  }

  @override
  void dispose() {
    _appResumedSubscription?.cancel();
    _profileUpdateSubscription?.cancel(); // ✅ YENİ: Subscription'ı temizle
    _audioPlayer.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _profileUpdateSubscription?.cancel();
    super.dispose();
  }
}
