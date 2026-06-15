import 'package:my_first_flutterapp/models/user.dart';
import 'package:my_first_flutterapp/models/auth_response.dart';
import 'dart:developer';
import 'dart:convert';
import 'package:http/http.dart' as http_client;
import 'package:my_first_flutterapp/services/begin_api_service.dart';
import 'package:my_first_flutterapp/services/message_api_service.dart';
import 'package:my_first_flutterapp/services/request_service.dart';
import 'notification_service.dart';
import 'profile_service.dart';
import 'group_service.dart';
import 'package:dio/dio.dart';
import 'package:my_first_flutterapp/services/discovery_service.dart';

class ApiService {
  final String baseUrl = 'https://convoapp.app/api';

  late final Dio _dio;
  final http_client.Client _client = http_client.Client();
  late final BeginApiService beginApi;
  late final ProfileService profile;
  late final GroupService group;
  late final DiscoveryService discovery;
  late final RequestService request;
  late final NotificationApiService notification;
  final MessageApiService messageApi = MessageApiService();

  ApiService() {
    beginApi = BeginApiService(_client);
    _dio = Dio();
    profile = ProfileService(_dio);
    group = GroupService();
    discovery = DiscoveryService(_client, baseUrl: baseUrl);
    request = RequestService(_client, baseUrl: baseUrl);
    notification = NotificationApiService(_client, baseUrl: baseUrl);
  }
  Future<void> registerUser(User newUser) async {
    try {
      final url = Uri.parse('$baseUrl/auth/register');
      final body = newUser.toJson();

      log('İstek URL: $url');
      log('Gönderilen Veri: ${jsonEncode(body)}');

      // BURASI TEK KALIYOR
      final response = await http_client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      // TEKRAR EDEN ÇAĞRILAR SİLİNDİ

      log('API Yanıt Kodu: ${response.statusCode}');
      log('API Yanıt Body: ${response.body}'); // ⚠️ Tam yanıtı görün

      if (response.statusCode == 200) return;

      // Hata mesajını ayrıştır
      String errorMessage = 'Kayıt başarısız oldu.';
      try {
        final errorBody = jsonDecode(response.body);
        errorMessage = errorBody['message'] ?? errorMessage;
      } catch (_) {
        errorMessage = 'Sunucu hatası: ${response.statusCode}';
      }

      throw Exception(errorMessage);
    } catch (e) {
      log('API İsteği Sırasında Hata: $e');
      rethrow;
    }
  }

  Future<AuthResponse> loginUser(String identifier, String password) async {
    try {
      final url = Uri.parse('$baseUrl/auth/login');

      // Gönderilecek JSON gövdesi (Payload).
      // Bu anahtarlar ("Username", "Password"), .NET Login DTO'nuzdaki Property isimleriyle eşleşmelidir.
      final body = {"UsernameOrEmail": identifier, "Password": password};

      log('[ONUR] Login İsteği: $url, Veri: ${jsonEncode(body)}');

      final response = await http_client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body), // Gövdeyi JSON'a dönüştürüp gönder
      );

      log('API Yanıt Kodu: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Başarılı (OK): Gelen JSON'u AuthResponse modeline dönüştür
        return AuthResponse.fromJson(jsonDecode(response.body));
      } else {
        // Hata Durumu (400, 401, 500 vb.)
        String errorMessage = 'Giriş başarısız oldu.';
        try {
          final errorBody = jsonDecode(response.body);
          // .NET API'dan gelen hata mesajını çekiyoruz
          errorMessage = errorBody['message'] ?? errorMessage;
        } catch (_) {
          // JSON ayrıştırma hatası veya boş yanıt gövdesi
          errorMessage = 'Sunucu hatası: ${response.statusCode}';
        }

        // Hata mesajını fırlat (catch bloğunda yakalanacak)
        throw Exception(errorMessage);
      }
    } catch (e) {
      log('API Giriş İsteği Sırasında Hata: $e');
      rethrow;
    }
  }

  Future<AuthResponse> getUserInfoById(String userId, String token) async {
    final url = Uri.parse('$baseUrl/Users/getUserInfo');

    final body = jsonEncode(userId);

    try {
      final response = await http_client.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        jsonResponse['Token'] = token;
        return AuthResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 401) {
        throw Exception("Oturum Token'ı geçersiz veya süresi dolmuş.");
      } else {
        throw Exception(
          'Kullanıcı bilgileri çekilemedi. Hata kodu: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Şifre sıfırlama kodu gönder
  Future<void> forgotPassword(String email) async {
    final response = await http_client.post(
      Uri.parse('$baseUrl/Auth/forgot-password'), // baseUrl zaten /api içeriyor
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(email),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Kod gönderilemedi');
    }
  }

  /// Şifreyi sıfırla
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await http_client.post(
      Uri.parse('$baseUrl/Auth/reset-password'), // baseUrl zaten /api içeriyor
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'code': code,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Şifre sıfırlanamadı');
    }
  }
}
