import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';
import 'enums.dart';

part 'user.g.dart';

@JsonSerializable()
@UtcDateTimeConverter()
class User {
  User({
    required this.id,
    required this.phone,
    required this.name,
    this.email,
    required this.language,
    required this.roles,
    required this.createdAt,
  });

  final String id;
  final String phone;
  final String name;
  final String? email;
  final AppLanguage language;
  final List<UserRole> roles;
  final DateTime createdAt;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
class OtpRequestResult {
  OtpRequestResult({required this.expiresInSeconds, required this.resendAfterSeconds});
  final int expiresInSeconds;
  final int resendAfterSeconds;

  factory OtpRequestResult.fromJson(Map<String, dynamic> json) => _$OtpRequestResultFromJson(json);
  Map<String, dynamic> toJson() => _$OtpRequestResultToJson(this);
}

@JsonSerializable()
class AuthResult {
  AuthResult({required this.accessToken, required this.refreshToken, required this.user, required this.isNewUser});
  final String accessToken;
  final String refreshToken;
  final User user;
  final bool isNewUser;

  factory AuthResult.fromJson(Map<String, dynamic> json) => _$AuthResultFromJson(json);
  Map<String, dynamic> toJson() => _$AuthResultToJson(this);
}

@JsonSerializable()
class TokenPair {
  TokenPair({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;

  factory TokenPair.fromJson(Map<String, dynamic> json) => _$TokenPairFromJson(json);
  Map<String, dynamic> toJson() => _$TokenPairToJson(this);
}
