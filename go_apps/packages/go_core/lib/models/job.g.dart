// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QuoteRequest _$QuoteRequestFromJson(Map<String, dynamic> json) => QuoteRequest(
  service: $enumDecode(_$ServiceTypeEnumMap, json['service']),
  pickup: Stop.fromJson(json['pickup'] as Map<String, dynamic>),
  dropoff: Stop.fromJson(json['dropoff'] as Map<String, dynamic>),
  food: json['food'] == null ? null : FoodQuoteInput.fromJson(json['food'] as Map<String, dynamic>),
  pabili: json['pabili'] == null ? null : PabiliQuoteInput.fromJson(json['pabili'] as Map<String, dynamic>),
  padala: json['padala'] == null ? null : PadalaQuoteInput.fromJson(json['padala'] as Map<String, dynamic>),
);

Map<String, dynamic> _$QuoteRequestToJson(QuoteRequest instance) => <String, dynamic>{
  'service': _$ServiceTypeEnumMap[instance.service]!,
  'pickup': instance.pickup.toJson(),
  'dropoff': instance.dropoff.toJson(),
  'food': ?instance.food?.toJson(),
  'pabili': ?instance.pabili?.toJson(),
  'padala': ?instance.padala?.toJson(),
};

const _$ServiceTypeEnumMap = {
  ServiceType.ride: 'ride',
  ServiceType.food: 'food',
  ServiceType.pabili: 'pabili',
  ServiceType.padala: 'padala',
};

FoodQuoteInput _$FoodQuoteInputFromJson(Map<String, dynamic> json) => FoodQuoteInput(
  merchantId: json['merchant_id'] as String,
  items: (json['items'] as List<dynamic>).map((e) => FoodQuoteItem.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$FoodQuoteInputToJson(FoodQuoteInput instance) => <String, dynamic>{
  'merchant_id': instance.merchantId,
  'items': instance.items.map((e) => e.toJson()).toList(),
};

FoodQuoteItem _$FoodQuoteItemFromJson(Map<String, dynamic> json) => FoodQuoteItem(
  itemId: json['item_id'] as String,
  quantity: (json['quantity'] as num).toInt(),
  addonOptionIds: (json['addon_option_ids'] as List<dynamic>).map((e) => e as String).toList(),
  note: json['note'] as String?,
);

Map<String, dynamic> _$FoodQuoteItemToJson(FoodQuoteItem instance) => <String, dynamic>{
  'item_id': instance.itemId,
  'quantity': instance.quantity,
  'addon_option_ids': instance.addonOptionIds,
  'note': ?instance.note,
};

PabiliItem _$PabiliItemFromJson(Map<String, dynamic> json) =>
    PabiliItem(name: json['name'] as String, quantity: (json['quantity'] as num).toInt(), note: json['note'] as String?);

Map<String, dynamic> _$PabiliItemToJson(PabiliItem instance) => <String, dynamic>{
  'name': instance.name,
  'quantity': instance.quantity,
  'note': ?instance.note,
};

PabiliQuoteInput _$PabiliQuoteInputFromJson(Map<String, dynamic> json) => PabiliQuoteInput(
  storeName: json['store_name'] as String,
  items: (json['items'] as List<dynamic>).map((e) => PabiliItem.fromJson(e as Map<String, dynamic>)).toList(),
  estimatedItemTotalCentavos: (json['estimated_item_total_centavos'] as num).toInt(),
);

Map<String, dynamic> _$PabiliQuoteInputToJson(PabiliQuoteInput instance) => <String, dynamic>{
  'store_name': instance.storeName,
  'items': instance.items.map((e) => e.toJson()).toList(),
  'estimated_item_total_centavos': instance.estimatedItemTotalCentavos,
};

PadalaQuoteInput _$PadalaQuoteInputFromJson(Map<String, dynamic> json) => PadalaQuoteInput(
  size: $enumDecode(_$PadalaSizeEnumMap, json['size']),
  description: json['description'] as String,
  recipientName: json['recipient_name'] as String,
  recipientPhone: json['recipient_phone'] as String,
  photoKey: json['photo_key'] as String?,
);

Map<String, dynamic> _$PadalaQuoteInputToJson(PadalaQuoteInput instance) => <String, dynamic>{
  'size': _$PadalaSizeEnumMap[instance.size]!,
  'description': instance.description,
  'recipient_name': instance.recipientName,
  'recipient_phone': instance.recipientPhone,
  'photo_key': ?instance.photoKey,
};

const _$PadalaSizeEnumMap = {PadalaSize.small: 'small', PadalaSize.medium: 'medium', PadalaSize.large: 'large'};

FareLine _$FareLineFromJson(Map<String, dynamic> json) =>
    FareLine(label: json['label'] as String, amountCentavos: (json['amount_centavos'] as num).toInt());

Map<String, dynamic> _$FareLineToJson(FareLine instance) => <String, dynamic>{
  'label': instance.label,
  'amount_centavos': instance.amountCentavos,
};

Quote _$QuoteFromJson(Map<String, dynamic> json) => Quote(
  id: json['id'] as String,
  service: $enumDecode(_$ServiceTypeEnumMap, json['service']),
  distanceM: (json['distance_m'] as num).toInt(),
  durationS: (json['duration_s'] as num).toInt(),
  expiresAt: const UtcDateTimeConverter().fromJson(json['expires_at'] as String),
  breakdown: (json['breakdown'] as List<dynamic>).map((e) => FareLine.fromJson(e as Map<String, dynamic>)).toList(),
  totalCentavos: (json['total_centavos'] as num).toInt(),
  maxItemBudgetCentavos: (json['max_item_budget_centavos'] as num?)?.toInt(),
  routePolyline: json['route_polyline'] as String?,
);

Map<String, dynamic> _$QuoteToJson(Quote instance) => <String, dynamic>{
  'id': instance.id,
  'service': _$ServiceTypeEnumMap[instance.service]!,
  'distance_m': instance.distanceM,
  'duration_s': instance.durationS,
  'expires_at': const UtcDateTimeConverter().toJson(instance.expiresAt),
  'breakdown': instance.breakdown.map((e) => e.toJson()).toList(),
  'total_centavos': instance.totalCentavos,
  'max_item_budget_centavos': ?instance.maxItemBudgetCentavos,
  'route_polyline': ?instance.routePolyline,
};

JobRider _$JobRiderFromJson(Map<String, dynamic> json) => JobRider(
  id: json['id'] as String,
  name: json['name'] as String,
  photoUrl: json['photo_url'] as String?,
  phoneMasked: json['phone_masked'] as String,
  plate: json['plate'] as String,
  makeModel: json['make_model'] as String,
  color: json['color'] as String,
  rating: (json['rating'] as num?)?.toDouble(),
  location: json['location'] == null ? null : LatLng.fromJson(json['location'] as Map<String, dynamic>),
);

Map<String, dynamic> _$JobRiderToJson(JobRider instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'photo_url': ?instance.photoUrl,
  'phone_masked': instance.phoneMasked,
  'plate': instance.plate,
  'make_model': instance.makeModel,
  'color': instance.color,
  'rating': ?instance.rating,
  'location': ?instance.location?.toJson(),
};

JobMerchant _$JobMerchantFromJson(Map<String, dynamic> json) =>
    JobMerchant(id: json['id'] as String, name: json['name'] as String, phoneMasked: json['phone_masked'] as String);

Map<String, dynamic> _$JobMerchantToJson(JobMerchant instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'phone_masked': instance.phoneMasked,
};

OrderLine _$OrderLineFromJson(Map<String, dynamic> json) => OrderLine(
  name: json['name'] as String,
  quantity: (json['quantity'] as num).toInt(),
  addons: (json['addons'] as List<dynamic>).map((e) => e as String).toList(),
  note: json['note'] as String?,
  lineTotalCentavos: (json['line_total_centavos'] as num).toInt(),
);

Map<String, dynamic> _$OrderLineToJson(OrderLine instance) => <String, dynamic>{
  'name': instance.name,
  'quantity': instance.quantity,
  'addons': instance.addons,
  'note': ?instance.note,
  'line_total_centavos': instance.lineTotalCentavos,
};

JobFood _$JobFoodFromJson(Map<String, dynamic> json) => JobFood(
  items: (json['items'] as List<dynamic>).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
  subtotalCentavos: (json['subtotal_centavos'] as num).toInt(),
  prepTimeMinutes: (json['prep_time_minutes'] as num?)?.toInt(),
  readyAt: const NullableUtcDateTimeConverter().fromJson(json['ready_at'] as String?),
  isReady: json['is_ready'] as bool,
  riderPaysMerchantCentavos: (json['rider_pays_merchant_centavos'] as num?)?.toInt(),
);

Map<String, dynamic> _$JobFoodToJson(JobFood instance) => <String, dynamic>{
  'items': instance.items.map((e) => e.toJson()).toList(),
  'subtotal_centavos': instance.subtotalCentavos,
  'prep_time_minutes': ?instance.prepTimeMinutes,
  'ready_at': ?const NullableUtcDateTimeConverter().toJson(instance.readyAt),
  'is_ready': instance.isReady,
  'rider_pays_merchant_centavos': ?instance.riderPaysMerchantCentavos,
};

JobPabili _$JobPabiliFromJson(Map<String, dynamic> json) => JobPabili(
  storeName: json['store_name'] as String,
  items: (json['items'] as List<dynamic>).map((e) => PabiliItem.fromJson(e as Map<String, dynamic>)).toList(),
  receiptUrl: json['receipt_url'] as String?,
  itemTotalCentavos: (json['item_total_centavos'] as num?)?.toInt(),
);

Map<String, dynamic> _$JobPabiliToJson(JobPabili instance) => <String, dynamic>{
  'store_name': instance.storeName,
  'items': instance.items.map((e) => e.toJson()).toList(),
  'receipt_url': ?instance.receiptUrl,
  'item_total_centavos': ?instance.itemTotalCentavos,
};

JobPadala _$JobPadalaFromJson(Map<String, dynamic> json) => JobPadala(
  size: $enumDecode(_$PadalaSizeEnumMap, json['size']),
  description: json['description'] as String,
  recipientName: json['recipient_name'] as String,
  recipientPhone: json['recipient_phone'] as String,
  photoUrl: json['photo_url'] as String?,
);

Map<String, dynamic> _$JobPadalaToJson(JobPadala instance) => <String, dynamic>{
  'size': _$PadalaSizeEnumMap[instance.size]!,
  'description': instance.description,
  'recipient_name': instance.recipientName,
  'recipient_phone': instance.recipientPhone,
  'photo_url': ?instance.photoUrl,
};

Fare _$FareFromJson(Map<String, dynamic> json) => Fare(
  breakdown: (json['breakdown'] as List<dynamic>).map((e) => FareLine.fromJson(e as Map<String, dynamic>)).toList(),
  totalCentavos: (json['total_centavos'] as num).toInt(),
);

Map<String, dynamic> _$FareToJson(Fare instance) => <String, dynamic>{
  'breakdown': instance.breakdown.map((e) => e.toJson()).toList(),
  'total_centavos': instance.totalCentavos,
};

JobPayment _$JobPaymentFromJson(Map<String, dynamic> json) => JobPayment(
  method: $enumDecode(_$PaymentMethodEnumMap, json['method']),
  status: $enumDecode(_$PaymentStatusEnumMap, json['status']),
  checkoutUrl: json['checkout_url'] as String?,
);

Map<String, dynamic> _$JobPaymentToJson(JobPayment instance) => <String, dynamic>{
  'method': _$PaymentMethodEnumMap[instance.method]!,
  'status': _$PaymentStatusEnumMap[instance.status]!,
  'checkout_url': ?instance.checkoutUrl,
};

const _$PaymentMethodEnumMap = {PaymentMethod.cash: 'cash', PaymentMethod.gcash: 'gcash', PaymentMethod.maya: 'maya'};

const _$PaymentStatusEnumMap = {
  PaymentStatus.pending: 'pending',
  PaymentStatus.paid: 'paid',
  PaymentStatus.failed: 'failed',
  PaymentStatus.refunded: 'refunded',
};

TimelineEntry _$TimelineEntryFromJson(Map<String, dynamic> json) =>
    TimelineEntry(status: $enumDecode(_$JobStatusEnumMap, json['status']), at: const UtcDateTimeConverter().fromJson(json['at'] as String));

Map<String, dynamic> _$TimelineEntryToJson(TimelineEntry instance) => <String, dynamic>{
  'status': _$JobStatusEnumMap[instance.status]!,
  'at': const UtcDateTimeConverter().toJson(instance.at),
};

const _$JobStatusEnumMap = {
  JobStatus.pendingPayment: 'pending_payment',
  JobStatus.merchantPending: 'merchant_pending',
  JobStatus.merchantPreparing: 'merchant_preparing',
  JobStatus.searching: 'searching',
  JobStatus.riderAssigned: 'rider_assigned',
  JobStatus.arrivedPickup: 'arrived_pickup',
  JobStatus.itemsPurchased: 'items_purchased',
  JobStatus.pickedUp: 'picked_up',
  JobStatus.arrivedDropoff: 'arrived_dropoff',
  JobStatus.completed: 'completed',
  JobStatus.cancelled: 'cancelled',
};

Job _$JobFromJson(Map<String, dynamic> json) => Job(
  id: json['id'] as String,
  code: json['code'] as String,
  service: $enumDecode(_$ServiceTypeEnumMap, json['service']),
  status: $enumDecode(_$JobStatusEnumMap, json['status']),
  createdAt: const UtcDateTimeConverter().fromJson(json['created_at'] as String),
  updatedAt: const UtcDateTimeConverter().fromJson(json['updated_at'] as String),
  pickup: Stop.fromJson(json['pickup'] as Map<String, dynamic>),
  dropoff: Stop.fromJson(json['dropoff'] as Map<String, dynamic>),
  rider: json['rider'] == null ? null : JobRider.fromJson(json['rider'] as Map<String, dynamic>),
  merchant: json['merchant'] == null ? null : JobMerchant.fromJson(json['merchant'] as Map<String, dynamic>),
  food: json['food'] == null ? null : JobFood.fromJson(json['food'] as Map<String, dynamic>),
  pabili: json['pabili'] == null ? null : JobPabili.fromJson(json['pabili'] as Map<String, dynamic>),
  padala: json['padala'] == null ? null : JobPadala.fromJson(json['padala'] as Map<String, dynamic>),
  fare: Fare.fromJson(json['fare'] as Map<String, dynamic>),
  payment: JobPayment.fromJson(json['payment'] as Map<String, dynamic>),
  proofUrl: json['proof_url'] as String?,
  cancelReason: json['cancel_reason'] as String?,
  cancelledBy: $enumDecodeNullable(_$PartyRoleEnumMap, json['cancelled_by']),
  allowedActions: (json['allowed_actions'] as List<dynamic>).map((e) => e as String).toList(),
  timeline: (json['timeline'] as List<dynamic>).map((e) => TimelineEntry.fromJson(e as Map<String, dynamic>)).toList(),
  routePolyline: json['route_polyline'] as String?,
);

Map<String, dynamic> _$JobToJson(Job instance) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'service': _$ServiceTypeEnumMap[instance.service]!,
  'status': _$JobStatusEnumMap[instance.status]!,
  'created_at': const UtcDateTimeConverter().toJson(instance.createdAt),
  'updated_at': const UtcDateTimeConverter().toJson(instance.updatedAt),
  'pickup': instance.pickup.toJson(),
  'dropoff': instance.dropoff.toJson(),
  'rider': ?instance.rider?.toJson(),
  'merchant': ?instance.merchant?.toJson(),
  'food': ?instance.food?.toJson(),
  'pabili': ?instance.pabili?.toJson(),
  'padala': ?instance.padala?.toJson(),
  'fare': instance.fare.toJson(),
  'payment': instance.payment.toJson(),
  'proof_url': ?instance.proofUrl,
  'cancel_reason': ?instance.cancelReason,
  'cancelled_by': ?_$PartyRoleEnumMap[instance.cancelledBy],
  'allowed_actions': instance.allowedActions,
  'timeline': instance.timeline.map((e) => e.toJson()).toList(),
  'route_polyline': ?instance.routePolyline,
};

const _$PartyRoleEnumMap = {
  PartyRole.customer: 'customer',
  PartyRole.rider: 'rider',
  PartyRole.merchant: 'merchant',
  PartyRole.system: 'system',
};

ShareLink _$ShareLinkFromJson(Map<String, dynamic> json) =>
    ShareLink(url: json['url'] as String, expiresAt: const UtcDateTimeConverter().fromJson(json['expires_at'] as String));

Map<String, dynamic> _$ShareLinkToJson(ShareLink instance) => <String, dynamic>{
  'url': instance.url,
  'expires_at': const UtcDateTimeConverter().toJson(instance.expiresAt),
};

RatingInput _$RatingInputFromJson(Map<String, dynamic> json) => RatingInput(
  riderRating: (json['rider_rating'] as num).toInt(),
  riderTags: (json['rider_tags'] as List<dynamic>).map((e) => e as String).toList(),
  comment: json['comment'] as String?,
  merchantRating: (json['merchant_rating'] as num?)?.toInt(),
);

Map<String, dynamic> _$RatingInputToJson(RatingInput instance) => <String, dynamic>{
  'rider_rating': instance.riderRating,
  'rider_tags': instance.riderTags,
  'comment': ?instance.comment,
  'merchant_rating': ?instance.merchantRating,
};
