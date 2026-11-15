import 'package:json_annotation/json_annotation.dart';

import '../utils/time.dart';
import 'geo.dart';

part 'merchant.g.dart';

@JsonSerializable()
@NullableUtcDateTimeConverter()
class Merchant {
  Merchant({
    required this.id,
    required this.name,
    this.logoUrl,
    this.coverUrl,
    required this.address,
    required this.location,
    required this.isOpen,
    this.pausedUntil,
    required this.hours,
    required this.prepTimeMinutes,
    this.rating,
    required this.minOrderCentavos,
    this.distanceM,
    this.menu,
  });

  final String id;
  final String name;
  final String? logoUrl;
  final String? coverUrl;
  final String address;
  final LatLng location;
  final bool isOpen;
  final DateTime? pausedUntil;
  final List<OpeningHours> hours;
  final int prepTimeMinutes;
  final double? rating;
  final int minOrderCentavos;
  final int? distanceM;
  final List<MenuCategory>? menu;

  bool get isPaused => pausedUntil != null && pausedUntil!.isAfter(DateTime.now());
  bool get acceptsOrders => isOpen && !isPaused;

  factory Merchant.fromJson(Map<String, dynamic> json) => _$MerchantFromJson(json);
  Map<String, dynamic> toJson() => _$MerchantToJson(this);
}

@JsonSerializable()
class OpeningHours {
  OpeningHours({required this.weekday, required this.opens, required this.closes});

  /// 0 = Sunday.
  final int weekday;
  final String opens;
  final String closes;

  factory OpeningHours.fromJson(Map<String, dynamic> json) => _$OpeningHoursFromJson(json);
  Map<String, dynamic> toJson() => _$OpeningHoursToJson(this);
}

@JsonSerializable()
class MenuCategory {
  MenuCategory({required this.id, required this.name, required this.sortOrder, required this.items});
  final String id;
  final String name;
  final int sortOrder;
  final List<MenuItem> items;

  factory MenuCategory.fromJson(Map<String, dynamic> json) => _$MenuCategoryFromJson(json);
  Map<String, dynamic> toJson() => _$MenuCategoryToJson(this);
}

@JsonSerializable()
class MenuItem {
  MenuItem({
    required this.id,
    required this.categoryId,
    required this.name,
    this.description,
    this.photoUrl,
    required this.priceCentavos,
    required this.isAvailable,
    required this.addonGroups,
  });

  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final String? photoUrl;
  final int priceCentavos;
  final bool isAvailable;
  final List<AddonGroup> addonGroups;

  factory MenuItem.fromJson(Map<String, dynamic> json) => _$MenuItemFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemToJson(this);
}

@JsonSerializable()
class AddonGroup {
  AddonGroup({required this.id, required this.name, required this.minSelect, required this.maxSelect, required this.options});
  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<AddonOption> options;

  factory AddonGroup.fromJson(Map<String, dynamic> json) => _$AddonGroupFromJson(json);
  Map<String, dynamic> toJson() => _$AddonGroupToJson(this);
}

@JsonSerializable()
class AddonOption {
  AddonOption({required this.id, required this.name, required this.priceCentavos, required this.isAvailable});
  final String id;
  final String name;
  final int priceCentavos;
  final bool isAvailable;

  factory AddonOption.fromJson(Map<String, dynamic> json) => _$AddonOptionFromJson(json);
  Map<String, dynamic> toJson() => _$AddonOptionToJson(this);
}

/// Body for `POST/PUT /merchant/menu/items`. `id` present on a group/option
/// means update, absent means create; groups/options missing are deleted.
@JsonSerializable()
class MenuItemInput {
  MenuItemInput({
    required this.categoryId,
    required this.name,
    this.description,
    this.photoKey,
    required this.priceCentavos,
    required this.isAvailable,
    required this.addonGroups,
  });

  final String categoryId;
  final String name;
  final String? description;
  final String? photoKey;
  final int priceCentavos;
  final bool isAvailable;
  final List<AddonGroupInput> addonGroups;

  factory MenuItemInput.fromJson(Map<String, dynamic> json) => _$MenuItemInputFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemInputToJson(this);
}

@JsonSerializable()
class AddonGroupInput {
  AddonGroupInput({this.id, required this.name, required this.minSelect, required this.maxSelect, required this.options});
  final String? id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<AddonOptionInput> options;

  factory AddonGroupInput.fromJson(Map<String, dynamic> json) => _$AddonGroupInputFromJson(json);
  Map<String, dynamic> toJson() => _$AddonGroupInputToJson(this);
}

@JsonSerializable()
class AddonOptionInput {
  AddonOptionInput({this.id, required this.name, required this.priceCentavos, required this.isAvailable});
  final String? id;
  final String name;
  final int priceCentavos;
  final bool isAvailable;

  factory AddonOptionInput.fromJson(Map<String, dynamic> json) => _$AddonOptionInputFromJson(json);
  Map<String, dynamic> toJson() => _$AddonOptionInputToJson(this);
}
