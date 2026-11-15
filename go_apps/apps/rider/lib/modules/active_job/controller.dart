import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';

class ActiveJobController extends GetxController {
  final RiderSessionService session = Get.find();
  final RiderRepository repo = Get.find();
  final JobsRepository jobs = Get.find();
  final LocationService location = Get.find();
  final busy = false.obs;
  final completed = Rxn<Job>();

  Job? get job => session.activeJob.value;

  /// Pickup until picked up, then drop-off.
  Stop get target {
    final j = job!;
    return const {JobStatus.riderAssigned, JobStatus.arrivedPickup, JobStatus.itemsPurchased}.contains(j.status) ? j.pickup : j.dropoff;
  }

  void navigate() => openNavigation(target.location);

  void chat() => Get.toNamed(
    CoreRoutes.chat,
    arguments: ChatArgs(jobId: job!.id, title: 'rider.customer'.tr),
  );

  Future<void> call() async {
    final n = await GoErrors.guard(() => jobs.call(job!.id));
    if (n != null) await dialNumber(n);
  }

  Future<void> advance(RiderStep step) async {
    String? proofKey, receiptKey;
    int? itemTotal;
    if (step.needsReceipt) {
      final r = await showGoSheet<(String, int)>(title: 'rider.receipt.title'.tr, child: const ReceiptSheet());
      if (r == null) return;
      (receiptKey, itemTotal) = r;
    }
    if (step.needsProofPhoto) {
      proofKey = await showGoSheet<String>(title: 'rider.proof.title'.tr, child: const ProofSheet());
      if (proofKey == null) return;
    }
    busy.value = true;
    try {
      final here = await location.current();
      final updated = await repo.updateJobStatus(
        job!.id,
        status: step.target,
        location: here,
        proofKey: proofKey,
        receiptKey: receiptKey,
        itemTotalCentavos: itemTotal,
      );
      if (updated.status == JobStatus.completed) {
        completed.value = updated;
        session.activeJob.value = null;
      } else {
        session.activeJob.value = updated;
      }
    } catch (e) {
      GoErrors.show(e);
    } finally {
      busy.value = false;
    }
  }
}

/// Pabili: photo of the receipt + item total.
class ReceiptSheet extends StatefulWidget {
  const ReceiptSheet({super.key});
  @override
  State<ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends State<ReceiptSheet> {
  String? _key;
  final _total = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhotoUploadTile(
          purpose: UploadPurpose.receipt,
          label: 'rider.receipt.photo'.tr,
          allowGallery: false,
          onUploaded: (k) => setState(() => _key = k),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('receipt.total'),
          controller: _total,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'rider.receipt.total'.tr, prefixText: '₱ ', errorText: _error),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('receipt.submit'),
          onPressed: _key == null
              ? null
              : () {
                  final c = parsePesosToCentavos(_total.text);
                  if (c == null || c <= 0) return setState(() => _error = 'pabili.budget_invalid'.tr);
                  Get.back(result: (_key!, c));
                },
          child: Text('common.continue'.tr),
        ),
      ],
    ),
  );
}

/// Proof-of-delivery photo (Food, Padala, Pabili).
class ProofSheet extends StatefulWidget {
  const ProofSheet({super.key});
  @override
  State<ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<ProofSheet> {
  String? _key;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('rider.proof.body'.tr, style: TextStyle(color: GoColors.muted)),
        const SizedBox(height: 12),
        PhotoUploadTile(
          purpose: UploadPurpose.proofOfDelivery,
          label: 'photo.take'.tr,
          allowGallery: false,
          height: 180,
          onUploaded: (k) => setState(() => _key = k),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('proof.submit'),
          onPressed: _key == null ? null : () => Get.back(result: _key),
          child: Text('rider.step.completed'.tr),
        ),
      ],
    ),
  );
}
