import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../checkout/controller.dart';

class PadalaController extends GetxController {
  final StorageService storage = Get.find();
  static const draftKey = 'padala';

  final pickup = Rxn<Stop>();
  final dropoff = Rxn<Stop>();
  final recipientName = TextEditingController();
  final recipientPhone = TextEditingController();
  final description = TextEditingController();
  final size = PadalaSize.small.obs;
  final photoKey = RxnString();
  final phoneError = RxnString();

  @override
  void onInit() {
    super.onInit();
    final d = storage.readDraft(draftKey);
    if (d != null) {
      if (d['pickup'] != null) pickup.value = Stop.fromJson(Map<String, dynamic>.from(d['pickup'] as Map));
      if (d['dropoff'] != null) dropoff.value = Stop.fromJson(Map<String, dynamic>.from(d['dropoff'] as Map));
      recipientName.text = d['name'] as String? ?? '';
      recipientPhone.text = d['phone'] as String? ?? '';
      description.text = d['desc'] as String? ?? '';
      size.value = PadalaSize.values.byName(d['size'] as String? ?? 'small');
    }
    for (final c in [recipientName, recipientPhone, description]) {
      c.addListener(save);
    }
    ever(size, (_) => save());
  }

  void save() => storage.writeDraft(draftKey, {
    'pickup': pickup.value?.toJson(),
    'dropoff': dropoff.value?.toJson(),
    'name': recipientName.text,
    'phone': recipientPhone.text,
    'desc': description.text,
    'size': size.value.name,
  });

  void next() {
    final phone = PhPhone.toE164(recipientPhone.text);
    phoneError.value = phone == null ? 'login.invalid_phone'.tr : null;
    if (pickup.value == null ||
        dropoff.value == null ||
        recipientName.text.trim().isEmpty ||
        description.text.trim().isEmpty ||
        phone == null) {
      if (phone != null) GoErrors.toast('pabili.fill_all'.tr);
      return;
    }
    final name = recipientName.text.trim();
    Get.toNamed(
      Routes.checkout,
      arguments: CheckoutArgs(
        title: 'service.padala'.tr,
        request: QuoteRequest(
          service: ServiceType.padala,
          pickup: pickup.value!,
          dropoff: dropoff.value!.copyWith(contactName: name, contactPhone: phone),
          padala: PadalaQuoteInput(
            size: size.value,
            description: description.text.trim(),
            recipientName: name,
            recipientPhone: phone,
            photoKey: photoKey.value,
          ),
        ),
        onPlaced: () => storage.clearDraft(draftKey),
      ),
    );
  }
}
