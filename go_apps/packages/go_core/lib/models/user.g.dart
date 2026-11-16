// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: json['id'] as String,
  phone: json['phone'] as String,
  name: json['name'] as String,
  email: json['email'] as String?,
  language: $enumDecode(_$AppLanguageEnumMap, json['language']),
  roles: (json['roles'] as List<dynamic>).map((e) => $enumDecode(_$UserRoleEnumMap, e)).toList(),
  createdAt: const UtcDateTimeConverter().fromJson(json['created_at'] as String),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'phone': instance.phone,
  'name': instance.name,
  'email': ?instance.email,
  'language': _$AppLanguageEnumMap[instance.language]!,
  'roles': instance.roles.map((e) => _$UserRoleEnumMap[e]!).toList(),
  'created_at': const UtcDateTimeConverter().toJson(instance.createdAt),
};

const _$AppLanguageEnumMap = {AppLanguage.en: 'en', AppLanguage.fil: 'fil'};

const _$UserRoleEnumMap = {UserRole.customer: 'customer', UserRole.rider: 'rider', UserRole.merchant: 'merchant'};

OtpRequestResult _$OtpRequestResultFromJson(Map<String, dynamic> json) => OtpRequestResult(
  expiresInSeconds: (json['expires_in_seconds'] as num).toInt(),
  resendAfterSeconds: (json['resend_after_seconds'] as num).toInt(),
);

Map<String, dynamic> _$OtpRequestResultToJson(OtpRequestResult instance) => <String, dynamic>{
  'expires_in_seconds': instance.expiresInSeconds,
  'resend_after_seconds': instance.resendAfterSeconds,
};

AuthResult _$AuthResultFromJson(Map<String, dynamic> json) => AuthResult(
  accessToken: json['access_token'] as String,
  refreshToken: json['refresh_token'] as String,
  user: User.fromJson(json['user'] as Map<String, dynamic>),
  isNewUser: json['is_new_user'] as bool,
);

Map<String, dynamic> _$AuthResultToJson(AuthResult instance) => <String, dynamic>{
  'access_token': instance.accessToken,
  'refresh_token': instance.refreshToken,
  'user': instance.user.toJson(),
  'is_new_user': instance.isNewUser,
};

TokenPair _$TokenPairFromJson(Map<String, dynamic> json) =>
    TokenPair(accessToken: json['access_token'] as String, refreshToken: json['refresh_token'] as String);

Map<String, dynamic> _$TokenPairToJson(TokenPair instance) => <String, dynamic>{
  'access_token': instance.accessToken,
  'refresh_token': instance.refreshToken,
};
