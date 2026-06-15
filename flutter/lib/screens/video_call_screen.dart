import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/conference_provider.dart';
import '../services/janus/video_room_service.dart';

class VideoCallOverlay extends StatefulWidget {
  const VideoCallOverlay({super.key});

  @override
  State<VideoCallOverlay> createState() => _VideoCallOverlayState();
}

class _VideoCallOverlayState extends State<VideoCallOverlay> {
  bool isMinimized = false;
  int? selectedFeedId;
  bool manualSelection = false;
  bool isMicOpen = true;
  bool isCamOpen = true;
  Offset offset = const Offset(20, 100);

  @override
  void initState() {
    super.initState();
    // WidgetsBinding kullanarak BuildContext hazır olduğunda çalıştırıyoruz
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final conferenceProv = Provider.of<ConferenceProvider>(
        context,
        listen: false,
      );

      // ✅ YENİ: Callback'leri bağlayalım
      if (conferenceProv.videoService != null) {
        // Biri katıldığında VEYA birinin durumu değiştiğinde (onMute gibi) ekranı yenile
        conferenceProv.videoService!.onRemoteJoined = (id, renderer) {
          if (mounted) {
            debugPrint(
              "🔄 UI Yenileniyor: $id kullanıcısının görüntü durumu değişti.",
            );
            setState(() {});
          }
        };

        // Biri ayrıldığında ekranı yenile
        conferenceProv.videoService!.onRemoteLeft = (id) {
          if (mounted) setState(() {});
        };
      }

      conferenceProv.addListener(_handleCallEnd);
    });
  }

  void _handleCallEnd() {
    if (!mounted) return;
    final conferenceProv = Provider.of<ConferenceProvider>(
      context,
      listen: false,
    );
    if (!conferenceProv.isInCall) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conferenceProv = Provider.of<ConferenceProvider>(context);
    final videoService = conferenceProv.videoService;

    if (videoService == null || !conferenceProv.isInCall) {
      return const SizedBox.shrink();
    }
    videoService.onRemoteJoined = (id, renderer) {
      if (mounted) {
        debugPrint(
          "🔄 UI Yenileniyor: $id kullanıcısı için karartma/açma tetiklendi.",
        );
        setState(() {});
      }
    };
    videoService.onLocalStreamReady = () {
      if (mounted) setState(() {});
    };

    if (isMinimized) {
      return Positioned(
        left: offset.dx,
        top: offset.dy,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              final screenSize = MediaQuery.of(context).size;
              const double windowWidth = 120;
              const double windowHeight = 180;
              Offset newOffset = offset + details.delta;
              double dx = newOffset.dx.clamp(
                0.0,
                screenSize.width - windowWidth,
              );
              double dy = newOffset.dy.clamp(
                0.0,
                screenSize.height - windowHeight,
              );
              offset = Offset(dx, dy);
            });
          },
          onDoubleTap: () => setState(() => isMinimized = false),
          child: _buildMiniWindow(videoService),
        ),
      );
    }

    // --- TAM EKRAN MANTIĞI ---
    final remoteEntries = videoService.remoteRenderers.entries.toList();
    RTCVideoRenderer mainRenderer;

    if (!manualSelection && remoteEntries.isNotEmpty) {
      mainRenderer = remoteEntries.last.value;
      selectedFeedId = remoteEntries.last.key;
    } else if (selectedFeedId != null &&
        videoService.remoteRenderers.containsKey(selectedFeedId)) {
      mainRenderer = videoService.remoteRenderers[selectedFeedId]!;
    } else {
      mainRenderer = videoService.localRenderer;
      selectedFeedId = null;
    }

    List<MapEntry<int?, RTCVideoRenderer>> thumbnailList = [];
    if (remoteEntries.isNotEmpty) {
      if (selectedFeedId != null) {
        thumbnailList.add(MapEntry(null, videoService.localRenderer));
      }
      for (var entry in remoteEntries) {
        if (entry.key != selectedFeedId) {
          thumbnailList.add(MapEntry(entry.key, entry.value));
        }
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. ANA VİDEO (Aynalama Sorunu Çözüldü)
          Positioned.fill(
            child: () {
              // 1. Durum: Ana ekranda (arkada) BEN varım
              if (mainRenderer == videoService.localRenderer) {
                if (!isCamOpen) {
                  return _buildBlackScreen(
                    "Kameranız Kapalı",
                    Icons.videocam_off,
                  );
                }
                if (mainRenderer.srcObject == null) {
                  return _buildBlackScreen(
                    "Kamera Başlatılıyor...",
                    Icons.sync,
                  );
                }
              }
              // 2. Durum: Ana ekranda (arkada) BAŞKASI var
              else {
                if (mainRenderer.srcObject == null) {
                  return _buildBlackScreen(
                    "Görüntü Bekleniyor...",
                    Icons.hourglass_empty,
                  );
                }
              }

              // Görüntü varsa göster (ValueKey ile donma engellendi)
              return RTCVideoView(
                mainRenderer,
                key: ValueKey(
                  'main_${mainRenderer.textureId}_${mainRenderer.srcObject?.id ?? 'none'}',
                ),
                mirror:
                    mainRenderer == videoService.localRenderer &&
                    videoService.isFrontCamera,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              );
            }(),
          ),

          // ÜST LİSTE (KATILIMCILAR)
          if (thumbnailList.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 10,
              right: 10,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: thumbnailList
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _buildThumbnail(entry, videoService),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),

          // KONTROLLER VE KÜÇÜLTME BUTONU
          _buildUIControls(conferenceProv, videoService),
        ],
      ),
    );
  }

  Widget _buildBlackScreen(String label, IconData icon) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 50),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildMiniWindow(VideoRoomService videoService) {
    final RTCVideoRenderer activeRenderer =
        videoService.remoteRenderers.isNotEmpty
        ? videoService.remoteRenderers.values.first
        : videoService.localRenderer;

    final bool showingLocal = videoService.remoteRenderers.isEmpty;

    return Container(
      width: 120,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white38, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 15, color: Colors.black54)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            Builder(
              builder: (context) {
                bool shouldShowBlack = false;
                String label = "Kamera Kapalı";

                if (showingLocal) {
                  if (!isCamOpen) {
                    shouldShowBlack = true;
                  } else if (activeRenderer.srcObject == null) {
                    shouldShowBlack = true;
                    label = "Başlatılıyor...";
                  }
                } else {
                  shouldShowBlack = (activeRenderer.srcObject == null);
                  label = "Bağlanıyor...";
                }

                if (shouldShowBlack) {
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_off,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RTCVideoView(
                  activeRenderer,
                  key: ValueKey(
                    'mini_${activeRenderer.textureId}_${activeRenderer.srcObject?.id ?? 'none'}',
                  ),
                  mirror: showingLocal && videoService.isFrontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                );
              },
            ),
            const Positioned(
              top: 5,
              right: 5,
              child: Icon(
                Icons.drag_indicator,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(
    MapEntry<int?, RTCVideoRenderer> entry,
    VideoRoomService videoService,
  ) {
    final bool isMe = entry.key == null;
    final renderer = entry.value;

    return GestureDetector(
      onTap: () => setState(() {
        selectedFeedId = entry.key;
        manualSelection = true;
      }),
      child: Container(
        width: 90,
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedFeedId == entry.key ? Colors.blue : Colors.white54,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Builder(
            builder: (context) {
              bool shouldShowBlack = false;
              String statusLabel = "Kapalı";

              if (isMe) {
                if (!isCamOpen) {
                  shouldShowBlack = true;
                } else if (renderer.srcObject == null) {
                  shouldShowBlack = true;
                  statusLabel = "Başlatılıyor...";
                }
              } else {
                shouldShowBlack = (renderer.srcObject == null);
                statusLabel = "Bağlanıyor...";
              }

              if (shouldShowBlack) {
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_off,
                          color: Colors.white24,
                          size: 24,
                        ),
                        Text(
                          statusLabel,
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return RTCVideoView(
                renderer,
                key: ValueKey(
                  'thumb_${renderer.textureId}_${renderer.srcObject?.id ?? 'none'}',
                ),
                mirror: isMe && videoService.isFrontCamera,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUIControls(
    ConferenceProvider conferenceProv,
    VideoRoomService videoService,
  ) {
    return Stack(
      children: [
        // Küçültme Butonu
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          right: 20,
          child: CircleAvatar(
            backgroundColor: Colors.black45,
            child: IconButton(
              icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
              onPressed: () {
                setState(() => isMinimized = true);
                // ❌ Navigator.pop KALDIRILDI - Artık dispose edilmiyor
                debugPrint("📦 Minimize edildi, arka planda kalıyor");
              },
            ),
          ),
        ),
        // 2. Alt Kontrol Barı (Taşma Sorunu Çözüldü)
        Positioned(
          // Cihazın altındaki güvenli alanı (çentik/nav bar) dinamik olarak hesaplar
          bottom: 20 + MediaQuery.of(context).padding.bottom,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _circleBtn(Icons.switch_camera, () async {
                // 3. Kamera Değişimi (Ayna durumunu güncellemek için setState eklendi)
                await videoService.switchCamera();
                setState(() {});
              }),
              _circleBtn(
                isCamOpen ? Icons.videocam : Icons.videocam_off,
                () {
                  setState(() => isCamOpen = !isCamOpen);
                  videoService.toggleVideo(isCamOpen);
                },
                color: isCamOpen ? Colors.white24 : Colors.orange,
              ),
              _circleBtn(Icons.call_end, () async {
                await conferenceProv.leaveConference();
              }, color: Colors.red),
              _circleBtn(
                isMicOpen ? Icons.mic : Icons.mic_off,
                () {
                  setState(() => isMicOpen = !isMicOpen);
                  videoService.toggleAudio(isMicOpen);
                },
                color: isMicOpen ? Colors.white24 : Colors.orange,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: color ?? Colors.white24,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}
