import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

enum EarningsRange { today, week }

class EarningsController extends GetxController {
  final RiderRepository repo = Get.find();
  final range = EarningsRange.today.obs;
  final earnings = Rxn<Earnings>();
  final jobs = <Job>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();
  String? _cursor;
  bool hasMore = false;

  @override
  void onInit() {
    super.onInit();
    load();
    ever(range, (_) => load());
  }

  (String, String) get _dates {
    final now = manilaNow();
    final today = DateTime.utc(now.year, now.month, now.day);
    // Week starts Monday (Manila).
    final from = range.value == EarningsRange.today ? today : today.subtract(Duration(days: today.weekday - 1));
    String f(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return (f(from), f(today));
  }

  Future<void> load({bool more = false}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = null;
    final (from, to) = _dates;
    try {
      if (!more) earnings.value = await repo.earnings(from: from, to: to);
      final page = await repo.jobs(cursor: more ? _cursor : null, from: from, to: to);
      more ? jobs.addAll(page.items) : jobs.assignAll(page.items);
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }
}
