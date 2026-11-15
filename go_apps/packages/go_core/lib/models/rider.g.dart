// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rider.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JobOffer _$JobOfferFromJson(Map<String, dynamic> json) => JobOffer(
  id: json['id'] as String,
  job: Job.fromJson(json['job'] as Map<String, dynamic>),
  earningsCentavos: (json['earnings_centavos'] as num).toInt(),
  pickupDistanceM: (json['pickup_distance_m'] as num).toInt(),
  expiresAt: const UtcDateTimeConverter().fromJson(json['expires_at'] as String),
);

Map<String, dynamic> _$JobOfferToJson(JobOffer instance) => <String, dynamic>{
  'id': instance.id,
  'job': instance.job.toJson(),
  'earnings_centavos': instance.earningsCentavos,
  'pickup_distance_m': instance.pickupDistanceM,
  'expires_at': const UtcDateTimeConverter().toJson(instance.expiresAt),
};

Vehicle _$VehicleFromJson(Map<String, dynamic> json) =>
    Vehicle(plate: json['plate'] as String, makeModel: json['make_model'] as String, color: json['color'] as String);

Map<String, dynamic> _$VehicleToJson(Vehicle instance) => <String, dynamic>{
  'plate': instance.plate,
  'make_model': instance.makeModel,
  'color': instance.color,
};

RiderDocuments _$RiderDocumentsFromJson(Map<String, dynamic> json) => RiderDocuments(
  licenseKey: json['license_key'] as String,
  orcrKey: json['orcr_key'] as String,
  selfieKey: json['selfie_key'] as String,
  clearanceKey: json['clearance_key'] as String,
);

Map<String, dynamic> _$RiderDocumentsToJson(RiderDocuments instance) => <String, dynamic>{
  'license_key': instance.licenseKey,
  'orcr_key': instance.orcrKey,
  'selfie_key': instance.selfieKey,
  'clearance_key': instance.clearanceKey,
};

RiderProfileInput _$RiderProfileInputFromJson(Map<String, dynamic> json) => RiderProfileInput(
  vehicle: Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
  documents: RiderDocuments.fromJson(json['documents'] as Map<String, dynamic>),
);

Map<String, dynamic> _$RiderProfileInputToJson(RiderProfileInput instance) => <String, dynamic>{
  'vehicle': instance.vehicle.toJson(),
  'documents': instance.documents.toJson(),
};

RiderProfile _$RiderProfileFromJson(Map<String, dynamic> json) => RiderProfile(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  status: $enumDecode(_$RiderStatusEnumMap, json['status']),
  rejectionReason: json['rejection_reason'] as String?,
  isOnline: json['is_online'] as bool,
  vehicle: json['vehicle'] == null ? null : Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
  rating: (json['rating'] as num?)?.toDouble(),
  balanceCentavos: (json['balance_centavos'] as num).toInt(),
  minBalanceCentavos: (json['min_balance_centavos'] as num).toInt(),
);

Map<String, dynamic> _$RiderProfileToJson(RiderProfile instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'status': _$RiderStatusEnumMap[instance.status]!,
  'rejection_reason': ?instance.rejectionReason,
  'is_online': instance.isOnline,
  'vehicle': ?instance.vehicle?.toJson(),
  'rating': ?instance.rating,
  'balance_centavos': instance.balanceCentavos,
  'min_balance_centavos': instance.minBalanceCentavos,
};

const _$RiderStatusEnumMap = {
  RiderStatus.incomplete: 'incomplete',
  RiderStatus.pendingReview: 'pending_review',
  RiderStatus.approved: 'approved',
  RiderStatus.rejected: 'rejected',
  RiderStatus.suspended: 'suspended',
};

WalletTransaction _$WalletTransactionFromJson(Map<String, dynamic> json) => WalletTransaction(
  id: json['id'] as String,
  type: $enumDecode(_$WalletTxTypeEnumMap, json['type']),
  amountCentavos: (json['amount_centavos'] as num).toInt(),
  balanceAfterCentavos: (json['balance_after_centavos'] as num).toInt(),
  jobId: json['job_id'] as String?,
  note: json['note'] as String?,
  createdAt: const UtcDateTimeConverter().fromJson(json['created_at'] as String),
);

Map<String, dynamic> _$WalletTransactionToJson(WalletTransaction instance) => <String, dynamic>{
  'id': instance.id,
  'type': _$WalletTxTypeEnumMap[instance.type]!,
  'amount_centavos': instance.amountCentavos,
  'balance_after_centavos': instance.balanceAfterCentavos,
  'job_id': ?instance.jobId,
  'note': ?instance.note,
  'created_at': const UtcDateTimeConverter().toJson(instance.createdAt),
};

const _$WalletTxTypeEnumMap = {
  WalletTxType.topup: 'topup',
  WalletTxType.commission: 'commission',
  WalletTxType.earning: 'earning',
  WalletTxType.adjustment: 'adjustment',
  WalletTxType.payout: 'payout',
};

Wallet _$WalletFromJson(Map<String, dynamic> json) =>
    Wallet(balanceCentavos: (json['balance_centavos'] as num).toInt(), minBalanceCentavos: (json['min_balance_centavos'] as num).toInt());

Map<String, dynamic> _$WalletToJson(Wallet instance) => <String, dynamic>{
  'balance_centavos': instance.balanceCentavos,
  'min_balance_centavos': instance.minBalanceCentavos,
};

TopupResult _$TopupResultFromJson(Map<String, dynamic> json) =>
    TopupResult(topupId: json['topup_id'] as String, checkoutUrl: json['checkout_url'] as String);

Map<String, dynamic> _$TopupResultToJson(TopupResult instance) => <String, dynamic>{
  'topup_id': instance.topupId,
  'checkout_url': instance.checkoutUrl,
};

EarningsDay _$EarningsDayFromJson(Map<String, dynamic> json) => EarningsDay(
  date: json['date'] as String,
  totalCentavos: (json['total_centavos'] as num).toInt(),
  jobsCount: (json['jobs_count'] as num).toInt(),
);

Map<String, dynamic> _$EarningsDayToJson(EarningsDay instance) => <String, dynamic>{
  'date': instance.date,
  'total_centavos': instance.totalCentavos,
  'jobs_count': instance.jobsCount,
};

Earnings _$EarningsFromJson(Map<String, dynamic> json) => Earnings(
  totalCentavos: (json['total_centavos'] as num).toInt(),
  jobsCount: (json['jobs_count'] as num).toInt(),
  days: (json['days'] as List<dynamic>).map((e) => EarningsDay.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$EarningsToJson(Earnings instance) => <String, dynamic>{
  'total_centavos': instance.totalCentavos,
  'jobs_count': instance.jobsCount,
  'days': instance.days.map((e) => e.toJson()).toList(),
};
