import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/enums.dart';
import '../services/upload_service.dart';
import '../theme/go_theme.dart';
import '../utils/error_handler.dart';
import 'go_sheet.dart';

/// Capture -> compress -> presigned upload, with progress and retry.
/// Calls [onUploaded] with the storage key.
class PhotoUploadTile extends StatefulWidget {
  const PhotoUploadTile({
    super.key,
    required this.purpose,
    required this.label,
    required this.onUploaded,
    this.initialKey,
    this.allowGallery = true,
    this.height = 140,
  });

  final UploadPurpose purpose;
  final String label;
  final ValueChanged<String?> onUploaded;
  final String? initialKey;
  final bool allowGallery;
  final double height;

  @override
  State<PhotoUploadTile> createState() => _PhotoUploadTileState();
}

class _PhotoUploadTileState extends State<PhotoUploadTile> {
  Uint8List? _bytes;
  double? _progress;
  bool _failed = false;
  String? _key;

  UploadService get _uploads => Get.find<UploadService>();

  @override
  void initState() {
    super.initState();
    _key = widget.initialKey;
  }

  Future<void> _pick() async {
    var camera = true;
    if (widget.allowGallery) {
      final choice = await showGoOptions<bool>(
        title: widget.label,
        options: [
          GoOption(value: true, label: 'photo.take'.tr, icon: Icons.photo_camera_outlined),
          GoOption(value: false, label: 'photo.gallery'.tr, icon: Icons.photo_library_outlined),
        ],
      );
      if (choice == null) return;
      camera = choice;
    }
    try {
      final file = await _uploads.pick(camera: camera);
      if (file == null) return;
      final bytes = await _uploads.compress(file);
      setState(() => _bytes = bytes);
      await _upload();
    } catch (e) {
      GoErrors.show(e);
    }
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() {
      _failed = false;
      _progress = 0;
    });
    try {
      final key = await _uploads.upload(
        bytes,
        widget.purpose,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _key = key;
        _progress = null;
      });
      widget.onUploaded(key);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _progress = null;
      });
      widget.onUploaded(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _key != null && _progress == null && !_failed;
    return InkWell(
      onTap: _progress != null ? null : (_failed ? _upload : _pick),
      borderRadius: BorderRadius.circular(GoSpacing.radius),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: GoColors.surface,
          borderRadius: BorderRadius.circular(GoSpacing.radius),
          border: Border.all(color: _failed ? GoColors.danger : (done ? GoColors.success : GoColors.line), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_bytes != null) Opacity(opacity: 0.35, child: Image.memory(_bytes!, fit: BoxFit.cover, cacheWidth: 400)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _failed ? Icons.refresh : (done ? Icons.check_circle : Icons.add_a_photo),
                    color: _failed ? GoColors.danger : (done ? GoColors.success : GoColors.primary),
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (_progress != null) ...[
                    Text('photo.uploading'.trParams({'p': '${(_progress! * 100).round()}'})),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: _progress),
                  ] else if (_failed)
                    Text('photo.retry'.tr, style: const TextStyle(color: GoColors.danger))
                  else if (done)
                    Text('photo.done'.tr, style: const TextStyle(color: GoColors.success)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
