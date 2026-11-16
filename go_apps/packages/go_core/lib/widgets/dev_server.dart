import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../bootstrap.dart';
import '../config/app_config.dart';
import '../theme/go_theme.dart';
import '../utils/error_handler.dart';
import 'go_sheet.dart';

/// Dev builds only (`DEV_TOOLS=true`): shows the current backend address on the
/// login screen and lets testers change it when the laptop's Wi-Fi IP changes.
class ServerAddressButton extends StatelessWidget {
  const ServerAddressButton({super.key});

  static bool get visible => AppConfig.current.devTools && !AppConfig.current.useMockApi;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final host = Uri.tryParse(AppConfig.current.apiBaseUrl)?.authority ?? AppConfig.current.apiBaseUrl;
    return Center(
      child: TextButton.icon(
        key: const Key('dev.server'),
        onPressed: () => showGoSheet<void>(title: 'dev.server_title'.tr, child: const _ServerForm()),
        icon: Icon(Icons.dns_outlined, size: 18, color: GoColors.muted),
        label: Text('${'dev.server'.tr}: $host', style: TextStyle(color: GoColors.muted)),
      ),
    );
  }
}

class _ServerForm extends StatefulWidget {
  const _ServerForm();
  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  late final _ctrl = TextEditingController(text: AppConfig.current.apiBaseUrl);
  String? _status;
  bool? _ok;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// `192.168.1.5:8080` -> `http://192.168.1.5:8080`; null when invalid.
  String? _normalized() {
    var v = _ctrl.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (v.isEmpty) return null;
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'http://$v';
    final u = Uri.tryParse(v);
    return (u == null || u.host.isEmpty) ? null : v;
  }

  Future<bool> _test(String url) async {
    setState(() {
      _busy = true;
      _status = 'dev.testing'.tr;
      _ok = null;
    });
    var reachable = false;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4), receiveTimeout: const Duration(seconds: 4)));
      final res = await dio.get<String>('$url/healthz');
      reachable = res.statusCode == 200;
    } catch (_) {}
    if (mounted) {
      setState(() {
        _busy = false;
        _ok = reachable;
        _status = reachable ? 'dev.reachable'.tr : 'dev.unreachable'.tr;
      });
    }
    return reachable;
  }

  Future<void> _save() async {
    final url = _normalized();
    if (url == null) return setState(() => _status = 'dev.invalid_url'.tr);
    if (!await _test(url)) return;
    await setServerAddress(url);
    Get.back();
    GoErrors.toast('dev.saved'.tr);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('dev.server_help'.tr, style: TextStyle(color: GoColors.muted)),
      const SizedBox(height: 12),
      TextField(
        key: const Key('dev.server.url'),
        controller: _ctrl,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(hintText: 'dev.server_hint'.tr, prefixIcon: const Icon(Icons.link)),
      ),
      if (_status != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _status!,
            style: TextStyle(
              color: _ok == null ? GoColors.muted : (_ok! ? GoColors.success : GoColors.danger),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final url = _normalized();
                      url == null ? setState(() => _status = 'dev.invalid_url'.tr) : _test(url);
                    },
              child: Text('dev.test'.tr),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(key: const Key('dev.server.save'), onPressed: _busy ? null : _save, child: Text('common.save'.tr)),
          ),
        ],
      ),
    ],
  );
}
