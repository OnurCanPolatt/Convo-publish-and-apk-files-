import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import '../models/auth_response.dart';
import '../models/user.dart';

class ProfileService {
  final Dio _dio;
  final String baseUrl = 'https://convoapp.app/api';

  // Constructor: Dio nesnesini dışarıdan alır
  ProfileService(this._dio);

  Future<String?> getProfileImageUrl(String userId, String token) async {
    try {
      final response = await _dio.get(
        '$baseUrl/Image/image/$userId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['imageUrl'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint("🖼️ Resim URL'si alınamadı: $e");
      return null;
    }
  }

  Future<bool> updateAllProfileInfo(AuthResponse user, String token) async {
    try {
      // 🚨 C# Modelindeki isimlerle (email, userName, phone, country, city, about)
      // birebir aynı anahtarları kullanıyoruz.
      final Map<String, dynamic> postData = {
        "email": user.email ?? "",
        "userName": user.userName ?? "",
        "phone":
            user.phoneNumber ??
            "", // AuthResponse'daki phoneNumber -> Modeldeki phone
        "country": user.country ?? "",
        "city": user.city ?? "",
        "about":
            user.about ??
            " ", // Boşsa bile en azından bir boşluk karakteri gönderelim
      };

      final response = await _dio.put(
        '$baseUrl/ProfileInfo/update-allInfo',
        data: postData,
        options: Options(
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      if (e is DioException) {
        // 400 hatasının içindeki validasyon mesajlarını görmek için:
        debugPrint("❌ Backend Validasyon Hatası: ${e.response?.data}");
      }
      return false;
    }
  }

  // ApiService.dart içine ekle
  Future<String?> uploadProfileImage(
    File imageFile,
    String userId,
    String token,
  ) async {
    try {
      String fileName = imageFile.path.split('/').last;

      // 1. Multipart form verisi
      // Backend'de Request.Form.Files.FirstOrDefault() kullandığın için
      // "file" anahtarı doğru, ancak backend userId'yi URL'den aldığı için
      // FormData içine tekrar "userId" eklemene gerek yok (zararı da olmaz).
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(
          imageFile.path,
          filename: fileName,
        ),
      });

      // 2. URL Yapılandırması
      // Controller ismin: ProfilePicture, Endpoint: upload/{userId}
      final response = await _dio.post(
        '$baseUrl/ProfilePicture/upload/$userId',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type':
                'multipart/form-data', // Form tipi olduğunu belirttik
          },
        ),
      );

      // 3. Yanıt Kontrolü (Backend'in döndüğü yapıya göre düzenlendi)
      if (response.statusCode == 200 && response.data['success'] == true) {
        // 🚨 DİKKAT: Senin backend 'data' objesi içinde 'originalImageUrl' dönüyor.
        // Flutter'da response.data['data']['originalImageUrl'] şeklinde okumalısın.
        final String? newImageUrl = response.data['data']['originalImageUrl'];
        return newImageUrl;
      }
      return null;
    } catch (e) {
      if (e is DioException) {
        debugPrint("🖼️ API Hatası: ${e.response?.data}");
      }
      debugPrint("🖼️ Resim yükleme hatası: $e");
      return null;
    }
  }

  Future<User?> getUserDetail(String userId, String token) async {
    try {
      final response = await _dio.post(
        "$baseUrl/Users/getUserInfobyId", // 🚨 BURAYI DÜZELTTİK: byInfo değil byId olmalı
        data: '"$userId"',
        options: Options(headers: {"Authorization": "Bearer $token"}),
      );
      if (response.statusCode == 200) {
        return User.fromJson(response.data);
      }
      return null;
    } catch (e) {
      debugPrint("❌ Kullanıcı detay hatası: $e");
      return null;
    }
  }

  Future<bool> changePassword(
    String currentPass,
    String newPass,
    String token,
  ) async {
    try {
      final response = await _dio.put(
        'https://convoapp.app/api/ProfileInfo/change-password',
        data: {'currentPassword': currentPass, 'newPassword': newPass},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
