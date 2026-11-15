import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/active_jobs_service.dart';

class CheckoutArgs {
  const CheckoutArgs({required this.title, required this.request, this.onPlaced});
  final String title;
  final QuoteRequest request;

  /// Clears drafts / cart once the job exists.
  final void Function()? onPlaced;
}

/// Shared by all services: quote -> payment method -> POST /jobs.
class CheckoutController extends GetxController {
  final JobsRepository jobs = Get.find();
  late final CheckoutArgs args;

  final quote = Rxn<Quote>();
  final loading = true.obs;
  final placing = false.obs;
  final error = Rxn<Object>();
  final method = PaymentMethod.cash.obs;
  final notes = ''.obs;

  /// Reused when retrying the same booking (Section 7.1).
  String? _idempotencyKey;

  @override
  void onInit() {
    super.onInit();
    args = Get.arguments as CheckoutArgs;
    fetchQuote();
  }

  Future<void> fetchQuote() async {
    loading.value = true;
    error.value = null;
    try {
      quote.value = await jobs.quote(args.request);
      _idempotencyKey = null; // new quote = new booking intent
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }

  bool get budgetTooHigh {
    final q = quote.value;
    final p = args.request.pabili;
    return q?.maxItemBudgetCentavos != null && p != null && p.estimatedItemTotalCentavos > q!.maxItemBudgetCentavos!;
  }

  Future<void> place() async {
    final q = quote.value;
    if (q == null || placing.value || budgetTooHigh) return;
    if (q.expiresAt.isBefore(DateTime.now())) {
      GoErrors.toast('error.quote_expired'.tr);
      await fetchQuote();
      return;
    }
    placing.value = true;
    _idempotencyKey ??= ApiClient.newIdempotencyKey();
    try {
      final job = await jobs.create(
        quoteId: q.id,
        method: method.value,
        notes: notes.value.trim().isEmpty ? null : notes.value.trim(),
        idempotencyKey: _idempotencyKey!,
      );
      args.onPlaced?.call();
      Get.find<ActiveJobsService>().upsert(job);
      if (job.payment.method.isOnline && job.payment.checkoutUrl != null) await openPayment(job.payment.checkoutUrl!);
      Get.until((r) => r.settings.name == Routes.home);
      Get.toNamed(Routes.tracking, arguments: job.id);
    } on ApiException catch (e) {
      if (e.code == ErrorCodes.quoteExpired) {
        GoErrors.toast('error.quote_expired'.tr);
        await fetchQuote();
      } else {
        GoErrors.show(e);
      }
    } catch (e) {
      GoErrors.show(e);
    } finally {
      placing.value = false;
    }
  }
}

/// Opens GCash/Maya checkout in an in-app browser tab. The tracking screen
/// polls `GET /jobs/{id}` until `payment.status` is paid or failed.
Future<void> openPayment(String url) async {
  if (AppConfig.current.useMockApi) {
    GoErrors.toast('checkout.mock_payment'.tr);
    return;
  }
  await openCheckoutPage(url);
}
