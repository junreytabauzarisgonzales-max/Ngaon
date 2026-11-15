import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/cart_service.dart';
import '../checkout/controller.dart';

class CartController extends GetxController {
  final CartService cart = Get.find();
  final MerchantsRepository merchants = Get.find();
  final GeoRepository geo = Get.find();
  final LocationService location = Get.find();
  final dropoff = Rxn<Stop>();
  final merchant = Rxn<Merchant>();

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  Future<void> _init() async {
    final id = cart.merchantId.value;
    if (id != null) merchant.value = await GoErrors.guard(() => merchants.get(id));
    try {
      final places = await geo.savedPlaces();
      final home = places.where((p) => p.label.toLowerCase() == 'home').firstOrNull;
      if (home != null) {
        dropoff.value ??= Stop(address: home.address, location: home.location);
      } else {
        final here = await location.current();
        dropoff.value ??= Stop(address: await geo.reverse(here), location: here);
      }
    } catch (_) {}
  }

  bool get belowMin => cart.subtotal < cart.minOrderCentavos.value;

  void checkout() {
    final m = merchant.value;
    if (m == null || dropoff.value == null || cart.isEmpty || belowMin) return;
    Get.toNamed(
      Routes.checkout,
      arguments: CheckoutArgs(
        title: m.name,
        request: QuoteRequest(
          service: ServiceType.food,
          pickup: Stop(address: m.address, location: m.location, contactName: m.name),
          dropoff: dropoff.value!,
          food: FoodQuoteInput(merchantId: m.id, items: cart.lines.map((l) => l.toQuote()).toList()),
        ),
        onPlaced: cart.clear,
      ),
    );
  }
}
