import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/conference_provider.dart';
import '../providers/chat_provider.dart';
import '../services/auth_provider.dart';

class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // 🚀 Consumer2 ile hem konferans hem de sohbet verilerini dinliyoruz
    return Consumer2<ConferenceProvider, ChatProvider>(
      builder: (context, confProv, chatProv, child) {
        // Aktif bir gelen arama yoksa görünmez kal
        if (!confProv.hasIncomingCall) return const SizedBox.shrink();

        final authProv = Provider.of<AuthProvider>(context, listen: false);
        final callData = confProv.incomingCallData;

        // 📋 Arama verilerini ve tipini belirle
        final bool isGroup =
            callData?['isGroup'] ?? (callData?['type'] == 'group_started');
        final String? groupId = callData?['groupId']?.toString();
        final String? starterId = callData?['starterId']?.toString();

        // 🔍 Görüntülenecek ismi belirle (Grup adı veya Arkadaş adı)
        String displayName = "Bilinmeyen Arama";

        if (isGroup && groupId != null) {
          // Grup aramasıysa ChatProvider'dan grup ismini çek
          displayName = chatProv.getGroupName(groupId);
        } else if (starterId != null) {
          // 🚀 P2P aramasıysa ChatProvider'daki isim belleğinden (cache) arkadaş ismini bul
          displayName = chatProv.getUserOrGroupName(starterId, isGroup: false);
        }

        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 10,
          right: 10,
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(16),
            color: Colors.grey[900],
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.video_call, color: Colors.blue, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGroup ? "Grup Konferansı" : "Gelen Arama",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          displayName, // 🚀 ID yerine artık arkadaş/grup adı gözüküyor
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // ✅ Kabul Et Butonu
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.green, size: 30),
                    onPressed: () async {
                      bool success = await confProv.acceptIncomingCall(
                        janusUrl: "ws://convoapp.app:8188",
                        myId: authProv.currentUser?.userId ?? "",
                        myName: authProv.currentUser?.userName ?? "Kullanıcı",
                      );

                      if (success) {
                        debugPrint("✅ Arama kabul edildi ve bağlanıldı.");
                      }
                    },
                  ),
                  // ❌ Reddet Butonu
                  IconButton(
                    icon: const Icon(
                      Icons.call_end,
                      color: Colors.red,
                      size: 30,
                    ),
                    onPressed: () => confProv.declineCall(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
