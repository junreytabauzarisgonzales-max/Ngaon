import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/geo.dart';
import '../repositories/repositories.dart';
import '../services/location_service.dart';
import '../theme/go_theme.dart';
import '../utils/error_handler.dart';
import 'go_map.dart';

class PickerArgs {
  const PickerArgs({this.title, this.initial, this.allowSave = true});
  final String? title;
  final LatLng? initial;
  final bool allowSave;
}

/// Center-pin location picker. `Get.toNamed('/location-picker')` returns a
/// [Stop] (address + location) or null.
class LocationPickerController extends GetxController {
  final GeoRepository geo = Get.find();
  final LocationService locationService = Get.find();

  late final PickerArgs args;
  final center = LatLng.bongao.obs;
  final address = ''.obs;
  final resolving = false.obs;
  final inArea = true.obs;
  final saved = <SavedPlace>[].obs;
  final results = <GeoSearchResult>[].obs;
  final searching = false.obs;
  final query = ''.obs;
  ServiceArea? _area;
  Timer? _debounce;
  int _reverseSeq = 0;
  final mapKey = GlobalKey<GoMapState>();

  @override
  void onInit() {
    super.onInit();
    args = Get.arguments is PickerArgs ? Get.arguments as PickerArgs : const PickerArgs();
    _start();
  }

  Future<void> _start() async {
    final start = args.initial ?? await locationService.current();
    center.value = start;
    unawaited(_loadArea());
    unawaited(_loadSaved());
    await onCameraIdle(start);
  }

  Future<void> _loadArea() async {
    try {
      _area = await geo.serviceArea();
      inArea.value = _area!.contains(center.value);
    } catch (_) {}
  }

  Future<void> _loadSaved() async {
    try {
      saved.assignAll(await geo.savedPlaces());
    } catch (_) {}
  }

  Future<void> onCameraIdle(LatLng p) async {
    center.value = p;
    inArea.value = _area?.contains(p) ?? true;
    final seq = ++_reverseSeq;
    resolving.value = true;
    try {
      final a = await geo.reverse(p);
      if (seq == _reverseSeq) address.value = a;
    } catch (_) {
      if (seq == _reverseSeq) address.value = '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}';
    } finally {
      if (seq == _reverseSeq) resolving.value = false;
    }
  }

  void onQuery(String q) {
    query.value = q;
    _debounce?.cancel();
    if (q.trim().length < 2) {
      results.clear();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      searching.value = true;
      try {
        results.assignAll(await geo.search(q.trim(), center.value));
      } catch (e) {
        GoErrors.show(e);
      } finally {
        searching.value = false;
      }
    });
  }

  Future<void> jumpTo(LatLng p, {String? label}) async {
    results.clear();
    query.value = '';
    center.value = p;
    await mapKey.currentState?.moveTo(p);
    await onCameraIdle(p);
    if (label != null) address.value = label;
  }

  Future<void> useMyLocation() async => jumpTo(await locationService.current());

  void confirm() {
    if (!inArea.value) {
      GoErrors.toast('error.out_of_service_area'.tr);
      return;
    }
    Get.back(
      result: Stop(address: address.value, location: center.value),
    );
  }

  Future<void> savePlace() async {
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
          TextButton(onPressed: Get.back, child: Text('common.cancel'.tr)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Get.back(result: ctrl.text.trim()),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    final p = await GoErrors.guard(() => geo.addPlace(label, address.value, center.value));
    if (p != null) {
      saved.add(p);
      GoErrors.toast('common.saved'.tr);
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }
}

class LocationPickerBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(LocationPickerController.new);
}

class LocationPickerView extends GetView<LocationPickerController> {
  const LocationPickerView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text(c.args.title ?? 'picker.title'.tr)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(hintText: 'picker.search_hint'.tr, prefixIcon: const Icon(Icons.search)),
              onChanged: c.onQuery,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Obx(() => GoMap(key: c.mapKey, center: c.center.value, onCameraIdle: c.onCameraIdle, myLocation: true)),
                ),
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 36),
                      child: Icon(Icons.location_on, size: 44, color: GoColors.danger),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'myloc',
                    onPressed: c.useMyLocation,
                    tooltip: 'picker.my_location'.tr,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                Obx(() {
                  final showList = c.results.isNotEmpty || (c.query.value.isEmpty && c.saved.isNotEmpty);
                  if (!showList) return const SizedBox.shrink();
                  final searching = c.results.isNotEmpty;
                  return Positioned(
                    left: 12,
                    right: 12,
                    top: 8,
                    child: Card(
                      elevation: 3,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            if (!searching)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text('picker.saved'.tr, style: TextStyle(color: GoColors.muted)),
                              ),
                            if (searching)
                              for (final r in c.results)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(r.name),
                                  subtitle: Text(r.address),
                                  onTap: () => c.jumpTo(r.location, label: '${r.name}, ${r.address}'),
                                )
                            else
                              for (final p in c.saved)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.bookmark_outline),
                                  title: Text(p.label),
                                  subtitle: Text(p.address),
                                  onTap: () => c.jumpTo(p.location, label: p.address),
                                ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Obx(
                () => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.place, color: GoColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.resolving.value ? 'picker.locating'.tr : c.address.value,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        if (c.args.allowSave && !c.resolving.value)
                          IconButton(
                            onPressed: c.savePlace,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            tooltip: 'picker.save_place'.tr,
                          ),
                      ],
                    ),
                    if (!c.inArea.value)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('error.out_of_service_area'.tr, style: const TextStyle(color: GoColors.danger)),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: c.resolving.value || !c.inArea.value || c.address.value.trim().isEmpty ? null : c.confirm,
                      child: Text(c.inArea.value ? 'picker.confirm'.tr : 'picker.out_of_area'.tr),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
