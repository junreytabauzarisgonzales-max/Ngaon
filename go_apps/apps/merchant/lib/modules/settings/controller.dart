import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/merchant_session_service.dart';

class DayHours {
  DayHours(this.weekday, {this.open = false, this.opens = '08:00', this.closes = '20:00'});
  final int weekday;
  bool open;
  String opens;
  String closes;
}

class SettingsController extends GetxController {
  final MerchantAdminRepository repo = Get.find();
  final MerchantSessionService session = Get.find();
  final name = TextEditingController();
  final minOrder = TextEditingController();
  final prep = 15.obs;
  final days = <DayHours>[].obs;
  String? logoKey, coverKey;
  final saving = false.obs;

  @override
  void onInit() {
    super.onInit();
    final m = session.store.value!;
    name.text = m.name;
    minOrder.text = centavosToInput(m.minOrderCentavos);
    prep.value = m.prepTimeMinutes;
    days.assignAll([
      for (var d = 0; d < 7; d++)
        () {
          final h = m.hours.where((h) => h.weekday == d).firstOrNull;
          return DayHours(d, open: h != null, opens: h?.opens ?? '08:00', closes: h?.closes ?? '20:00');
        }(),
    ]);
  }

  Future<void> pickTime(DayHours d, bool opening) async {
    final cur = (opening ? d.opens : d.closes).split(':');
    final t = await showTimePicker(
      context: Get.context!,
      initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])),
    );
    if (t == null) return;
    final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    opening ? d.opens = s : d.closes = s;
    days.refresh();
  }

  Future<void> save() async {
    final min = parsePesosToCentavos(minOrder.text);
    if (name.text.trim().isEmpty || min == null) {
      GoErrors.toast('error.validation_failed'.tr);
      return;
    }
    saving.value = true;
    try {
      session.store.value = await repo.updateStore(
        StoreUpdate(
          name: name.text.trim(),
          minOrderCentavos: min,
          prepTimeMinutes: prep.value,
          logoKey: logoKey,
          coverKey: coverKey,
          hours: [
            for (final d in days)
              if (d.open) OpeningHours(weekday: d.weekday, opens: d.opens, closes: d.closes),
          ],
        ),
      );
      Get.back();
      GoErrors.toast('common.saved'.tr);
    } catch (e) {
      GoErrors.show(e);
    } finally {
      saving.value = false;
    }
  }
}
