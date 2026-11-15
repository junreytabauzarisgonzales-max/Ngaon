import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'controller.dart';

class ScanView extends GetView<ScanController> {
  const ScanView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c.enabled && c.camera != null)
            MobileScanner(
              controller: c.camera,
              onDetect: c.onDetect,
              errorBuilder: (context, error) => _CameraError(error: error),
            )
          else
            const ColoredBox(color: GoColors.night),
          // Dim everything except the scan window.
          const IgnorePointer(child: CustomPaint(painter: _ScanWindowPainter())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'scan.title'.tr,
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Obx(
                        () => _RoundIcon(
                          icon: c.torchOn.value ? Icons.flash_on : Icons.flash_off,
                          onTap: c.toggleTorch,
                          tooltip: 'scan.torch'.tr,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _RoundIcon(icon: Icons.photo_library_outlined, onTap: c.fromGallery, tooltip: 'scan.gallery'.tr),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    'scan.hint'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: goNavBarClearance),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.18),
    shape: const CircleBorder(),
    child: IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, color: Colors.white),
    ),
  );
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});
  final MobileScannerException error;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GoColors.night,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 12),
            Text(
              'scan.no_camera'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Get.find<LocationService>().openSettings(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(160, 44)),
              child: Text('scan.open_settings'.tr),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Dark overlay with a rounded clear square and green corner brackets.
class _ScanWindowPainter extends CustomPainter {
  const _ScanWindowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.68;
    final rect = Rect.fromCenter(center: size.center(Offset(0, -size.height * 0.04)), width: side, height: side);
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(window)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    final p = Paint()
      ..color = GoColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    for (final (corner, dx, dy) in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner + Offset(0, dy * 14), corner + Offset(0, dy * l), p);
      canvas.drawLine(corner + Offset(dx * 14, 0), corner + Offset(dx * l, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
