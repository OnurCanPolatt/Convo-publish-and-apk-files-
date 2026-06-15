class AuthResponse {
  // 🚨 Düzeltme 1: Alan adları lowerCamelCase yapıldı.
  final String? token;
  final String? userId;
  final String? userName;
  final String? firstName;
  final String? lastName;
  final int? age;
  final String? email;
  final String? phoneNumber;
  final String? country;
  final String? city;
  final String? gender;
  final String? about;
  final String? profileImageUrl;

  AuthResponse({
    required this.token,
    required this.userId,
    required this.userName,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.email,
    required this.phoneNumber,
    required this.country,
    required this.city,
    required this.gender,
    this.about, // required kaldırıldı, çünkü '?' var.
    this.profileImageUrl,
  });
  AuthResponse copyWith({
    String? token,
    String? userId,
    String? userName,
    String? firstName,
    String? lastName,
    int? age,
    String? email,
    String? phoneNumber,
    String? country,
    String? city,
    String? gender,
    String? about,
    String? profileImageUrl,
  }) {
    return AuthResponse(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      age: age ?? this.age,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      country: country ?? this.country,
      city: city ?? this.city,
      gender: gender ?? this.gender,
      about: about ?? this.about,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  // API'dan gelen JSON verisini AuthResponse objesine dönüştürmek için Factory Metot
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      // JSON ANAHTARLARI hala .NET'ten geldiği gibi okunuyor:
      profileImageUrl: json['profileImageUrl'] as String?,
      token: json['token'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userName: json['username'] as String? ?? '',

      // Diğer alanlar (küçük harf key ile okundu)
      firstName: json['firstname'] as String? ?? '',
      lastName: json['lastname'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      country: json['country'] as String? ?? '',
      city: json['city'] as String? ?? '',
      gender: json['gender'] as String? ?? '',

      // About artık String? olduğu için null dönebilir.
      about: json['about'] as String?, // Null gelirse null döner. (Daha temiz)
    );
  }
}
