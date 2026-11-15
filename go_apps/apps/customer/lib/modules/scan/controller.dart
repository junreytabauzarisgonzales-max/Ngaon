import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/routes/app_routes.dart';
import '../shell/controller.dart';

/// What a scanned QR means for Go.
sealed class ScanTarget {
  const ScanTarget();

  /// `go://merchant/<id>` or `https://<host>/m/<id>` -> merchant menu.
  static ScanTarget parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri != null) {
      if (uri.scheme == 'go' && uri.host == 'merchant' && uri.pathSegments.isNotEmpty) return MerchantTarget(uri.pathSegments.first);
      final seg = uri.pathSegments;
      if ((uri.scheme == 'https' || uri.scheme == 'http') && seg.length >= 2 && seg[seg.length - 2] == 'm') return MerchantTarget(seg.last);
    }
    return TextTarget(raw);
  }
}

class MerchantTarget extends ScanTarget {
  const MerchantTarget(this.merchantId);
  final String merchantId;
}

class TextTarget extends ScanTarget {
  const TextTarget(this.text);
  final String text;
}

/// Camera runs only while the Scan tab is visible.
class ScanController extends GetxController {
  MobileScannerController? camera;
  final active = false.obs;
  final torchOn = false.obs;
  bool _handling = false;

  bool get enabled => AppConfig.current.enablePlatformPlugins;

  @override
  void onInit() {
    super.onInit();
    if (enabled) {
      camera = MobileScannerController(
        autoStart: false,
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
    final shell = Get.find<ShellController>();
    ever<int>(shell.index, (i) => i == ShellController.scanTab ? start() : stop());
  }

  Future<void> start() async {
    active.value = true;
    try {
      await camera?.start();
    } catch (_) {}
  }

  Future<void> stop() async {
    active.value = false;
    torchOn.value = false;
    try {
      await camera?.stop();
    } catch (_) {}
  }

  Future<void> toggleTorch() async {
    await camera?.toggleTorch();
    torchOn.toggle();
  }

  void onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw != null) handle(raw);
  }

  Future<void> fromGallery() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    final r = await camera?.analyzeImage(f.path);
    final raw = r?.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    raw == null ? GoErrors.toast('scan.no_code_in_image'.tr) : await handle(raw);
  }

  Future<void> handle(String raw) async {
    if (_handling) return;
    _handling = true;
    HapticFeedback.mediumImpact();
    await stop();
    switch (ScanTarget.parse(raw)) {
      case MerchantTarget(:final merchantId):
        await Get.toNamed<dynamic>(Routes.merchant, arguments: merchantId);
      case TextTarget(:final text):
        await showGoSheet<void>(
          title: 'scan.result_title'.tr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('scan.not_go'.tr, style: TextStyle(color: GoColors.muted)),
              const SizedBox(height: 12),
              SelectableText(text, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Get.back();
                  GoErrors.toast('scan.copied'.tr);
                },
                icon: const Icon(Icons.copy),
                label: Text('scan.copy'.tr),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: Get.back, child: Text('scan.again'.tr)),
            ],
          ),
        );
    }
    _handling = false;
    if (Get.find<ShellController>().index.value == ShellController.scanTab) await start();
  }

  @override
  void onClose() {
    camera?.dispose();
    super.onClose();
  }
}
