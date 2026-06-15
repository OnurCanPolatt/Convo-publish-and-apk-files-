import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/discovery_model.dart'; // Yeni oluşturduğumuz model

class DiscoveryService {
  final String baseUrl;
  final http.Client client;

  DiscoveryService(this.client, {required this.baseUrl});

  Future<DiscoveryResponse> getDiscoveryUsers(
    int pageNumber,
    int pageSize,
    String token, {
    String? searchTerm,
  }) async {
    String urlString =
        '$baseUrl/Users/discovery?pageNumber=$pageNumber&pageSize=$pageSize';

    if (searchTerm != null && searchTerm.isNotEmpty) {
      urlString += '&searchTerm=$searchTerm';
    }

    final url = Uri.parse(urlString);

    try {
      final response = await client.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return DiscoveryResponse.fromJson(data);
      } else {
        throw Exception('Kullanıcılar getirilemedi: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
