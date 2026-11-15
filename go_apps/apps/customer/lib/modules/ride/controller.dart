import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../checkout/controller.dart';

class RideController extends GetxController {
  final LocationService location = Get.find();
  final GeoRepository geo = Get.find();
  final pickup = Rxn<Stop>();
  final dropoff = Rxn<Stop>();

  @override
  void onInit() {
    super.onInit();
    _defaultPickup();
  }

  Future<void> _defaultPickup() async {
    try {
      final here = await location.current();
      final address = await geo.reverse(here);
      pickup.value ??= Stop(address: address, location: here);
    } catch (_) {}
  }

  bool get ready => pickup.value != null && dropoff.value != null;

  void swap() {
    final p = pickup.value;
    pickup.value = dropoff.value;
    dropoff.value = p;
  }

  void seePrice() {
    if (!ready) return;
    Get.toNamed(
      Routes.checkout,
      arguments: CheckoutArgs(
        title: 'service.ride'.tr,
        request: QuoteRequest(service: ServiceType.ride, pickup: pickup.value!, dropoff: dropoff.value!),
      ),
    );
  }
}
