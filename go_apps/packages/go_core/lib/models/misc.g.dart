// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'misc.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => ChatMessage(
  id: json['id'] as String,
  jobId: json['job_id'] as String,
  sender: $enumDecode(_$PartyRoleEnumMap, json['sender']),
  text: json['text'] as String?,
  imageUrl: json['image_url'] as String?,
  createdAt: const UtcDateTimeConverter().fromJson(json['created_at'] as String),
);

Map<String, dynamic> _$ChatMessageToJson(ChatMessage instance) => <String, dynamic>{
  'id': instance.id,
  'job_id': instance.jobId,
  'sender': _$PartyRoleEnumMap[instance.sender]!,
  'text': ?instance.text,
  'image_url': ?instance.imageUrl,
  'created_at': const UtcDateTimeConverter().toJson(instance.createdAt),
};

const _$PartyRoleEnumMap = {
  PartyRole.customer: 'customer',
  PartyRole.rider: 'rider',
  PartyRole.merchant: 'merchant',
  PartyRole.system: 'system',
};

UploadTicket _$UploadTicketFromJson(Map<String, dynamic> json) => UploadTicket(
  uploadUrl: json['upload_url'] as String,
  key: json['key'] as String,
  expiresAt: const UtcDateTimeConverter().fromJson(json['expires_at'] as String),
);

Map<String, dynamic> _$UploadTicketToJson(UploadTicket instance) => <String, dynamic>{
  'upload_url': instance.uploadUrl,
  'key': instance.key,
  'expires_at': const UtcDateTimeConverter().toJson(instance.expiresAt),
};

MaskedNumber _$MaskedNumberFromJson(Map<String, dynamic> json) => MaskedNumber(maskedNumber: json['masked_number'] as String);

Map<String, dynamic> _$MaskedNumberToJson(MaskedNumber instance) => <String, dynamic>{'masked_number': instance.maskedNumber};
