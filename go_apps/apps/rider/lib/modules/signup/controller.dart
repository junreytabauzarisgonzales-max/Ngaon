import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/rider_session_service.dart';

/// Personal info, motorcycle, and document uploads. Draft persisted.
class SignupController extends GetxController {
  final RiderRepository repo = Get.find();
  final AuthRepository authRepo = Get.find();
  final AuthService auth = Get.find();
  final StorageService storage = Get.find();
  final RiderSessionService session = Get.find();
  static const draftKey = 'rider_signup';

  final name = TextEditingController();
  final plate = TextEditingController();
  final makeModel = TextEditingController();
  final color = TextEditingController();
  final docs = <UploadPurpose, String>{}.obs;
  final submitting = false.obs;

  static const required = [UploadPurpose.riderLicense, UploadPurpose.riderOrcr, UploadPurpose.riderSelfie, UploadPurpose.riderClearance];

  @override
  void onInit() {
    super.onInit();
    name.text = auth.user.value?.name ?? '';
    final v = session.profile.value?.vehicle;
    final d = storage.readDraft(draftKey) ?? {};
    plate.text = d['plate'] as String? ?? v?.plate ?? '';
    makeModel.text = d['make_model'] as String? ?? v?.makeModel ?? '';
    color.text = d['color'] as String? ?? v?.color ?? '';
    for (final p in required) {
      final k = (d['docs'] as Map?)?[p.wire] as String?;
      if (k != null) docs[p] = k;
    }
    for (final c in [plate, makeModel, color]) {
      c.addListener(_save);
    }
  }

  void setDoc(UploadPurpose p, String? key) {
    key == null ? docs.remove(p) : docs[p] = key;
    _save();
  }

  void _save() => storage.writeDraft(draftKey, {
    'plate': plate.text,
    'make_model': makeModel.text,
    'color': color.text,
    'docs': {for (final e in docs.entries) e.key.wire: e.value},
  });

  bool get complete =>
      name.text.trim().length >= 2 &&
      plate.text.trim().isNotEmpty &&
      makeModel.text.trim().isNotEmpty &&
      color.text.trim().isNotEmpty &&
      required.every(docs.containsKey);

  Future<void> submit() async {
    if (!complete) {
      GoErrors.toast('rider.signup.incomplete'.tr);
      return;
    }
    submitting.value = true;
    try {
      if (name.text.trim() != auth.user.value?.name) auth.setUser(await authRepo.updateMe(name: name.text.trim()));
      session.profile.value = await repo.submit(
        RiderProfileInput(
          vehicle: Vehicle(plate: plate.text.trim().toUpperCase(), makeModel: makeModel.text.trim(), color: color.text.trim()),
          documents: RiderDocuments(
            licenseKey: docs[UploadPurpose.riderLicense]!,
            orcrKey: docs[UploadPurpose.riderOrcr]!,
            selfieKey: docs[UploadPurpose.riderSelfie]!,
            clearanceKey: docs[UploadPurpose.riderClearance]!,
          ),
        ),
      );
      await storage.clearDraft(draftKey);
      Get.offAllNamed(Routes.pending);
    } catch (e) {
      GoErrors.show(e);
    } finally {
      submitting.value = false;
    }
  }
}
