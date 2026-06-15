import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_response.dart';

class AuthProvider with ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _token;
  AuthResponse? _userAuthData;
  bool _isLoading = true;

  String? get token => _token;
  bool get isAuthenticated =>
      _token != null && _userAuthData != null; // 👈 İkisi de olmalı
  bool get isLoading => _isLoading;
  AuthResponse? get currentUser => _userAuthData;

  Future<void> initializeAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 1. Tüm gerekli verileri diskten oku
      final storedToken = await _secureStorage.read(key: 'jwt_token');
      final userId = await _secureStorage.read(key: 'user_id');
      final userName = await _secureStorage.read(key: 'user_name');
      final email = await _secureStorage.read(key: 'user_email');
      final phoneNumber = await _secureStorage.read(key: 'user_phone');
      final country = await _secureStorage.read(key: 'user_country');
      final city = await _secureStorage.read(key: 'user_city');
      final about = await _secureStorage.read(key: 'user_about');

      if (storedToken != null && userId != null) {
        _token = storedToken;
        // 2. RAM'deki kullanıcı objesini doldur
        _userAuthData = AuthResponse(
          token: storedToken,
          userId: userId,
          userName: userName ?? "Kullanıcı",
          firstName: "",
          lastName: "",
          email: email,
          age: 0,
          phoneNumber: phoneNumber,
          country: country,
          city: city,
          gender: "",
          about: about,
        );
        debugPrint("✅ Oturum başarıyla geri yüklendi: $userName");
      }
    } catch (e) {
      debugPrint("❌ Disk okuma hatası: $e");
      _token = null;
      _userAuthData = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Login olunca hem RAM'e hem Diske yazalım
  Future<void> loginSuccess(AuthResponse authData) async {
    _token = authData.token;
    _userAuthData = authData;

    // Tüm alanları diske kaydediyoruz:
    await _secureStorage.write(key: 'jwt_token', value: authData.token);
    await _secureStorage.write(key: 'user_id', value: authData.userId);
    await _secureStorage.write(key: 'user_name', value: authData.userName);
    await _secureStorage.write(key: 'user_email', value: authData.email);
    await _secureStorage.write(key: 'user_city', value: authData.city);
    await _secureStorage.write(key: 'user_country', value: authData.country);
    await _secureStorage.write(key: 'user_phone', value: authData.phoneNumber);
    await _secureStorage.write(key: 'user_about', value: authData.about);

    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _userAuthData = null;
    await _secureStorage.deleteAll(); // Hepsini sil
    notifyListeners();
  }
  // AuthProvider sınıfının içine ekle:

  void updateLocalUserField(String fieldName, String newValue) {
    if (_userAuthData == null) return;

    // Mevcut veriyi kopyalayarak yeni bir AuthResponse oluşturuyoruz
    // Çünkü AuthResponse genellikle immutable (değiştirilemez) tasarlanır
    switch (fieldName.toLowerCase()) {
      case "profileimage": // 👈 Yeni ekledik
        _userAuthData = _userAuthData!.copyWith(profileImageUrl: newValue);
        break;
      case "city":
        _userAuthData = _userAuthData!.copyWith(city: newValue);
        break;
      case "country":
        _userAuthData = _userAuthData!.copyWith(country: newValue);
        break;
      case "about":
        _userAuthData = _userAuthData!.copyWith(about: newValue);
        break;
      case "phone":
        _userAuthData = _userAuthData!.copyWith(phoneNumber: newValue);
        break;
      case "name":
        _userAuthData = _userAuthData!.copyWith(firstName: newValue);
        break;
      case "surname":
        _userAuthData = _userAuthData!.copyWith(lastName: newValue);
        break;
      case "email":
        _userAuthData = _userAuthData!.copyWith(email: newValue);
        break;
    }

    notifyListeners(); // 🚨 Bu satır profil sayfasını ve diğer ekranları anında yeniler!
  }
}
