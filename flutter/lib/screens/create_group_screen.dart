// lib/screens/create_group.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';
import 'package:uuid/uuid.dart'; // UserItem burada tanımlı
import 'package:my_first_flutterapp/models/chat_list_item.dart';

import '../services/signalr/signalr_service.dart';

class CreateGroupScreen extends StatefulWidget {
  final List<UserItem> selectedUsers;
  final List<UserItem> allFriends;

  const CreateGroupScreen({
    super.key,
    required this.selectedUsers,
    required this.allFriends,
  });

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();

  File? _groupImage;
  final ImagePicker _picker = ImagePicker();

  String _groupName = '';
  String _groupDescription = '';
  bool _isCreating = false;

  late List<UserItem> _currentMembers;

  @override
  void initState() {
    super.initState();
    _currentMembers = List.from(widget.selectedUsers);
  }

  // --- Yardımcı Widget: Profil Fotoğrafı Oluşturucu ---
  Widget _buildUserAvatar(UserItem user, {double radius = 20}) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.shade50,
      child: (user.imageUrl != null && user.imageUrl!.isNotEmpty)
          ? ClipOval(
              child: Image.network(
                user.imageUrl!,
                fit: BoxFit.cover,
                width: radius * 2,
                height: radius * 2,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.person, color: Colors.deepPurple, size: radius),
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
              ),
            )
          : Icon(Icons.person, color: Colors.deepPurple, size: radius),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _groupImage = File(image.path);
      });
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isCreating = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final String token = authProvider.token ?? "";
      final String myId = authProvider.currentUser?.userId ?? "";

      // 1. WEB İLE UYUMLU ID VE TARİH OLUŞTURMA
      final String newGroupId = const Uuid().v4();
      String uploadedImageUrl = "";

      // 2. FOTOĞRAFI YÜKLE (Eğer seçildiyse)
      if (_groupImage != null) {
        debugPrint("📸 Grup fotoğrafı yükleniyor...");
        final String? responseUrl = await _apiService.group.uploadGroupImage(
          _groupImage!,
          newGroupId,
          token,
        );

        if (responseUrl != null) {
          uploadedImageUrl = responseUrl;
        }
      }

      // 3. PAYLOAD HAZIRLA
      final Map<String, dynamic> groupPayload = {
        "Id": newGroupId,
        "Name": _groupName.trim(),
        "Description": _groupDescription.trim().isEmpty
            ? null
            : _groupDescription.trim(),
        "Type": 1,
        "CreatedByUserId": myId,
        "CreatedAt": DateTime.now().toUtc().toIso8601String(),
        "IsActive": true,
        "ImageUrl": uploadedImageUrl,
        "Members": [
          {
            "UserId": myId,
            "Role": 2, // ✅ DOĞRU! Kurucu Owner (2) olmalı
            "IsActive": true,
            "JoinedAt": DateTime.now().toUtc().toIso8601String(),
          },
          ..._currentMembers.map(
            (m) => {
              "UserId": m.id,
              "Role": 0, // Diğer üyeler Member (0) olarak eklenir
              "IsActive": true,
              "JoinedAt": DateTime.now().toUtc().toIso8601String(),
            },
          ),
        ],
      };

      // 4. GRUBU OLUŞTUR
      final bool success = await _apiService.group.createGroup(
        groupPayload,
        token,
      );

      if (success && mounted) {
        // ✅ FIX: Grup oluşturulduktan sonra SignalR grubuna katıl!
        debugPrint(
          "✅ Grup oluşturuldu, SignalR grubuna katılınıyor: $newGroupId",
        );

        final signalRService = context.read<SignalrService>();
        final joinSuccess = await signalRService.methods?.joinMultipleGroups([
          newGroupId,
        ]);

        if (joinSuccess == true) {
          debugPrint(
            "✅ SignalR: Yeni oluşturulan gruba başarıyla katıldı: $newGroupId",
          );
        } else {
          debugPrint("⚠️ SignalR: Gruba katılma başarısız oldu: $newGroupId");
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grup başarıyla oluşturuldu!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("❌ Grup Oluşturma Hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showAddMembersModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled:
          true, // Uzun listelerde modalın yukarı kaymasını sağlar
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // ✅ StatefulBuilder: Modal açıkken birini eklediğinde listenin anlık güncellenmesi için şarttır
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // 1. Mevcut üyelerin ID'lerini normalize et (Küçük harf + Boşluk silme)
            final currentIds = _currentMembers
                .map((m) => m.id.toLowerCase().trim())
                .toSet();

            // 2. Tüm arkadaşlar listesinden, ID'si mevcut üyelerde olmayanları filtrele
            final availableFriends = widget.allFriends.where((f) {
              // Listenizdeki arkadaşın ID'sini de normalize edin
              final friendId = f.id.toLowerCase().trim();
              // Eğer bu ID seçili üyeler (currentIds) içinde YOKSA göster
              return !currentIds.contains(friendId);
            }).toList();

            return Container(
              padding: const EdgeInsets.all(16),
              height:
                  MediaQuery.of(context).size.height *
                  0.7, // Ekranın %70'ini kaplar
              child: Column(
                children: [
                  const Text(
                    "Arkadaş Ekle",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  Expanded(
                    child: availableFriends.isEmpty
                        ? const Center(
                            child: Text(
                              "Eklenebilecek yeni arkadaş bulunamadı.",
                            ),
                          )
                        : ListView.builder(
                            itemCount: availableFriends.length,
                            itemBuilder: (context, index) {
                              final friend = availableFriends[index];
                              return ListTile(
                                // ✅ RAM/Cache'deki profil fotoğrafını gösteren yardımcı fonksiyon
                                leading: _buildUserAvatar(friend),
                                title: Text(friend.name),
                                subtitle: const Text("Arkadaş"),
                                trailing: const Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.green,
                                ),
                                onTap: () {
                                  // Ana sayfanın (CreateGroupScreen) state'ini günceller
                                  setState(() {
                                    _currentMembers.add(friend);
                                  });

                                  // Modal içindeki availableFriends listesini tazeleyerek
                                  // eklenen kişinin anında listeden kaybolmasını sağlar
                                  setModalState(() {});

                                  // İstersen ekleme sonrası modalı kapatabilirsin:
                                  // Navigator.pop(context);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Grup Oluştur')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // --- Fotoğraf Seçimi ---
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.deepPurple.shade100,
                  backgroundImage: _groupImage != null
                      ? FileImage(_groupImage!)
                      : null,
                  child: _groupImage == null
                      ? const Icon(
                          Icons.camera_alt,
                          size: 40,
                          color: Colors.deepPurple,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 24),

              // --- Grup Adı ---
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Grup Adı',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Grup adı gerekli' : null,
                onSaved: (v) => _groupName = v!,
              ),
              const SizedBox(height: 16),

              // --- Grup Açıklaması ---
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Grup Açıklaması (Opsiyonel)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 2,
                onSaved: (v) => _groupDescription = v ?? '',
              ),
              const SizedBox(height: 24),

              // --- Üyeler Başlığı ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Üyeler (${_currentMembers.length})",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showAddMembersModal,
                    icon: const Icon(Icons.person_add),
                    label: const Text("Ekle"),
                  ),
                ],
              ),
              const Divider(),

              // --- Üye Listesi ---
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _currentMembers.length,
                itemBuilder: (context, index) {
                  final user = _currentMembers[index];
                  return ListTile(
                    leading: _buildUserAvatar(user),
                    title: Text(user.name),
                    subtitle: const Text("Üye"),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () =>
                          setState(() => _currentMembers.removeAt(index)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              _isCreating
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      onPressed: _currentMembers.length < 2
                          ? null
                          : _createGroup,
                      icon: const Icon(Icons.check),
                      label: const Text("Grubu Oluştur"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
