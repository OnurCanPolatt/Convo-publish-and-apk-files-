import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat_list_item.dart';
import '../models/chat_room_model.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/signalr/signalr_service.dart';
import '../services/profile_service.dart';
import '../widgets/fullscreen_image_page.dart';
import '../widgets/user_detail_modal.dart';

class GroupScreen extends StatefulWidget {
  final String groupId;
  const GroupScreen({super.key, required this.groupId});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final ApiService _apiService = ApiService();
  late ProfileService _profileService;

  ChatRoomModel? groupInfo;
  bool isLoading = true;
  bool isCurrentUserAdmin = false;

  final Map<String, String?> _memberImages = {};

  bool isEditingName = false;
  bool isEditingDescription = false;
  late TextEditingController _nameController;
  late TextEditingController _descController;

  StreamSubscription<Map<String, dynamic>>? _signalrSubscription;

  @override
  void initState() {
    super.initState();
    _profileService = ProfileService(Dio());
    _nameController = TextEditingController();
    _descController = TextEditingController();
    _setupSignalRListener();
    _loadGroupData();
  }

  // ✅ Düzeltilmiş ve Eksiksiz _setupSignalRListener Metodu
  void _setupSignalRListener() {
    final signalr = context.read<SignalrService>();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final String myId = authProvider.currentUser?.userId ?? "";

    _signalrSubscription = signalr.friendEventStream.listen((event) async {
      if (!mounted) return;

      final type = event['type'];
      final eventGroupId = event['groupId']?.toString();
      final eventUserId = event['userId']?.toString();

      // 🚀 ÜYE BİLGİSİ GÜNCELLEME KONTROLÜ
      if (type == 'InfoUpdated' || type == 'ReceiveUserInfoUpdated') {
        // Eğer güncellenen kişi grubun üyelerinden biriyse
        bool isMember =
            groupInfo?.members.any(
              (m) => m.userId.toLowerCase() == eventUserId?.toLowerCase(),
            ) ??
            false;

        if (isMember && eventUserId != null) {
          debugPrint(
            "📡 GroupInfo: Üye $eventUserId güncellendi, veriler tazeleniyor...",
          );
          // Resim cache listesinden bu kullanıcıyı sil ki yeni resmi çekebilsin
          _memberImages.remove(eventUserId);
          await _loadGroupData(); // 🔄 Tüm grup verisini ve yeni üye isimlerini tekrar çek
        }
      }

      // 🚪 GRUPTAN ATILMA/AYRILMA KONTROLÜ
      if (type == 'UserLeftGroup') {
        if (eventGroupId == widget.groupId &&
            eventUserId?.toLowerCase() == myId.toLowerCase()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
      }

      // 🔄 GENEL GRUP GÜNCELLEMELERİ
      if (type == 'GroupInfoUpdated' && eventGroupId == widget.groupId) {
        _loadGroupData();
      }
    });
  }

  @override
  void dispose() {
    _signalrSubscription?.cancel();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupData() async {
    debugPrint("🔄 Grup verileri yükleniyor: ${widget.groupId}");
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final token = authProv.token ?? "";
    final myId = authProv.currentUser?.userId;

    try {
      final data = await _apiService.group.getFreshGroupInfo(
        widget.groupId,
        token,
      );

      if (data != null) {
        if (mounted) {
          setState(() {
            groupInfo = data;
            _nameController.text = groupInfo!.name ?? '';
            _descController.text = groupInfo!.description ?? '';

            // 1. Gruptaki kendi üyelik nesnemizi bulalım
            final me = groupInfo!.members.firstWhere(
              (m) => m.userId.toLowerCase() == myId?.toLowerCase(),
              orElse: () => ChatRoomMemberModel(
                userId: "",
                role: 0,
                joinedAt: DateTime.now(),
              ),
            );

            // 🚀 2. YETKİ KONTROLÜ (GÜNCELLENDİ)
            // Backend Enum: Member=0, Admin=1, Owner=2
            // Eğer rolümüz 1 veya 2 ise VEYA grubun kurucusu bizsek yetkiliyizdir.
            isCurrentUserAdmin =
                (me.role == 1 ||
                me.role == 2 ||
                groupInfo!.createdByUserId == myId);

            debugPrint("🔐 Giriş Yapan ID: $myId");
            debugPrint("🔐 Grubun Kurucusu ID: ${groupInfo!.createdByUserId}");
            debugPrint(
              "🔐 Benim Rolüm: ${me.role} | Yetkim: $isCurrentUserAdmin",
            );

            isLoading = false;
          });
          _loadMemberImages(token);
        }
      }
    } catch (e) {
      debugPrint("❌ Grup yükleme hatası: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _loadMemberImages(String token) async {
    if (groupInfo == null) return;
    for (var member in groupInfo!.members) {
      if (!_memberImages.containsKey(member.userId)) {
        try {
          final url = await _profileService.getProfileImageUrl(
            member.userId,
            token,
          );
          if (mounted) setState(() => _memberImages[member.userId] = url);
        } catch (e) {
          debugPrint("⚠️ Fotoğraf yüklenemedi: ${member.userId}");
        }
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    if (!isCurrentUserAdmin) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (pickedFile != null) {
      final authProv = Provider.of<AuthProvider>(context, listen: false);
      debugPrint("📸 Fotoğraf yükleniyor...");
      String? newUrl = await _apiService.group.uploadGroupImage(
        File(pickedFile.path),
        widget.groupId,
        authProv.token!,
      );

      if (newUrl != null) {
        bool dbOk = await _apiService.group.updateGroupInfo(
          widget.groupId,
          _nameController.text,
          _descController.text,
          authProv.token!,
          imageUrl: newUrl,
        );

        if (dbOk) {
          await Future.delayed(const Duration(seconds: 1));
          await _loadGroupData();
          _notifyGroupUpdate();
        }
      }
    }
  }

  void _notifyGroupUpdate() {
    context.read<SignalrService>().methods?.groupInfoUpdated(widget.groupId);
  }

  Future<void> _saveChanges() async {
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    bool ok = await _apiService.group.updateGroupInfo(
      widget.groupId,
      _nameController.text,
      _descController.text,
      authProv.token!,
      imageUrl: groupInfo?.imageUrl,
    );

    if (ok) {
      setState(() {
        isEditingName = false;
        isEditingDescription = false;
      });
      await _loadGroupData();
      _notifyGroupUpdate();
    }
  }

  Future<void> _changeRole(
    ChatRoomMemberModel member,
    bool shouldBeAdmin,
  ) async {
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    bool ok = await _apiService.group.updateMemberRole(
      widget.groupId,
      member.userId,
      shouldBeAdmin,
      authProv.token!,
    );
    if (ok) {
      await _loadGroupData();
      _notifyGroupUpdate();
    }
  }

  Future<void> _leaveGroup() async {
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    bool ok = await _apiService.group.leaveGroup(
      widget.groupId,
      authProv.currentUser!.userId!,
      authProv.token!,
    );
    if (ok) {
      _notifyGroupUpdate();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _deleteGroup() async {
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    bool ok = await _apiService.group.deleteGroup(
      widget.groupId,
      authProv.token!,
    );
    if (ok) {
      _notifyGroupUpdate();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showAddMemberModal() async {
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final token = authProv.token!;
    final List<UserItem> myFriends = await _apiService.beginApi.getMyFriends(
      authProv.currentUser!.userId!,
      token,
    );
    final existingMemberIds = groupInfo!.members.map((m) => m.userId).toSet();
    final addableFriends = myFriends
        .where((f) => !existingMemberIds.contains(f.id))
        .toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          for (var friend in addableFriends) {
            if (friend.imageUrl == null) {
              _apiService.profile.getProfileImageUrl(friend.id, token).then((
                url,
              ) {
                if (url != null && mounted)
                  setModalState(() => friend.imageUrl = url);
              });
            }
          }
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  "Gruba Üye Ekle",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                Expanded(
                  child: addableFriends.isEmpty
                      ? const Center(
                          child: Text("Eklenecek yeni arkadaş bulunamadı."),
                        )
                      : ListView.builder(
                          itemCount: addableFriends.length,
                          itemBuilder: (context, index) {
                            final friend = addableFriends[index];
                            final bool hasImg =
                                friend.imageUrl != null &&
                                friend.imageUrl!.startsWith('http');
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: hasImg
                                    ? NetworkImage(friend.imageUrl!)
                                    : null,
                                child: !hasImg
                                    ? Text(friend.name[0].toUpperCase())
                                    : null,
                              ),
                              title: Text(friend.name),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.add_circle,
                                  color: Colors.green,
                                ),
                                onPressed: () async {
                                  bool ok = await _apiService.group
                                      .addMembersToGroup(widget.groupId, [
                                        friend.id,
                                      ], token);
                                  if (ok) {
                                    Navigator.pop(ctx);
                                    await _loadGroupData();
                                    _notifyGroupUpdate();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmAction(String message, Function action) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Onay"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              action();
            },
            child: const Text("Evet", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Grup Bilgileri"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            _buildInfoSection(),
            _buildMembersList(),
            const SizedBox(height: 20),
            _buildActionButtons(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Geçerli bir resim olup olmadığının kontrolü
    final bool hasValidImage =
        groupInfo?.imageUrl != null && groupInfo!.imageUrl!.startsWith('http');

    // Önbelleği kırmak için timestamp eklenmiş URL
    final String imageUrl = hasValidImage
        ? "${groupInfo!.imageUrl}?t=${DateTime.now().millisecondsSinceEpoch}"
        : "";

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Stack(
            children: [
              // 🚀 1. GRUP FOTOĞRAFI: Tıklanınca TAM EKRAN açılır
              GestureDetector(
                onTap: () {
                  if (hasValidImage) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullscreenImagePage(
                          imageUrl: imageUrl,
                          tag:
                              'group_image_${widget.groupId}', // Benzersiz Hero etiketi
                        ),
                      ),
                    );
                  }
                },
                child: Hero(
                  tag: 'group_image_${widget.groupId}',
                  child: CircleAvatar(
                    radius: 55,
                    backgroundImage: hasValidImage
                        ? NetworkImage(imageUrl)
                        : null,
                    child: !hasValidImage
                        ? const Icon(Icons.group, size: 55)
                        : null,
                  ),
                ),
              ),
              // 🚀 2. KAMERA İKONU: Tıklanınca FOTOĞRAF SEÇME/YÜKLEME açılır
              if (isCurrentUserAdmin)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap:
                        _pickAndUploadImage, // Kamera ikonuna özel tetikleyici
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: const Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 15),
          // GRUP ADI DÜZENLEME VE GÖRÜNTÜLEME ALANI
          isEditingName
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Grup Adı",
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: _saveChanges,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => isEditingName = false),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        groupInfo?.name ?? "",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentUserAdmin)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => setState(() => isEditingName = true),
                      ),
                  ],
                ),
          Text(
            "${groupInfo?.members.length ?? 0} Katılımcı",
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    // 🚀 Tarih formatlama (Örn: 2024-05-20T10:00 -> 20.05.2024)
    String formattedDate = "Bilinmiyor";
    if (groupInfo?.createdAt != null) {
      final date = groupInfo!.createdAt!;
      formattedDate =
          "${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}";
    }

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            title: const Text(
              "Açıklama",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            subtitle: isEditingDescription
                ? TextField(controller: _descController, maxLines: null)
                : Text(groupInfo?.description ?? "Açıklama yok"),
            trailing: isCurrentUserAdmin
                ? IconButton(
                    icon: Icon(isEditingDescription ? Icons.check : Icons.edit),
                    onPressed: () => isEditingDescription
                        ? _saveChanges()
                        : setState(() => isEditingDescription = true),
                  )
                : null,
          ),
        ),
        // 🚀 YENİ: Oluşturulma Tarihi Bilgisi
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                "Grup oluşturulma tarihi: $formattedDate",
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMembersList() {
    final myId = context.read<AuthProvider>().currentUser?.userId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Katılımcılar",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              if (isCurrentUserAdmin)
                TextButton.icon(
                  onPressed: _showAddMemberModal,
                  icon: const Icon(Icons.person_add),
                  label: const Text("Ekle"),
                ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: groupInfo?.members.length ?? 0,
          itemBuilder: (context, index) {
            final member = groupInfo!.members[index];
            final bool isMe =
                member.userId.toLowerCase() == myId?.toLowerCase();

            final bool isOwner =
                member.role == 2 || member.userId == groupInfo!.createdByUserId;
            final bool isAdmin = member.role == 1;

            final String? memberUrl = _memberImages[member.userId];
            final bool hasImg =
                memberUrl != null && memberUrl.startsWith('http');

            return ListTile(
              leading: GestureDetector(
                onTap: () {
                  // 🚀 DEĞİŞİKLİK: Eğer bu kişi BENSEM butonları gösterme
                  UserDetailModal.show(
                    context,
                    member.userId,
                    showActions: !isMe, // Eğer bensem false, başkasıysa true
                  );
                },
                child: CircleAvatar(
                  backgroundImage: hasImg ? NetworkImage(memberUrl) : null,
                  child: !hasImg ? const Icon(Icons.person) : null,
                ),
              ),
              title: GestureDetector(
                onTap: () {
                  // 🚀 DEĞİŞİKLİK: Aynı mantığı buraya da ekliyoruz
                  UserDetailModal.show(
                    context,
                    member.userId,
                    showActions: !isMe,
                  );
                },
                child: Text(
                  isMe
                      ? "${member.userName} (Siz)"
                      : (member.userName ?? "Kullanıcı"),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              subtitle: Text(isOwner ? "Kurucu" : (isAdmin ? "Admin" : "Üye")),
              trailing: (isCurrentUserAdmin && !isMe && member.role != 2)
                  ? _buildMemberMenu(member)
                  : (isOwner
                        ? const Icon(Icons.star, color: Colors.amber, size: 20)
                        : null),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMemberMenu(ChatRoomMemberModel member) {
    // 0: Member, 1: Admin, 2: Owner
    final bool isMemberCurrentlyAdmin = member.role == 1;

    return PopupMenuButton<String>(
      onSelected: (val) async {
        if (val == 'role') {
          await _changeRole(member, !isMemberCurrentlyAdmin);
        } else if (val == 'remove') {
          _confirmAction("${member.userName} gruptan çıkarılsın mı?", () async {
            final token = context.read<AuthProvider>().token!;
            bool ok = await _apiService.group.leaveGroup(
              widget.groupId,
              member.userId,
              token,
            );
            if (ok) {
              await _loadGroupData();
              _notifyGroupUpdate();
            }
          });
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'role',
          child: Text(isMemberCurrentlyAdmin ? "Üyeliğe Düşür" : "Admin Yap"),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: Text("Gruptan At", style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    final myId = context.read<AuthProvider>().currentUser?.userId;
    final bool isOwner = groupInfo?.createdByUserId == myId;
    return Column(
      children: [
        const Divider(),
        ListTile(
          leading: const Icon(Icons.exit_to_app, color: Colors.red),
          title: const Text(
            "Gruptan Ayrıl",
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          onTap: () => _confirmAction(
            "Gruptan ayrılmak istediğinize emin misiniz?",
            _leaveGroup,
          ),
        ),
        if (isOwner)
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              "Grubu Sil",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () => _confirmAction(
              "Bu grubu silmek istediğinize emin misiniz?",
              _deleteGroup,
            ),
          ),
      ],
    );
  }
}
