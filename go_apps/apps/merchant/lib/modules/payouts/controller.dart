import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

class PayoutsController extends GetxController {
  final MerchantAdminRepository repo = Get.find();
  final items = <Payout>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();
  String? _cursor;
  bool hasMore = false;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load({bool more = false}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = null;
    try {
      final p = await repo.payouts(cursor: more ? _cursor : null);
      more ? items.addAll(p.items) : items.assignAll(p.items);
      _cursor = p.nextCursor;
      hasMore = p.hasMore;
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }
}
