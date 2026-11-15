import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';
import 'enums.dart';
import 'geo.dart';

part 'job.g.dart';

@JsonSerializable()
class QuoteRequest {
  QuoteRequest({required this.service, required this.pickup, required this.dropoff, this.food, this.pabili, this.padala});
  final ServiceType service;
  final Stop pickup;
  final Stop dropoff;
  final FoodQuoteInput? food;
  final PabiliQuoteInput? pabili;
  final PadalaQuoteInput? padala;

  factory QuoteRequest.fromJson(Map<String, dynamic> json) => _$QuoteRequestFromJson(json);
  Map<String, dynamic> toJson() => _$QuoteRequestToJson(this);
}

@JsonSerializable()
class FoodQuoteInput {
  FoodQuoteInput({required this.merchantId, required this.items});
  final String merchantId;
  final List<FoodQuoteItem> items;

  factory FoodQuoteInput.fromJson(Map<String, dynamic> json) => _$FoodQuoteInputFromJson(json);
  Map<String, dynamic> toJson() => _$FoodQuoteInputToJson(this);
}

@JsonSerializable()
class FoodQuoteItem {
  FoodQuoteItem({required this.itemId, required this.quantity, required this.addonOptionIds, this.note});
  final String itemId;
  final int quantity;
  final List<String> addonOptionIds;
  final String? note;

  factory FoodQuoteItem.fromJson(Map<String, dynamic> json) => _$FoodQuoteItemFromJson(json);
  Map<String, dynamic> toJson() => _$FoodQuoteItemToJson(this);
}

@JsonSerializable()
class PabiliItem {
  PabiliItem({required this.name, required this.quantity, this.note});
  final String name;
  final int quantity;
  final String? note;

  factory PabiliItem.fromJson(Map<String, dynamic> json) => _$PabiliItemFromJson(json);
  Map<String, dynamic> toJson() => _$PabiliItemToJson(this);
}

@JsonSerializable()
class PabiliQuoteInput {
  PabiliQuoteInput({required this.storeName, required this.items, required this.estimatedItemTotalCentavos});
  final String storeName;
  final List<PabiliItem> items;
  final int estimatedItemTotalCentavos;

  factory PabiliQuoteInput.fromJson(Map<String, dynamic> json) => _$PabiliQuoteInputFromJson(json);
  Map<String, dynamic> toJson() => _$PabiliQuoteInputToJson(this);
}

@JsonSerializable()
class PadalaQuoteInput {
  PadalaQuoteInput({
    required this.size,
    required this.description,
    required this.recipientName,
    required this.recipientPhone,
    this.photoKey,
  });
  final PadalaSize size;
  final String description;
  final String recipientName;
  final String recipientPhone;
  final String? photoKey;

  factory PadalaQuoteInput.fromJson(Map<String, dynamic> json) => _$PadalaQuoteInputFromJson(json);
  Map<String, dynamic> toJson() => _$PadalaQuoteInputToJson(this);
}

@JsonSerializable()
class FareLine {
  FareLine({required this.label, required this.amountCentavos});
  final String label;
  final int amountCentavos;

  factory FareLine.fromJson(Map<String, dynamic> json) => _$FareLineFromJson(json);
  Map<String, dynamic> toJson() => _$FareLineToJson(this);
}

@JsonSerializable()
@UtcDateTimeConverter()
class Quote {
  Quote({
    required this.id,
    required this.service,
    required this.distanceM,
    required this.durationS,
    required this.expiresAt,
    required this.breakdown,
    required this.totalCentavos,
    this.maxItemBudgetCentavos,
  });
  final String id;
  final ServiceType service;
  final int distanceM;
  final int durationS;
  final DateTime expiresAt;
  final List<FareLine> breakdown;
  final int totalCentavos;
  final int? maxItemBudgetCentavos;

  factory Quote.fromJson(Map<String, dynamic> json) => _$QuoteFromJson(json);
  Map<String, dynamic> toJson() => _$QuoteToJson(this);
}

@JsonSerializable()
class JobRider {
  JobRider({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.phoneMasked,
    required this.plate,
    required this.makeModel,
    required this.color,
    this.rating,
    this.location,
  });
  final String id;
  final String name;
  final String? photoUrl;
  final String phoneMasked;
  final String plate;
  final String makeModel;
  final String color;
  final double? rating;
  final LatLng? location;

  factory JobRider.fromJson(Map<String, dynamic> json) => _$JobRiderFromJson(json);
  Map<String, dynamic> toJson() => _$JobRiderToJson(this);
}

@JsonSerializable()
class JobMerchant {
  JobMerchant({required this.id, required this.name, required this.phoneMasked});
  final String id;
  final String name;
  final String phoneMasked;

  factory JobMerchant.fromJson(Map<String, dynamic> json) => _$JobMerchantFromJson(json);
  Map<String, dynamic> toJson() => _$JobMerchantToJson(this);
}

/// One ordered line, used by `Job.food.items` and `MerchantOrder.items`.
@JsonSerializable()
class OrderLine {
  OrderLine({required this.name, required this.quantity, required this.addons, this.note, required this.lineTotalCentavos});
  final String name;
  final int quantity;
  final List<String> addons;
  final String? note;
  final int lineTotalCentavos;

  factory OrderLine.fromJson(Map<String, dynamic> json) => _$OrderLineFromJson(json);
  Map<String, dynamic> toJson() => _$OrderLineToJson(this);
}

@JsonSerializable()
@NullableUtcDateTimeConverter()
class JobFood {
  JobFood({
    required this.items,
    required this.subtotalCentavos,
    this.prepTimeMinutes,
    this.readyAt,
    required this.isReady,
    this.riderPaysMerchantCentavos,
  });
  final List<OrderLine> items;
  final int subtotalCentavos;
  final int? prepTimeMinutes;
  final DateTime? readyAt;
  final bool isReady;

  /// ADDED: amount the rider pays the merchant at pickup (cash orders only).
  /// Equals `MerchantOrder.rider_pays_at_pickup_centavos`.
  final int? riderPaysMerchantCentavos;

  factory JobFood.fromJson(Map<String, dynamic> json) => _$JobFoodFromJson(json);
  Map<String, dynamic> toJson() => _$JobFoodToJson(this);
}

@JsonSerializable()
class JobPabili {
  JobPabili({required this.storeName, required this.items, this.receiptUrl, this.itemTotalCentavos});
  final String storeName;
  final List<PabiliItem> items;
  final String? receiptUrl;
  final int? itemTotalCentavos;

  factory JobPabili.fromJson(Map<String, dynamic> json) => _$JobPabiliFromJson(json);
  Map<String, dynamic> toJson() => _$JobPabiliToJson(this);
}

@JsonSerializable()
class JobPadala {
  JobPadala({required this.size, required this.description, required this.recipientName, required this.recipientPhone, this.photoUrl});
  final PadalaSize size;
  final String description;
  final String recipientName;
  final String recipientPhone;
  final String? photoUrl;

  factory JobPadala.fromJson(Map<String, dynamic> json) => _$JobPadalaFromJson(json);
  Map<String, dynamic> toJson() => _$JobPadalaToJson(this);
}

@JsonSerializable()
class Fare {
  Fare({required this.breakdown, required this.totalCentavos});
  final List<FareLine> breakdown;
  final int totalCentavos;

  factory Fare.fromJson(Map<String, dynamic> json) => _$FareFromJson(json);
  Map<String, dynamic> toJson() => _$FareToJson(this);
}

@JsonSerializable()
class JobPayment {
  JobPayment({required this.method, required this.status, this.checkoutUrl});
  final PaymentMethod method;
  final PaymentStatus status;
  final String? checkoutUrl;

  factory JobPayment.fromJson(Map<String, dynamic> json) => _$JobPaymentFromJson(json);
  Map<String, dynamic> toJson() => _$JobPaymentToJson(this);
}

@JsonSerializable()
@UtcDateTimeConverter()
class TimelineEntry {
  TimelineEntry({required this.status, required this.at});
  final JobStatus status;
  final DateTime at;

  factory TimelineEntry.fromJson(Map<String, dynamic> json) => _$TimelineEntryFromJson(json);
  Map<String, dynamic> toJson() => _$TimelineEntryToJson(this);
}

/// Values found in `Job.allowed_actions`.
class JobActions {
  JobActions._();
  // customer
  static const cancel = 'cancel';
  static const chat = 'chat';
  static const call = 'call';
  static const sos = 'sos';
  static const share = 'share';
  static const confirmItems = 'confirm_items';
  static const rate = 'rate';
  // rider: target statuses of POST /rider/jobs/{id}/status are listed by
  // their wire name (e.g. `arrived_pickup`), see API_CONTRACT.md (ADDED).
}

@JsonSerializable()
@UtcDateTimeConverter()
class Job {
  Job({
    required this.id,
    required this.code,
    required this.service,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.pickup,
    required this.dropoff,
    this.rider,
    this.merchant,
    this.food,
    this.pabili,
    this.padala,
    required this.fare,
    required this.payment,
    this.proofUrl,
    this.cancelReason,
    this.cancelledBy,
    required this.allowedActions,
    required this.timeline,
  });

  final String id;
  final String code;
  final ServiceType service;
  final JobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Stop pickup;
  final Stop dropoff;
  final JobRider? rider;
  final JobMerchant? merchant;
  final JobFood? food;
  final JobPabili? pabili;
  final JobPadala? padala;
  final Fare fare;
  final JobPayment payment;
  final String? proofUrl;
  final String? cancelReason;
  final PartyRole? cancelledBy;
  final List<String> allowedActions;
  final List<TimelineEntry> timeline;

  bool can(String action) => allowedActions.contains(action);
  bool get isActive => !status.isFinal;

  factory Job.fromJson(Map<String, dynamic> json) => _$JobFromJson(json);
  Map<String, dynamic> toJson() => _$JobToJson(this);
}

@JsonSerializable()
@UtcDateTimeConverter()
class ShareLink {
  ShareLink({required this.url, required this.expiresAt});
  final String url;
  final DateTime expiresAt;

  factory ShareLink.fromJson(Map<String, dynamic> json) => _$ShareLinkFromJson(json);
  Map<String, dynamic> toJson() => _$ShareLinkToJson(this);
}

@JsonSerializable()
class RatingInput {
  RatingInput({required this.riderRating, required this.riderTags, this.comment, this.merchantRating});
  final int riderRating;
  final List<String> riderTags;
  final String? comment;
  final int? merchantRating;

  factory RatingInput.fromJson(Map<String, dynamic> json) => _$RatingInputFromJson(json);
  Map<String, dynamic> toJson() => _$RatingInputToJson(this);
}
