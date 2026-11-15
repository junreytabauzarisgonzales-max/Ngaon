import 'package:json_annotation/json_annotation.dart';

@JsonEnum()
enum AppLanguage { en, fil }

@JsonEnum()
enum UserRole { customer, rider, merchant }

@JsonEnum()
enum ServiceType { ride, food, pabili, padala }

@JsonEnum(fieldRename: FieldRename.snake)
enum JobStatus {
  pendingPayment,
  merchantPending,
  merchantPreparing,
  searching,
  riderAssigned,
  arrivedPickup,
  itemsPurchased,
  pickedUp,
  arrivedDropoff,
  completed,
  cancelled;

  bool get isFinal => this == completed || this == cancelled;

  static JobStatus fromWire(String v) => JobStatus.values.firstWhere((s) => s.wire == v);
}

@JsonEnum()
enum PaymentMethod {
  cash,
  gcash,
  maya;

  bool get isOnline => this != cash;
}

@JsonEnum()
enum PaymentStatus { pending, paid, failed, refunded }

@JsonEnum()
enum PartyRole { customer, rider, merchant, system }

@JsonEnum(fieldRename: FieldRename.snake)
enum RiderStatus { incomplete, pendingReview, approved, rejected, suspended }

@JsonEnum()
enum WalletTxType { topup, commission, earning, adjustment, payout }

@JsonEnum()
enum MerchantRole { owner, staff }

@JsonEnum(fieldRename: FieldRename.snake)
enum MerchantOrderStatus {
  @JsonValue('new')
  newOrder,
  preparing,
  ready,
  pickedUp,
  completed,
  rejected,
  cancelled,
}

@JsonEnum(fieldRename: FieldRename.snake)
enum PayoutType { payout, commissionInvoice }

@JsonEnum()
enum PayoutStatus { pending, paid, overdue }

@JsonEnum()
enum PadalaSize { small, medium, large }

@JsonEnum(fieldRename: FieldRename.snake)
enum RejectReason { outOfStock, tooBusy, closingSoon, other }

/// Purposes accepted by `POST /uploads`.
@JsonEnum(fieldRename: FieldRename.snake)
enum UploadPurpose {
  riderLicense,
  riderOrcr,
  riderSelfie,
  riderClearance,
  receipt,
  proofOfDelivery,
  parcelPhoto,
  chatImage,
  menuItemPhoto,
  merchantLogo,
  merchantCover,
}

/// Wire (snake_case) value of any contract enum, e.g. `JobStatus.riderAssigned`
/// -> `rider_assigned`. Matches what json_serializable emits.
extension EnumWire on Enum {
  String get wire {
    if (this == MerchantOrderStatus.newOrder) return 'new';
    return name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
  }
}
