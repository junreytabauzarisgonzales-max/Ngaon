import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';
import 'enums.dart';
import 'job.dart';
import 'merchant.dart';

part 'merchant_admin.g.dart';

@JsonSerializable()
class MerchantAccount {
  MerchantAccount({required this.merchant, required this.role, required this.staffName});
  final Merchant merchant;
  final MerchantRole role;
  final String staffName;

  factory MerchantAccount.fromJson(Map<String, dynamic> json) => _$MerchantAccountFromJson(json);
  Map<String, dynamic> toJson() => _$MerchantAccountToJson(this);
}

@JsonSerializable()
class MerchantOrderRider {
  MerchantOrderRider({required this.name, this.photoUrl, required this.plate, required this.phoneMasked});
  final String name;
  final String? photoUrl;
  final String plate;
  final String phoneMasked;

  factory MerchantOrderRider.fromJson(Map<String, dynamic> json) => _$MerchantOrderRiderFromJson(json);
  Map<String, dynamic> toJson() => _$MerchantOrderRiderToJson(this);
}

/// Values found in `MerchantOrder.allowed_actions`.
class OrderActions {
  OrderActions._();
  static const accept = 'accept';
  static const reject = 'reject';
  static const ready = 'ready';
}

@JsonSerializable()
@UtcDateTimeConverter()
@NullableUtcDateTimeConverter()
class MerchantOrder {
  MerchantOrder({
    required this.id,
    required this.jobId,
    required this.code,
    required this.status,
    required this.createdAt,
    this.merchantAcceptDeadline,
    this.prepTimeMinutes,
    this.readyAt,
    required this.items,
    required this.subtotalCentavos,
    required this.commissionCentavos,
    required this.netCentavos,
    required this.paymentMethod,
    this.riderPaysAtPickupCentavos,
    this.rider,
    required this.customerFirstName,
    this.notes,
    this.rejectReason,
    required this.allowedActions,
  });

  final String id;
  final String jobId;
  final String code;
  final MerchantOrderStatus status;
  final DateTime createdAt;
  final DateTime? merchantAcceptDeadline;
  final int? prepTimeMinutes;
  final DateTime? readyAt;
  final List<OrderLine> items;
  final int subtotalCentavos;
  final int commissionCentavos;
  final int netCentavos;
  final PaymentMethod paymentMethod;
  final int? riderPaysAtPickupCentavos;
  final MerchantOrderRider? rider;
  final String customerFirstName;
  final String? notes;
  final RejectReason? rejectReason;
  final List<String> allowedActions;

  bool can(String action) => allowedActions.contains(action);
  int get itemCount => items.fold(0, (s, i) => s + i.quantity);

  factory MerchantOrder.fromJson(Map<String, dynamic> json) => _$MerchantOrderFromJson(json);
  Map<String, dynamic> toJson() => _$MerchantOrderToJson(this);
}

@JsonSerializable()
class SalesDay {
  SalesDay({required this.date, required this.ordersCount, required this.grossCentavos, required this.netCentavos});
  final String date;
  final int ordersCount;
  final int grossCentavos;
  final int netCentavos;

  factory SalesDay.fromJson(Map<String, dynamic> json) => _$SalesDayFromJson(json);
  Map<String, dynamic> toJson() => _$SalesDayToJson(this);
}

@JsonSerializable()
class SalesReport {
  SalesReport({
    required this.from,
    required this.to,
    required this.ordersCount,
    required this.grossCentavos,
    required this.commissionCentavos,
    required this.netCentavos,
    required this.days,
  });
  final String from;
  final String to;
  final int ordersCount;
  final int grossCentavos;
  final int commissionCentavos;
  final int netCentavos;
  final List<SalesDay> days;

  factory SalesReport.fromJson(Map<String, dynamic> json) => _$SalesReportFromJson(json);
  Map<String, dynamic> toJson() => _$SalesReportToJson(this);
}

@JsonSerializable()
@NullableUtcDateTimeConverter()
class Payout {
  Payout({
    required this.id,
    required this.periodFrom,
    required this.periodTo,
    required this.amountCentavos,
    required this.type,
    required this.status,
    this.paidAt,
  });
  final String id;
  final String periodFrom;
  final String periodTo;
  final int amountCentavos;
  final PayoutType type;
  final PayoutStatus status;
  final DateTime? paidAt;

  factory Payout.fromJson(Map<String, dynamic> json) => _$PayoutFromJson(json);
  Map<String, dynamic> toJson() => _$PayoutToJson(this);
}

/// Body for `PATCH /merchant/store`. Only non-null fields are sent.
/// [clearPause] sends `paused_until: null` explicitly to resume orders.
class StoreUpdate {
  StoreUpdate({
    this.isOpen,
    this.pausedUntil,
    this.clearPause = false,
    this.prepTimeMinutes,
    this.minOrderCentavos,
    this.hours,
    this.logoKey,
    this.coverKey,
    this.name,
  });
  final bool? isOpen;
  final DateTime? pausedUntil;
  final bool clearPause;
  final int? prepTimeMinutes;
  final int? minOrderCentavos;
  final List<OpeningHours>? hours;
  final String? logoKey;
  final String? coverKey;
  final String? name;

  Map<String, dynamic> toJson() => {
    if (isOpen != null) 'is_open': isOpen,
    if (pausedUntil != null) 'paused_until': toIsoUtc(pausedUntil!),
    if (clearPause) 'paused_until': null,
    if (prepTimeMinutes != null) 'prep_time_minutes': prepTimeMinutes,
    if (minOrderCentavos != null) 'min_order_centavos': minOrderCentavos,
    if (hours != null) 'hours': hours!.map((h) => h.toJson()).toList(),
    if (logoKey != null) 'logo_key': logoKey,
    if (coverKey != null) 'cover_key': coverKey,
    if (name != null) 'name': name,
  };
}
