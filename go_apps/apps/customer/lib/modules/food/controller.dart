import 'dart:async';

import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/cart_service.dart';

/// Nearby merchants list with search.
class FoodController extends GetxController {
  final MerchantsRepository repo = Get.find();
  final LocationService location = Get.find();
  final CartService cart = Get.find();
  final merchants = <Merchant>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();
  String? _cursor;
  bool hasMore = false;
  String _q = '';
  Timer? _debounce;
  LatLng _near = LatLng.bongao;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  Future<void> _start() async {
    _near = await location.current();
    await load();
  }

  Future<void> load({bool more = false}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = null;
    try {
      final page = await repo.list(near: _near, q: _q, cursor: more ? _cursor : null);
      more ? merchants.addAll(page.items) : merchants.assignAll(page.items);
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }

  void search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _q = q.trim();
      load();
    });
  }

  void open(Merchant m) => Get.toNamed(Routes.merchant, arguments: m.id);

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}

/// One merchant's menu + add-to-cart.
class MerchantMenuController extends GetxController {
  final MerchantsRepository repo = Get.find();
  final CartService cart = Get.find();
  late final String merchantId;
  final merchant = Rxn<Merchant>();
  final loading = true.obs;
  final error = Rxn<Object>();

  @override
  void onInit() {
    super.onInit();
    merchantId = Get.arguments as String;
    load();
  }

  Future<void> load() async {
    loading.value = merchant.value == null;
    error.value = null;
    try {
      merchant.value = await repo.get(merchantId);
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }

  /// Adds a configured item; asks before replacing another merchant's cart.
  Future<bool> addToCart(CartLine line) async {
    final m = merchant.value!;
    if (cart.belongsToOther(m.id)) {
      final ok = await confirmDialog(
        title: 'food.clear_cart_title'.tr,
        message: 'food.clear_cart_body'.trParams({'name': cart.merchantName.value}),
        confirmText: 'food.clear_cart'.tr,
      );
      if (!ok) return false;
    }
    cart.add(m, line);
    return true;
  }
}
