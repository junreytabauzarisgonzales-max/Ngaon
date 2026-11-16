// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merchant.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Merchant _$MerchantFromJson(Map<String, dynamic> json) => Merchant(
  id: json['id'] as String,
  name: json['name'] as String,
  logoUrl: json['logo_url'] as String?,
  coverUrl: json['cover_url'] as String?,
  address: json['address'] as String,
  location: LatLng.fromJson(json['location'] as Map<String, dynamic>),
  isOpen: json['is_open'] as bool,
  pausedUntil: const NullableUtcDateTimeConverter().fromJson(json['paused_until'] as String?),
  hours: (json['hours'] as List<dynamic>).map((e) => OpeningHours.fromJson(e as Map<String, dynamic>)).toList(),
  prepTimeMinutes: (json['prep_time_minutes'] as num).toInt(),
  rating: (json['rating'] as num?)?.toDouble(),
  minOrderCentavos: (json['min_order_centavos'] as num).toInt(),
  distanceM: (json['distance_m'] as num?)?.toInt(),
  menu: (json['menu'] as List<dynamic>?)?.map((e) => MenuCategory.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$MerchantToJson(Merchant instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'logo_url': ?instance.logoUrl,
  'cover_url': ?instance.coverUrl,
  'address': instance.address,
  'location': instance.location.toJson(),
  'is_open': instance.isOpen,
  'paused_until': ?const NullableUtcDateTimeConverter().toJson(instance.pausedUntil),
  'hours': instance.hours.map((e) => e.toJson()).toList(),
  'prep_time_minutes': instance.prepTimeMinutes,
  'rating': ?instance.rating,
  'min_order_centavos': instance.minOrderCentavos,
  'distance_m': ?instance.distanceM,
  'menu': ?instance.menu?.map((e) => e.toJson()).toList(),
};

OpeningHours _$OpeningHoursFromJson(Map<String, dynamic> json) =>
    OpeningHours(weekday: (json['weekday'] as num).toInt(), opens: json['opens'] as String, closes: json['closes'] as String);

Map<String, dynamic> _$OpeningHoursToJson(OpeningHours instance) => <String, dynamic>{
  'weekday': instance.weekday,
  'opens': instance.opens,
  'closes': instance.closes,
};

MenuCategory _$MenuCategoryFromJson(Map<String, dynamic> json) => MenuCategory(
  id: json['id'] as String,
  name: json['name'] as String,
  sortOrder: (json['sort_order'] as num).toInt(),
  items: (json['items'] as List<dynamic>).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$MenuCategoryToJson(MenuCategory instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'sort_order': instance.sortOrder,
  'items': instance.items.map((e) => e.toJson()).toList(),
};

MenuItem _$MenuItemFromJson(Map<String, dynamic> json) => MenuItem(
  id: json['id'] as String,
  categoryId: json['category_id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  photoUrl: json['photo_url'] as String?,
  priceCentavos: (json['price_centavos'] as num).toInt(),
  isAvailable: json['is_available'] as bool,
  addonGroups: (json['addon_groups'] as List<dynamic>).map((e) => AddonGroup.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$MenuItemToJson(MenuItem instance) => <String, dynamic>{
  'id': instance.id,
  'category_id': instance.categoryId,
  'name': instance.name,
  'description': ?instance.description,
  'photo_url': ?instance.photoUrl,
  'price_centavos': instance.priceCentavos,
  'is_available': instance.isAvailable,
  'addon_groups': instance.addonGroups.map((e) => e.toJson()).toList(),
};

AddonGroup _$AddonGroupFromJson(Map<String, dynamic> json) => AddonGroup(
  id: json['id'] as String,
  name: json['name'] as String,
  minSelect: (json['min_select'] as num).toInt(),
  maxSelect: (json['max_select'] as num).toInt(),
  options: (json['options'] as List<dynamic>).map((e) => AddonOption.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$AddonGroupToJson(AddonGroup instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'min_select': instance.minSelect,
  'max_select': instance.maxSelect,
  'options': instance.options.map((e) => e.toJson()).toList(),
};

AddonOption _$AddonOptionFromJson(Map<String, dynamic> json) => AddonOption(
  id: json['id'] as String,
  name: json['name'] as String,
  priceCentavos: (json['price_centavos'] as num).toInt(),
  isAvailable: json['is_available'] as bool,
);

Map<String, dynamic> _$AddonOptionToJson(AddonOption instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'price_centavos': instance.priceCentavos,
  'is_available': instance.isAvailable,
};

MenuItemInput _$MenuItemInputFromJson(Map<String, dynamic> json) => MenuItemInput(
  categoryId: json['category_id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  photoKey: json['photo_key'] as String?,
  priceCentavos: (json['price_centavos'] as num).toInt(),
  isAvailable: json['is_available'] as bool,
  addonGroups: (json['addon_groups'] as List<dynamic>).map((e) => AddonGroupInput.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$MenuItemInputToJson(MenuItemInput instance) => <String, dynamic>{
  'category_id': instance.categoryId,
  'name': instance.name,
  'description': ?instance.description,
  'photo_key': ?instance.photoKey,
  'price_centavos': instance.priceCentavos,
  'is_available': instance.isAvailable,
  'addon_groups': instance.addonGroups.map((e) => e.toJson()).toList(),
};

AddonGroupInput _$AddonGroupInputFromJson(Map<String, dynamic> json) => AddonGroupInput(
  id: json['id'] as String?,
  name: json['name'] as String,
  minSelect: (json['min_select'] as num).toInt(),
  maxSelect: (json['max_select'] as num).toInt(),
  options: (json['options'] as List<dynamic>).map((e) => AddonOptionInput.fromJson(e as Map<String, dynamic>)).toList(),
);

Map<String, dynamic> _$AddonGroupInputToJson(AddonGroupInput instance) => <String, dynamic>{
  'id': ?instance.id,
  'name': instance.name,
  'min_select': instance.minSelect,
  'max_select': instance.maxSelect,
  'options': instance.options.map((e) => e.toJson()).toList(),
};

AddonOptionInput _$AddonOptionInputFromJson(Map<String, dynamic> json) => AddonOptionInput(
  id: json['id'] as String?,
  name: json['name'] as String,
  priceCentavos: (json['price_centavos'] as num).toInt(),
  isAvailable: json['is_available'] as bool,
);

Map<String, dynamic> _$AddonOptionInputToJson(AddonOptionInput instance) => <String, dynamic>{
  'id': ?instance.id,
  'name': instance.name,
  'price_centavos': instance.priceCentavos,
  'is_available': instance.isAvailable,
};
