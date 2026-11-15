import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../repositories/repositories.dart';

/// Presigned upload flow (Section 7.3): compress -> POST /uploads -> PUT -> key.
class UploadService extends GetxService {
  UploadsRepository get _repo => Get.find<UploadsRepository>();
  final _picker = ImagePicker();

  Future<XFile?> pick({bool camera = true}) =>
      _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);

  /// Max 1280 px, ~70 % JPEG.
  Future<Uint8List> compress(XFile file) async {
    final raw = await file.readAsBytes();
    if (!AppConfig.current.enablePlatformPlugins) return raw;
    try {
      return await FlutterImageCompress.compressWithList(raw, minWidth: 1280, minHeight: 1280, quality: 70, format: CompressFormat.jpeg);
    } catch (_) {
      return raw;
    }
  }

  /// Uploads [bytes] and returns the storage key.
  Future<String> upload(Uint8List bytes, UploadPurpose purpose, {void Function(double)? onProgress}) async {
    final ticket = await _repo.create(purpose);
    await _repo.put(ticket.uploadUrl, bytes, onProgress: onProgress);
    return ticket.key;
  }
}
