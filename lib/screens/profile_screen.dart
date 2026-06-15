import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/services/profile_service.dart';
import 'package:provider/provider.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/signalr/signalr_service.dart';
import '../widgets/fullscreen_image_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();
  late ProfileService _profileService;
  final ImagePicker _picker = ImagePicker();

  // Controllers
  late TextEditingController _cityController;
  late TextEditingController _countryController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _aboutController;

  bool _isPasswordSectionOpen = false;
  final TextEditingController _currentPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _profileService = ProfileService(Dio());

    _cityController = TextEditingController();
    _countryController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _aboutController = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;

      if (user != null) {
        setState(() {
          _cityController.text = user.city ?? "";
          _countryController.text = user.country ?? "";
          _emailController.text = user.email ?? "";
          _phoneController.text = user.phoneNumber ?? "";
          _aboutController.text = user.about ?? "";
        });

        if (authProvider.token != null) {
          final imageUrl = await _apiService.profile.getProfileImageUrl(
            user.userId!,
            authProvider.token!,
          );
          if (imageUrl != null && imageUrl.isNotEmpty) {
            authProvider.updateLocalUserField("profileimage", imageUrl);
          }
        }
      }
    });
  }

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (image != null) {
      setState(() => _isLoading = true);

      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final signalR = Provider.of<SignalrService>(context, listen: false);

      final token = authProvider.token ?? "";
      final userId = authProvider.currentUser?.userId ?? "";

      try {
        debugPrint("📸 Profil fotoğrafı API'ye yükleniyor...");
        final String? newImageUrl = await _apiService.profile
            .uploadProfileImage(File(image.path), userId, token);

        if (newImageUrl != null) {
          authProvider.updateLocalUserField("profileimage", newImageUrl);

          if (signalR.isConnected) {
            debugPrint(
              "📡 SignalR üzerinden güncelleme sinyali gönderiliyor...",
            );
            await signalR.methods?.userInfoUpdated(userId);
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profil fotoğrafı başarıyla güncellendi!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("❌ Resim yükleme hatası: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Güncelleme sırasında bir hata oluştu.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = authProvider.token ?? "";
      final user = authProvider.currentUser;

      if (user == null) return;

      try {
        final updatedUser = user.copyWith(
          email: _emailController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          country: _countryController.text.trim(),
          city: _cityController.text.trim(),
          about: _aboutController.text.trim(),
        );

        bool success = await _apiService.profile.updateAllProfileInfo(
          updatedUser,
          token,
        );

        if (mounted) {
          if (success) {
            authProvider.loginSuccess(updatedUser);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profil başarıyla güncellendi!'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Güncelleme başarısız!'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("Profil Güncelleme Hatası: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Teknik bir hata oluştu.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePasswordChange() async {
    final current = _currentPassController.text.trim();
    final newP = _newPassController.text.trim();

    if (current.isEmpty || newP.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Alanlar boş olamaz")));
      return;
    }
    if (newP.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Yeni şifre en az 6 karakter olmalıdır")),
      );
      return;
    }

    final authProv = Provider.of<AuthProvider>(context, listen: false);
    bool success = await _profileService.changePassword(
      current,
      newP,
      authProv.token!,
    );

    if (success) {
      setState(() {
        _isPasswordSectionOpen = false;
        _currentPassController.clear();
        _newPassController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Şifre güncellendi"),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Hata! Mevcut şifre yanlış olabilir"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0f172a)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3f51b5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profilimi Düzenle',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Main Content
                Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 32,
                      bottom: 100, // Sabit buton için boşluk
                    ),
                    children: [
                      // Profil Fotoğrafı
                      Center(
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () {
                                final imageUrl =
                                    authProvider.currentUser?.profileImageUrl;
                                if (imageUrl != null && imageUrl.isNotEmpty) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => FullscreenImagePage(
                                        imageUrl:
                                            "$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}",
                                        tag: 'my_profile_image',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Hero(
                                tag: 'my_profile_image',
                                child: Container(
                                  width: 128,
                                  height: 128,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF1e293b)
                                          : Colors.white,
                                      width: 4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child:
                                        (authProvider
                                                    .currentUser
                                                    ?.profileImageUrl !=
                                                null &&
                                            authProvider
                                                .currentUser!
                                                .profileImageUrl!
                                                .isNotEmpty)
                                        ? Image.network(
                                            "${authProvider.currentUser!.profileImageUrl}?t=${DateTime.now().millisecondsSinceEpoch}",
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Icon(
                                                      Icons.person,
                                                      size: 64,
                                                      color: Colors.grey[400],
                                                    ),
                                          )
                                        : Icon(
                                            Icons.person,
                                            size: 64,
                                            color: Colors.grey[400],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickAndUploadImage,
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3f51b5),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF1e293b)
                                          : Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Kullanıcı Adı (Read-Only)
                      _buildLabeledField(
                        label: 'Kullanıcı Adı (Değiştirilemez)',
                        icon: Icons.person,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF334155).withOpacity(0.5)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF475569)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person,
                                color: Colors.grey[400],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                user?.userName ?? "",
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[300]
                                      : Colors.grey[600],
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // E-posta
                      _buildLabeledField(
                        label: 'E-posta',
                        icon: Icons.mail,
                        isPrimary: true,
                        child: _buildTextField(
                          _emailController,
                          Icons.mail,
                          'E-posta',
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'E-posta gerekli';
                            }
                            if (!RegExp(
                              r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                            ).hasMatch(value)) {
                              return 'Geçerli bir e-posta girin';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Telefon
                      _buildLabeledField(
                        label: 'Telefon Numarası',
                        icon: Icons.call,
                        child: _buildTextField(
                          _phoneController,
                          Icons.call,
                          'Telefon',
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              // Sadece rakamları al
                              final digitsOnly = value.replaceAll(
                                RegExp(r'\D'),
                                '',
                              );

                              // Türkiye cep telefonu formatı kontrolü
                              // 05321234567 (11 rakam) veya 5321234567 (10 rakam)
                              if (digitsOnly.length == 10) {
                                // 5XX formatında olmalı
                                if (!digitsOnly.startsWith('5')) {
                                  return 'Geçersiz telefon numarası';
                                }
                              } else if (digitsOnly.length == 11) {
                                // 05XX formatında olmalı
                                if (!digitsOnly.startsWith('05')) {
                                  return 'Geçersiz telefon numarası';
                                }
                              } else {
                                return 'Telefon numarası 10-11 rakam olmalı';
                              }
                            }
                            return null;
                          },
                        ),
                      ),

                      // Şehir ve Ülke
                      Row(
                        children: [
                          Expanded(
                            child: _buildLabeledField(
                              label: 'Şehir',
                              icon: null,
                              child: _buildTextField(
                                _cityController,
                                null,
                                'Şehir',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildLabeledField(
                              label: 'Ülke',
                              icon: null,
                              child: _buildTextField(
                                _countryController,
                                null,
                                'Ülke',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Hakkımda
                      _buildLabeledField(
                        label: 'Hakkımda',
                        icon: null,
                        child: _buildTextField(
                          _aboutController,
                          null,
                          'Kendinizden bahsedin...',
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Şifre Değiştir Bölümü
                      _buildPasswordSection(isDark),
                    ],
                  ),
                ),

                // Sabit Alt Kaydet Butonu
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0f172a)
                          : const Color(0xFFF8FAFC),
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3f51b5),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.save, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Değişiklikleri Kaydet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLabeledField({
    required String label,
    IconData? icon,
    bool isPrimary = false,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isPrimary
                  ? const Color(0xFF3f51b5)
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    IconData? icon,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1e293b) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Icon(
                icon,
                color: icon == Icons.mail
                    ? const Color(0xFF3f51b5)
                    : Colors.grey[400],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextFormField(
              // ✅ TextFormField = validation var
              controller: controller,
              maxLines: maxLines,
              keyboardType: keyboardType,
              validator: validator,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                errorStyle: const TextStyle(height: 0), // Hata mesajını gizle
                contentPadding: EdgeInsets.symmetric(
                  horizontal: icon == null ? 16 : 0,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1e293b) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(
              () => _isPasswordSectionOpen = !_isPasswordSectionOpen,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.lock, color: Color(0xFF3f51b5), size: 20),
                  const SizedBox(width: 12),
                  const Text(
                    'Şifre Değiştir',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                  ),
                  const Spacer(),
                  Icon(
                    _isPasswordSectionOpen
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
          if (_isPasswordSectionOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Divider(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFE2E8F0),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _currentPassController,
                    obscureText: true,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Mevcut Şifre',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  Divider(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFE2E8F0),
                  ),
                  TextField(
                    controller: _newPassController,
                    obscureText: true,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Yeni Şifre (Min 6 Karakter)',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _handlePasswordChange,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3f51b5).withOpacity(0.1),
                      foregroundColor: const Color(0xFF3f51b5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                        side: BorderSide(
                          color: const Color(0xFF3f51b5).withOpacity(0.2),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Güncelle',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cityController.dispose();
    _countryController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _aboutController.dispose();
    _currentPassController.dispose();
    _newPassController.dispose();
    super.dispose();
  }
}
