import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../models/user.dart';
import '../network/api_exception.dart';
import '../repositories/repositories.dart';
import '../services/auth_service.dart';
import '../theme/go_theme.dart';
import '../utils/error_handler.dart';
import '../utils/validators.dart';

/// Shared phone -> OTP -> (name) flow for all three apps.
/// Each app supplies [onLoggedIn] to route after login.
class LoginController extends GetxController {
  LoginController({required this.onLoggedIn});

  /// Called after the session is saved (and name set for new users).
  final Future<void> Function(AuthResult result) onLoggedIn;

  final AuthRepository repo = Get.find();
  final AuthService auth = Get.find();

  final phone = TextEditingController();
  final otp = TextEditingController();
  final name = TextEditingController();
  final busy = false.obs;
  final phoneError = RxnString();
  final otpError = RxnString();
  final resendIn = 0.obs;
  String _e164 = '';
  AuthResult? _result;
  Timer? _timer;

  String get maskedPhone => PhPhone.mask(_e164);

  Future<void> submitPhone() async {
    final e164 = PhPhone.toE164(phone.text);
    if (e164 == null || !PhPhone.isValidLocal(phone.text.replaceFirst(RegExp(r'^0'), ''))) {
      phoneError.value = 'login.invalid_phone'.tr;
      return;
    }
    phoneError.value = null;
    busy.value = true;
    try {
      final r = await repo.requestOtp(e164);
      _e164 = e164;
      _startTimer(r.resendAfterSeconds);
      otp.clear();
      otpError.value = null;
      if (Get.currentRoute != LoginRoutes.otp) unawaited(Get.toNamed(LoginRoutes.otp));
    } catch (e) {
      if (e is ApiException && e.fields.containsKey('phone')) {
        phoneError.value = 'login.invalid_phone'.tr;
      } else {
        GoErrors.show(e);
      }
    } finally {
      busy.value = false;
    }
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    resendIn.value = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (resendIn.value <= 0) {
        t.cancel();
      } else {
        resendIn.value--;
      }
    });
  }

  Future<void> resend() async {
    if (resendIn.value > 0) return;
    await submitPhone();
  }

  Future<void> submitOtp() async {
    final code = otp.text.trim();
    if (!isValidOtp(code)) {
      otpError.value = 'login.invalid_otp'.tr;
      return;
    }
    otpError.value = null;
    busy.value = true;
    try {
      final r = await repo.verifyOtp(_e164, code, AppConfig.current.app);
      await auth.completeLogin(r);
      _result = r;
      if (r.isNewUser || r.user.name.trim().isEmpty) {
        unawaited(Get.toNamed(LoginRoutes.name));
      } else {
        await onLoggedIn(r);
      }
    } catch (e) {
      if (e is ApiException && (e.code == ErrorCodes.otpInvalid || e.code == ErrorCodes.otpExpired)) {
        otpError.value = GoErrors.message(e);
      } else {
        GoErrors.show(e);
      }
    } finally {
      busy.value = false;
    }
  }

  Future<void> submitName() async {
    final n = name.text.trim();
    if (n.length < 2) return;
    busy.value = true;
    try {
      final u = await repo.updateMe(name: n, language: auth.language);
      auth.setUser(u);
      await onLoggedIn(_result!);
    } catch (e) {
      GoErrors.show(e);
    } finally {
      busy.value = false;
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    phone.dispose();
    otp.dispose();
    name.dispose();
    super.onClose();
  }
}

class LoginRoutes {
  LoginRoutes._();
  static const phone = '/login';
  static const otp = '/login/otp';
  static const name = '/login/name';

  /// Pages for the shared flow; [binding] must put a [LoginController].
  static List<GetPage<dynamic>> pages(Bindings binding) => [
    GetPage(name: phone, page: () => const LoginPhoneView(), binding: binding),
    GetPage(name: otp, page: () => const LoginOtpView()),
    GetPage(name: name, page: () => const LoginNameView()),
  ];
}

class _LoginScaffold extends StatelessWidget {
  const _LoginScaffold({required this.title, this.subtitle, required this.children, this.showBack = false});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showBack ? AppBar() : null,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!showBack) ...[
            const SizedBox(height: 32),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: GoColors.primary, borderRadius: BorderRadius.circular(18)),
              alignment: Alignment.center,
              child: const Text(
                'Go',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: TextStyle(color: GoColors.muted, fontSize: 15))],
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    ),
  );
}

class LoginPhoneView extends GetView<LoginController> {
  const LoginPhoneView({super.key});

  @override
  Widget build(BuildContext context) => _LoginScaffold(
    title: 'login.welcome'.tr,
    subtitle: 'login.subtitle'.tr,
    children: [
      Obx(
        () => TextField(
          key: const Key('login.phone'),
          controller: controller.phone,
          keyboardType: TextInputType.phone,
          autofocus: true,
          maxLength: 11,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => controller.submitPhone(),
          style: const TextStyle(fontSize: 20, letterSpacing: 1),
          decoration: InputDecoration(
            labelText: 'login.phone_label'.tr,
            hintText: 'login.phone_hint'.tr,
            prefixText: '+63 ',
            errorText: controller.phoneError.value,
            counterText: '',
          ),
        ),
      ),
      const SizedBox(height: 16),
      Obx(
        () => FilledButton(
          key: const Key('login.phone.submit'),
          onPressed: controller.busy.value ? null : controller.submitPhone,
          child: controller.busy.value ? const _Spinner() : Text('common.continue'.tr),
        ),
      ),
      if (AppConfig.current.useMockApi)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            'login.mock_hint'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: GoColors.muted),
          ),
        ),
    ],
  );
}

class LoginOtpView extends GetView<LoginController> {
  const LoginOtpView({super.key});

  @override
  Widget build(BuildContext context) => _LoginScaffold(
    showBack: true,
    title: 'login.otp_title'.tr,
    subtitle: 'login.otp_sent'.trParams({'phone': controller.maskedPhone}),
    children: [
      Obx(
        () => TextField(
          key: const Key('login.otp'),
          controller: controller.otp,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.w700),
          onChanged: (v) {
            if (v.length == 6) controller.submitOtp();
          },
          decoration: InputDecoration(counterText: '', errorText: controller.otpError.value),
        ),
      ),
      const SizedBox(height: 16),
      Obx(
        () => FilledButton(
          key: const Key('login.otp.submit'),
          onPressed: controller.busy.value ? null : controller.submitOtp,
          child: controller.busy.value ? const _Spinner() : Text('login.verify'.tr),
        ),
      ),
      const SizedBox(height: 8),
      Obx(
        () => TextButton(
          onPressed: controller.resendIn.value > 0 || controller.busy.value ? null : controller.resend,
          child: Text(
            controller.resendIn.value > 0 ? 'login.resend_in'.trParams({'s': '${controller.resendIn.value}'}) : 'login.resend'.tr,
          ),
        ),
      ),
      TextButton(onPressed: Get.back, child: Text('login.change_number'.tr)),
    ],
  );
}

class LoginNameView extends GetView<LoginController> {
  const LoginNameView({super.key});

  @override
  Widget build(BuildContext context) => _LoginScaffold(
    showBack: false,
    title: 'login.name_title'.tr,
    children: [
      TextField(
        key: const Key('login.name'),
        controller: controller.name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: 'login.name_label'.tr),
        onSubmitted: (_) => controller.submitName(),
      ),
      const SizedBox(height: 16),
      Obx(
        () => FilledButton(
          key: const Key('login.name.submit'),
          onPressed: controller.busy.value ? null : controller.submitName,
          child: controller.busy.value ? const _Spinner() : Text('common.continue'.tr),
        ),
      ),
    ],
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white));
}
