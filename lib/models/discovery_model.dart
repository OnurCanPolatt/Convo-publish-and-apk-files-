import 'package:my_first_flutterapp/models/user.dart';

class DiscoveryResponse {
  final List<User> users;
  final int totalCount;

  DiscoveryResponse({required this.users, required this.totalCount});

  factory DiscoveryResponse.fromJson(Map<String, dynamic> json) {
    return DiscoveryResponse(
      users: (json['users'] as List)
          .map(
            (u) => User.fromJson(u),
          ) // Mevcut User.fromJson metodunu kullanıyoruz
          .toList(),
      totalCount: json['totalCount'] ?? 0,
    );
  }
}
