import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';
import 'enums.dart';

part 'misc.g.dart';

@JsonSerializable()
@UtcDateTimeConverter()
class ChatMessage {
  ChatMessage({required this.id, required this.jobId, required this.sender, this.text, this.imageUrl, required this.createdAt});
  final String id;
  final String jobId;
  final PartyRole sender;
  final String? text;
  final String? imageUrl;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);
  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);
}

@JsonSerializable()
@UtcDateTimeConverter()
class UploadTicket {
  UploadTicket({required this.uploadUrl, required this.key, required this.expiresAt});
  final String uploadUrl;
  final String key;
  final DateTime expiresAt;

  factory UploadTicket.fromJson(Map<String, dynamic> json) => _$UploadTicketFromJson(json);
  Map<String, dynamic> toJson() => _$UploadTicketToJson(this);
}

@JsonSerializable()
class MaskedNumber {
  MaskedNumber({required this.maskedNumber});
  final String maskedNumber;

  factory MaskedNumber.fromJson(Map<String, dynamic> json) => _$MaskedNumberFromJson(json);
  Map<String, dynamic> toJson() => _$MaskedNumberToJson(this);
}

/// A page of a cursor-paginated list (`meta.next_cursor`).
class Page<T> {
  const Page(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
  bool get hasMore => nextCursor != null;
}

/// Exposes the wire string of [UploadPurpose] values.
String uploadPurposeWire(UploadPurpose p) => p.wire;
