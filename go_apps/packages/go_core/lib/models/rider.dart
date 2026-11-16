import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';
import 'enums.dart';
import 'job.dart';

part 'rider.g.dart';

@JsonSerializable()
@UtcDateTimeConverter()
class JobOffer {
  JobOffer({required this.id, required this.job, required this.earningsCentavos, required this.pickupDistanceM, required this.expiresAt});
  final String id;
  final Job job;
  final int earningsCentavos;
  final int pickupDistanceM;
  final DateTime expiresAt;

  factory JobOffer.fromJson(Map<String, dynamic> json) => _$JobOfferFromJson(json);
  Map<String, dynamic> toJson() => _$JobOfferToJson(this);
}

@JsonSerializable()
class Vehicle {
  Vehicle({required this.plate, required this.makeModel, required this.color});
  final String plate;
  final String makeModel;
  final String color;

  factory Vehicle.fromJson(Map<String, dynamic> json) => _$VehicleFromJson(json);
  Map<String, dynamic> toJson() => _$VehicleToJson(this);
}

@JsonSerializable()
class RiderDocuments {
  RiderDocuments({required this.licenseKey, required this.orcrKey, required this.selfieKey, required this.clearanceKey});
  final String licenseKey;
  final String orcrKey;
  final String selfieKey;
  final String clearanceKey;

  factory RiderDocuments.fromJson(Map<String, dynamic> json) => _$RiderDocumentsFromJson(json);
  Map<String, dynamic> toJson() => _$RiderDocumentsToJson(this);
}

@JsonSerializable()
class RiderProfileInput {
  RiderProfileInput({required this.vehicle, required this.documents});
  final Vehicle vehicle;
  final RiderDocuments documents;

  factory RiderProfileInput.fromJson(Map<String, dynamic> json) => _$RiderProfileInputFromJson(json);
  Map<String, dynamic> toJson() => _$RiderProfileInputToJson(this);
}

@JsonSerializable()
class RiderProfile {
  RiderProfile({
    required this.id,
    required this.userId,
    required this.status,
    this.rejectionReason,
    required this.isOnline,
    this.vehicle,
    this.rating,
    required this.balanceCentavos,
    required this.minBalanceCentavos,
    this.kycStatus,
  });
  final String id;
  final String userId;
  final RiderStatus status;
  final String? rejectionReason;
  final bool isOnline;
  final Vehicle? vehicle;
  final double? rating;
  final int balanceCentavos;
  final int minBalanceCentavos;

  /// ADDED: Didit identity verification status when KYC is enabled:
  /// not_started | in_progress | in_review | approved | declined | expired.
  final String? kycStatus;

  bool get kycRequired => kycStatus != null;
  bool get kycApproved => kycStatus == 'approved';

  bool get hasEnoughBalance => balanceCentavos >= minBalanceCentavos;

  factory RiderProfile.fromJson(Map<String, dynamic> json) => _$RiderProfileFromJson(json);
  Map<String, dynamic> toJson() => _$RiderProfileToJson(this);
}

@JsonSerializable()
@UtcDateTimeConverter()
class WalletTransaction {
  WalletTransaction({
    required this.id,
    required this.type,
    required this.amountCentavos,
    required this.balanceAfterCentavos,
    this.jobId,
    this.note,
    required this.createdAt,
  });
  final String id;
  final WalletTxType type;
  final int amountCentavos;
  final int balanceAfterCentavos;
  final String? jobId;
  final String? note;
  final DateTime createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) => _$WalletTransactionFromJson(json);
  Map<String, dynamic> toJson() => _$WalletTransactionToJson(this);
}

@JsonSerializable()
class Wallet {
  Wallet({required this.balanceCentavos, required this.minBalanceCentavos});
  final int balanceCentavos;
  final int minBalanceCentavos;

  factory Wallet.fromJson(Map<String, dynamic> json) => _$WalletFromJson(json);
  Map<String, dynamic> toJson() => _$WalletToJson(this);
}

@JsonSerializable()
class TopupResult {
  TopupResult({required this.topupId, required this.checkoutUrl});
  final String topupId;
  final String checkoutUrl;

  factory TopupResult.fromJson(Map<String, dynamic> json) => _$TopupResultFromJson(json);
  Map<String, dynamic> toJson() => _$TopupResultToJson(this);
}

@JsonSerializable()
class EarningsDay {
  EarningsDay({required this.date, required this.totalCentavos, required this.jobsCount});
  final String date;
  final int totalCentavos;
  final int jobsCount;

  factory EarningsDay.fromJson(Map<String, dynamic> json) => _$EarningsDayFromJson(json);
  Map<String, dynamic> toJson() => _$EarningsDayToJson(this);
}

@JsonSerializable()
class Earnings {
  Earnings({required this.totalCentavos, required this.jobsCount, required this.days});
  final int totalCentavos;
  final int jobsCount;
  final List<EarningsDay> days;

  factory Earnings.fromJson(Map<String, dynamic> json) => _$EarningsFromJson(json);
  Map<String, dynamic> toJson() => _$EarningsToJson(this);
}

/// ADDED: response of `POST /rider/kyc/session`.
@JsonSerializable()
class KycSession {
  KycSession({required this.sessionId, required this.url, required this.kycStatus});
  final String sessionId;
  final String url;
  final String kycStatus;

  factory KycSession.fromJson(Map<String, dynamic> json) => _$KycSessionFromJson(json);
  Map<String, dynamic> toJson() => _$KycSessionToJson(this);
}
