import 'package:get/get.dart';

import '../services/active_jobs_service.dart';
import '../services/cart_service.dart';

/// App-wide services. Repositories are registered by go_core
/// (`GoRepositoryBinding`: HTTP or mock depending on USE_MOCK_API).
class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(CartService(), permanent: true);
    Get.put(ActiveJobsService(), permanent: true);
  }
}
