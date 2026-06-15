class User {
  final String id; // Backend'den gelen GUID'i tutmak için şart
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final String? password; // Keşfet ekranında şifre gelmez, opsiyonel yaptık
  final String gender;
  final int age;
  final String phoneNumber;
  final String country;
  final String city;
  int status; // 🚨 Backend'den gelen Enum değeri (0, 1, 2, 3)
  String? profileImageUrl;
  String? about;

  User({
    required this.id, // ID eklendi
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.email,
    this.password,
    required this.gender,
    required this.age,
    required this.phoneNumber,
    required this.country,
    required this.city,
    required this.status, // Status eklendi
    this.profileImageUrl,
    this.about,
  });

  // API'ye veri gönderirken (Kayıt vb.) kullanılır
  Map<String, dynamic> toJson() {
    return {
      "Id": id,
      "FirstName": firstName,
      "LastName": lastName,
      "UserName": username,
      "Email": email,
      "Password": password,
      "Gender": gender,
      "Age": age,
      "PhoneNumber": phoneNumber,
      "Country": country,
      "City": city,
      "Status": status,
      "About": about,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      username:
          json['userName'] ?? '', // Backend'den 'userName' geliyor demiştin
      email: json['email'] ?? '',
      password: '',
      gender: json['gender'] ?? '',
      age: json['age'] ?? 0,
      phoneNumber: json['phoneNumber'] ?? '',
      country: json['country'] ?? '',
      city: json['city'] ?? '',
      status: json['status'] ?? 0,
      profileImageUrl: json['profileImageUrl'],
      about: json['about'] ?? '',
    );
  }
}
