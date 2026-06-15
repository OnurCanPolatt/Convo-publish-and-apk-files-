// lib/services/secure_storage_service.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  static const _userIdKey = 'auth_user_id';

  // Token'ı güvenli bir şekilde kaydeder
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  // Token'ı güvenli bir şekilde okur
  Future<String?> readToken() async {
    return await _storage.read(key: _tokenKey);
  }

  // Token'ı siler
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  // Kullanıcı ID'sini kaydeder
  Future<void> saveUserId(String userId) async {
    await _storage.write(key: _userIdKey, value: userId);
  }

  // Kullanıcı ID'sini okur
  Future<String?> readUserId() async {
    return await _storage.read(key: _userIdKey);
  }

  Future<void> deleteUserId() async {
    await _storage.delete(key: _userIdKey);
  }
}
