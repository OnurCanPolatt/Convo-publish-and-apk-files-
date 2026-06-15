import 'package:my_first_flutterapp/models/user.dart';

class Group {
  final int id;
  String name;
  String description;
  final List<User> members;
  final User admin;
  String? imageUrl; // Opsiyonel grup fotoğrafı

  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.members,
    required this.admin,
    this.imageUrl,
  });
}
