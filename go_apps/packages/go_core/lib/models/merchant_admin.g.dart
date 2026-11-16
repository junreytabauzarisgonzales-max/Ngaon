// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merchant_admin.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MerchantAccount _$MerchantAccountFromJson(Map<String, dynamic> json) =>
    MerchantAccount(
      merchant: Merchant.fromJson(json['merchant'] as Map<String, dynamic>),
      role: $enumDecode(_$MerchantRoleEnumMap, json['role']),
      staffName: json['staff_name'] as String,
    );

Map<String, dynamic> _$MerchantAccountToJson(MerchantAccount instance) =>
    <String, dynamic>{
      'merchant': instance.merchant.toJson(),
      'role': _$MerchantRoleEnumMap[instance.role]!,
      'staff_name': instance.staffName,
    };

const _$MerchantRoleEnumMap = {
  MerchantRole.owner: 'owner',
  MerchantRole.staff: 'staff',
};

MerchantOrderRider _$MerchantOrderRiderFromJson(Map<String, dynamic> json) =>
    MerchantOrderRider(
      name: json['name'] as String,
      photoUrl: json['photo_url'] as String?,
      plate: json['plate'] as String,
      phoneMasked: json['phone_masked'] as String,
    );

Map<String, dynamic> _$MerchantOrderRiderToJson(MerchantOrderRider instance) =>
    <String, dynamic>{
      'name': instance.name,
      'photo_url': ?instance.photoUrl,
      'plate': instance.plate,
      'phone_masked': instance.phoneMasked,
    };

MerchantOrder _$MerchantOrderFromJson(Map<String, dynamic> json) =>
    MerchantOrder(
      id: json['id'] as String,
      jobId: json['job_id'] as String,
      code: json['code'] as String,
      status: $enumDecode(_$MerchantOrderStatusEnumMap, json['status']),
      createdAt: const UtcDateTimeConverter().fromJson(
        json['created_at'] as String,
      ),
      merchantAcceptDeadline: const NullableUtcDateTimeConverter().fromJson(
        json['merchant_accept_deadline'] as String?,
      ),
      prepTimeMinutes: (json['prep_time_minutes'] as num?)?.toInt(),
      readyAt: const NullableUtcDateTimeConverter().fromJson(
        json['ready_at'] as String?,
      ),
      items: (json['items'] as List<dynamic>)
          .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotalCentavos: (json['subtotal_centavos'] as num).toInt(),
      commissionCentavos: (json['commission_centavos'] as num).toInt(),
      netCentavos: (json['net_centavos'] as num).toInt(),
      paymentMethod: $enumDecode(
        _$PaymentMethodEnumMap,
        json['payment_method'],
      ),
      riderPaysAtPickupCentavos: (json['rider_pays_at_pickup_centavos'] as num?)
          ?.toInt(),
      rider: json['rider'] == null
          ? null
          : MerchantOrderRider.fromJson(json['rider'] as Map<String, dynamic>),
      customerFirstName: json['customer_first_name'] as String,
      notes: json['notes'] as String?,
      rejectReason: $enumDecodeNullable(
        _$RejectReasonEnumMap,
        json['reject_reason'],
      ),
      allowedActions: (json['allowed_actions'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$MerchantOrderToJson(
  MerchantOrder instance,
) => <String, dynamic>{
  'id': instance.id,
  'job_id': instance.jobId,
  'code': instance.code,
  'status': _$MerchantOrderStatusEnumMap[instance.status]!,
  'created_at': const UtcDateTimeConverter().toJson(instance.createdAt),
  'merchant_accept_deadline': ?const NullableUtcDateTimeConverter().toJson(
    instance.merchantAcceptDeadline,
  ),
  'prep_time_minutes': ?instance.prepTimeMinutes,
  'ready_at': ?const NullableUtcDateTimeConverter().toJson(instance.readyAt),
  'items': instance.items.map((e) => e.toJson()).toList(),
  'subtotal_centavos': instance.subtotalCentavos,
  'commission_centavos': instance.commissionCentavos,
  'net_centavos': instance.netCentavos,
  'payment_method': _$PaymentMethodEnumMap[instance.paymentMethod]!,
  'rider_pays_at_pickup_centavos': ?instance.riderPaysAtPickupCentavos,
  'rider': ?instance.rider?.toJson(),
  'customer_first_name': instance.customerFirstName,
  'notes': ?instance.notes,
  'reject_reason': ?_$RejectReasonEnumMap[instance.rejectReason],
  'allowed_actions': instance.allowedActions,
};

const _$MerchantOrderStatusEnumMap = {
  MerchantOrderStatus.newOrder: 'new',
  MerchantOrderStatus.preparing: 'preparing',
  MerchantOrderStatus.ready: 'ready',
  MerchantOrderStatus.pickedUp: 'picked_up',
  MerchantOrderStatus.completed: 'completed',
  MerchantOrderStatus.rejected: 'rejected',
  MerchantOrderStatus.cancelled: 'cancelled',
};

const _$PaymentMethodEnumMap = {
  PaymentMethod.cash: 'cash',
  PaymentMethod.gcash: 'gcash',
  PaymentMethod.maya: 'maya',
};

const _$RejectReasonEnumMap = {
  RejectReason.outOfStock: 'out_of_stock',
  RejectReason.tooBusy: 'too_busy',
  RejectReason.closingSoon: 'closing_soon',
  RejectReason.other: 'other',
};

SalesDay _$SalesDayFromJson(Map<String, dynamic> json) => SalesDay(
  date: json['date'] as String,
  ordersCount: (json['orders_count'] as num).toInt(),
  grossCentavos: (json['gross_centavos'] as num).toInt(),
  netCentavos: (json['net_centavos'] as num).toInt(),
);

Map<String, dynamic> _$SalesDayToJson(SalesDay instance) => <String, dynamic>{
  'date': instance.date,
  'orders_count': instance.ordersCount,
  'gross_centavos': instance.grossCentavos,
  'net_centavos': instance.netCentavos,
};

SalesReport _$SalesReportFromJson(Map<String, dynamic> json) => SalesReport(
  from: json['from'] as String,
  to: json['to'] as String,
  ordersCount: (json['orders_count'] as num).toInt(),
  grossCentavos: (json['gross_centavos'] as num).toInt(),
  commissionCentavos: (json['commission_centavos'] as num).toInt(),
  netCentavos: (json['net_centavos'] as num).toInt(),
  days: (json['days'] as List<dynamic>)
      .map((e) => SalesDay.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SalesReportToJson(SalesReport instance) =>
    <String, dynamic>{
      'from': instance.from,
      'to': instance.to,
      'orders_count': instance.ordersCount,
      'gross_centavos': instance.grossCentavos,
      'commission_centavos': instance.commissionCentavos,
      'net_centavos': instance.netCentavos,
      'days': instance.days.map((e) => e.toJson()).toList(),
    };

Payout _$PayoutFromJson(Map<String, dynamic> json) => Payout(
  id: json['id'] as String,
  periodFrom: json['period_from'] as String,
  periodTo: json['period_to'] as String,
  amountCentavos: (json['amount_centavos'] as num).toInt(),
  type: $enumDecode(_$PayoutTypeEnumMap, json['type']),
  status: $enumDecode(_$PayoutStatusEnumMap, json['status']),
  paidAt: const NullableUtcDateTimeConverter().fromJson(
    json['paid_at'] as String?,
  ),
);

Map<String, dynamic> _$PayoutToJson(Payout instance) => <String, dynamic>{
  'id': instance.id,
  'period_from': instance.periodFrom,
  'period_to': instance.periodTo,
  'amount_centavos': instance.amountCentavos,
  'type': _$PayoutTypeEnumMap[instance.type]!,
  'status': _$PayoutStatusEnumMap[instance.status]!,
  'paid_at': ?const NullableUtcDateTimeConverter().toJson(instance.paidAt),
};

const _$PayoutTypeEnumMap = {
  PayoutType.payout: 'payout',
  PayoutType.commissionInvoice: 'commission_invoice',
};

const _$PayoutStatusEnumMap = {
  PayoutStatus.pending: 'pending',
  PayoutStatus.paid: 'paid',
  PayoutStatus.overdue: 'overdue',
};
