import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:my_first_flutterapp/models/user.dart';
import 'package:my_first_flutterapp/services/api_service.dart';
import 'dart:developer';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();
  late VideoPlayerController _videoController;

  // Kontrolcüler
  final _firstNameCtl = TextEditingController();
  final _lastNameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _confirmPasswordCtl = TextEditingController();
  final _usernameCtl = TextEditingController();
  final _cityCtl = TextEditingController();
  final _countryCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _ageCtl = TextEditingController();
  final _aboutCtl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _selectedGender;

  @override
  void initState() {
    super.initState();
    // Login sayfasındaki videoyu burada da kullanalım
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
    _firstNameCtl.dispose();
    _lastNameCtl.dispose();
    _emailCtl.dispose();
    _passwordCtl.dispose();
    _confirmPasswordCtl.dispose();
    _usernameCtl.dispose();
    _cityCtl.dispose();
    _countryCtl.dispose();
    _phoneCtl.dispose();
    _ageCtl.dispose();
    _aboutCtl.dispose();
    super.dispose();
  }

  // API Kayıt Metodu (Senin metodun, sadece bildirimler düzenlendi)
  void _submitSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedGender == null) {
      _showError('Cinsiyet seçimi zorunludur.');
      return;
    }

    setState(() => _loading = true);

    try {
      final int age = int.tryParse(_ageCtl.text) ?? 0;
      final User newUser = User(
        id: '',
        firstName: _firstNameCtl.text.trim(),
        lastName: _lastNameCtl.text.trim(),
        username: _usernameCtl.text.trim(),
        email: _emailCtl.text.trim(),
        password: _passwordCtl.text,
        gender: _selectedGender!,
        age: age,
        phoneNumber: _phoneCtl.text.trim(),
        country: _countryCtl.text.trim(),
        city: _cityCtl.text.trim(),
        status: 0,
      );
      // API servisin eğer kayıt başarısızsa Exception fırlatmalı
      await _apiService.registerUser(newUser);

      if (!mounted) return;
      Navigator.pop(context, 'Kayıt Başarıyla Oluşturuldu!');
    } catch (e) {
      // 🚩 BURASI: API'den gelen 400 Bad Request içindeki hata mesajını gösterir
      String errorMessage = e.toString().replaceFirst('Exception: ', '');
      if (errorMessage.contains('is already taken')) {
        errorMessage = "Kullanıcı adı veya Email zaten kullanımda.";
      }
      _showError(errorMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // 1. Video Arka Plan
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

          // 2. Koyu Katman
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),

          // 3. İçerik (Blur Kartı)
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    width: mq.size.width * 0.9,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: _buildRegisterForm(),
                  ),
                ),
              ),
            ),
          ),

          // Geri butonu (Video üstünde görünmesi için)
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          Text(
            'Convo',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.indigo[600],
            ),
          ),
          const Text(
            'Yeni Hesap Oluşturun',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),

          // İsim Soyisim (Yan yana)
          Row(
            children: [
              Expanded(
                child: _buildField(_firstNameCtl, 'Ad', Icons.person_outline),
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildField(_lastNameCtl, 'Soyad', null)),
            ],
          ),
          _buildField(_usernameCtl, 'Kullanıcı Adı', Icons.alternate_email),
          _buildField(
            _emailCtl,
            'E-posta',
            Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
          ),

          // Şifreler
          _buildField(_passwordCtl, 'Şifre', Icons.lock_outline, isPass: true),
          _buildField(
            _confirmPasswordCtl,
            'Şifre Tekrar',
            Icons.lock_reset,
            isPass: true,
            isConfirm: true,
          ),

          // Yaş ve Cinsiyet (Yan yana)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildField(
                  _ageCtl,
                  'Yaş',
                  Icons.cake_outlined,
                  keyboard: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedGender,
                  validator: (v) => v == null ? 'Cinsiyet seçiniz' : null,
                  decoration: InputDecoration(
                    labelText: 'Cinsiyet',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: const ['Erkek', 'Kadın']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedGender = v),
                ),
              ),
            ],
          ),

          _buildField(
            _phoneCtl,
            'Telefon',
            Icons.phone_android_outlined,
            keyboard: TextInputType.phone,
          ),

          Row(
            children: [
              Expanded(
                child: _buildField(_cityCtl, 'Şehir', Icons.location_city),
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildField(_countryCtl, 'Ülke', Icons.public)),
            ],
          ),

          const SizedBox(height: 20),

          // Buton
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[400],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _loading ? null : _submitSignUp,
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Hesabı Oluştur',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Ortak TextField Tasarımı (Kod tekrarını önlemek için)
  // Ortak TextField Tasarımı
  Widget _buildField(
    TextEditingController ctl,
    String label,
    IconData? icon, {
    bool isPass = false,
    bool isConfirm = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctl,
        obscureText: isPass ? _obscure : false,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: isPass && !isConfirm
              ? IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
        ),
        validator: (v) {
          // trim() kullanarak sadece sağ ve soldaki boşlukları temizliyoruz
          final val = v?.trim() ?? '';

          // 1. Boş kontrolü
          if (val.isEmpty) return 'Bu alan boş bırakılamaz';

          // 2. Kullanıcı Adı ve İsim/Soyisim Boşluk Kontrolü (YENİ)
          if (label == 'Kullanıcı Adı' || label == 'Ad' || label == 'Soyad') {
            if (v!.contains(' ')) {
              return 'Boşluk karakteri kullanılamaz';
            }
          }

          // 3. Email format kontrolü
          if (keyboard == TextInputType.emailAddress) {
            final emailRegExp = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
            if (!emailRegExp.hasMatch(val))
              return 'Geçerli bir e-posta giriniz';
          }

          // 4. Telefon Numarası Kontrolü (11 Haneli) (YENİ)
          if (keyboard == TextInputType.phone) {
            // Sadece rakamlardan oluşup oluşmadığını ve 11 hane olduğunu kontrol eder
            if (val.length != 11 || !RegExp(r'^[0-9]+$').hasMatch(val)) {
              return 'Telefon numarası 11 haneli olmalıdır';
            }
          }

          // 5. Şifre uzunluk kontrolü
          if (isPass && !isConfirm && val.length < 6) {
            return 'Şifre en az 6 karakter olmalıdır';
          }

          // 6. Şifre eşleşme kontrolü
          if (isConfirm && val != _passwordCtl.text) {
            return 'Şifreler uyuşmuyor';
          }

          // 7. Yaş kontrolü
          if (label == 'Yaş') {
            final age = int.tryParse(val);
            if (age == null || age < 18 || age > 120)
              return 'Geçerli bir yaş giriniz (18+)';
          }

          return null;
        },
      ),
    );
  }
}
