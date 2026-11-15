import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

enum SalesRange { today, week, custom }

class SalesController extends GetxController {
  final MerchantAdminRepository repo = Get.find();
  final range = SalesRange.today.obs;
  final report = Rxn<SalesReport>();
  final loading = false.obs;
  final error = Rxn<Object>();
  DateTimeRange? custom;

  static String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void onInit() {
    super.onInit();
    load();
  }

  (String, String) get dates {
    final n = manilaNow();
    final today = DateTime.utc(n.year, n.month, n.day);
    return switch (range.value) {
      SalesRange.today => (fmt(today), fmt(today)),
      SalesRange.week => (fmt(today.subtract(Duration(days: today.weekday - 1))), fmt(today)),
      SalesRange.custom => (fmt(custom!.start), fmt(custom!.end)),
    };
  }

  Future<void> select(SalesRange r) async {
    if (r == SalesRange.custom) {
      final picked = await showDateRangePicker(
        context: Get.context!,
        firstDate: DateTime(2025),
        lastDate: DateTime.now(),
        initialDateRange: custom,
      );
      if (picked == null) return;
      custom = picked;
    }
    range.value = r;
    await load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      final (from, to) = dates;
      report.value = await repo.sales(from: from, to: to);
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }
}
