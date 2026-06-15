import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:my_first_flutterapp/services/secure_storage_service.dart';
import 'package:my_first_flutterapp/screens/messages_screen.dart';
import 'package:my_first_flutterapp/screens/signup_screen.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'package:my_first_flutterapp/models/auth_response.dart';
import 'package:provider/provider.dart';
import 'package:my_first_flutterapp/services/auth_provider.dart';

import 'forgot_password_screen.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();

  bool _obscure = true;
  bool _remember = false;
  bool _loading = false;

  final ApiService _apiService = ApiService();
  final SecureStorageService _storageService = SecureStorageService();
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();

    _videoController =
        VideoPlayerController.asset('assets/videos/login-bgg.mp4')
          ..initialize().then((_) {
            _videoController.setLooping(true);
            _videoController.play();
            setState(() {});
          });
  }

  @override
  void dispose() {
    _videoController.dispose();
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    bool shouldStopLoading = true;

    try {
      final identifier = _emailCtl.text.trim();
      final password = _passCtl.text;

      // 1. API Çağrısı
      final AuthResponse authResult = await _apiService.loginUser(
        identifier,
        password,
      );
      if (!mounted) return;
      // 2. AuthProvider'a erişim
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // 3. KRİTİK NOKTA: Beni Hatırla Kontrolü
      if (_remember) {
        // ✅ BENİ HATIRLA SEÇİLİ: Hem RAM'e hem DİSKE kaydet
        // Az önce AuthProvider içinde yazdığımız metodu çağırıyoruz
        await authProvider.loginSuccess(authResult);
      } else {
        // ℹ️ BENİ HATIRLA SEÇİLİ DEĞİL: Sadece RAM'e kaydet (Uygulama kapanınca uçar)
        // Diskteki eski verileri de temizle
        authProvider.loginSuccess(authResult);
        await _storageService.deleteToken();
        await _storageService.deleteUserId();
      }

      _showSnack('Giriş başarılı! Hoş geldiniz ${authResult.userName}');

      if (!mounted) return;
      shouldStopLoading = false;

      // 4. Yönlendirme
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ExploreUsersScreen()),
      );
    } catch (e) {
      String errorMessage = e.toString().replaceAll('Exception: ', '');
      _showError(errorMessage);
    } finally {
      if (mounted && shouldStopLoading) {
        setState(() => _loading = false);
      }
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String text) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hata'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cardMaxWidth = mq.size.width * 0.86;

    return Scaffold(
      body: Stack(
        children: [
          // Video background
          Positioned.fill(
            child: _videoController.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController.value.size.width,
                      height: _videoController.value.size.height,
                      child: VideoPlayer(_videoController),
                    ),
                  )
                : Container(color: Colors.black),
          ),

          // Dark overlay for readability
          Positioned.fill(child: Container(color: Colors.black.withAlpha(51))),

          // Centered login card with blur
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: cardMaxWidth,
                  maxHeight: 700,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(217),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(38),
                            blurRadius: 10,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 22,
                      ),
                      child: _buildForm(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Convo',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.indigo[600],
            ),
          ),
          const SizedBox(height: 6),
          Text('Giriş Yapın', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email veya Kullanıcı Adı',
              hintText: 'Email veya kullanıcı adınız',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.person_outline),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'E-posta veya kullanıcı adı girin';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Şifre',
              hintText: 'Şifreniz',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              isDense: true,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Şifre girin';
              if (v.length < 6) return 'En az 6 karakter';
              return null;
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
              ),
              const SizedBox(width: 4),
              const Text('Beni Hatırla'),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                child: const Text('Şifremi Unuttum?'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[400],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Giriş Yap'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              // 👈 onPressed'i async yaptık
              // 1. SignUpScreen'i aç ve dönen sonucu bekle
              final result = await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SignUpScreen()),
              );

              // 2. Sonuç kontrolü (Kayıt başarılıysa, result bir String'dir)
              if (result != null && result is String) {
                if (!mounted) return;
                // SnackBar'ı gösterme
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result),
                    backgroundColor: Colors.green, // Başarı için yeşil
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
            child: const Text('Hesap Oluştur'),
          ),
        ],
      ),
    );
  }
}
