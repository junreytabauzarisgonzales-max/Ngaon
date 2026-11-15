import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

class ProfileController extends GetxController {
  final AuthService auth = Get.find();
  final AuthRepository authRepo = Get.find();
  final GeoRepository geo = Get.find();
  final StorageService storage = Get.find();
  final places = <SavedPlace>[].obs;
  final language = 'en'.obs;

  @override
  void onInit() {
    super.onInit();
    language.value = storage.languageCode;
    loadPlaces();
  }

  Future<void> loadPlaces() async {
    try {
      places.assignAll(await geo.savedPlaces());
    } catch (_) {}
  }

  Future<void> editName() async {
    final ctrl = TextEditingController(text: auth.user.value?.name);
    final name = await Get.dialog<String>(
      AlertDialog(
        title: Text('login.name_label'.tr),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: Get.back, child: Text('common.cancel'.tr)),
          TextButton(
            onPressed: () => Get.back(result: ctrl.text.trim()),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
    if (name == null || name.length < 2) return;
    final u = await GoErrors.guard(() => authRepo.updateMe(name: name));
    if (u != null) auth.setUser(u);
  }

  Future<void> setLanguage(String code) async {
    language.value = code;
    await setGoLanguage(code);
    await GoErrors.guard(() => authRepo.updateMe(language: code == 'fil' ? AppLanguage.fil : AppLanguage.en));
  }

  Future<void> addPlace() async {
    final r = await Get.toNamed<dynamic>(CoreRoutes.locationPicker, arguments: const PickerArgs(allowSave: true));
    if (r is Stop) {
      final ctrl = TextEditingController();
      final label = await Get.dialog<String>(
        AlertDialog(
          title: Text('picker.save_place'.tr),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: 'picker.label_hint'.tr),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: ctrl.text.trim()),
              child: Text('common.save'.tr),
            ),
          ],
        ),
      );
      if (label == null || label.isEmpty) return;
      final p = await GoErrors.guard(() => geo.addPlace(label, r.address, r.location));
      if (p != null) places.add(p);
    } else {
      await loadPlaces();
    }
  }

  Future<void> deletePlace(SavedPlace p) async {
    if (!await confirmDialog(title: 'dialog.are_you_sure'.tr, danger: true, confirmText: 'common.delete'.tr)) return;
    await GoErrors.guard(() => geo.deletePlace(p.id));
    places.remove(p);
  }

  Future<void> logout() async {
    if (await confirmDialog(title: 'common.logout_confirm'.tr)) await auth.logout();
  }

  Future<void> deleteAccount() async {
    final ok = await confirmDialog(
      title: 'profile.delete_title'.tr,
      message: 'profile.delete_body'.tr,
      danger: true,
      confirmText: 'common.delete'.tr,
    );
    if (!ok) return;
    final done = await GoErrors.guard(() async {
      await authRepo.deleteMe();
      return true;
    });
    if (done == true) await auth.logout(remote: false);
  }
}
