import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';
import 'controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.session;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: c.refreshAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, goNavBarClearance),
            children: [
              Obx(() {
                final online = s.online;
                return Material(
                  color: online ? GoColors.primary : GoColors.night,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    key: const Key('rider.toggle'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: s.toggling.value ? null : () => c.toggle(!online),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                      child: Column(
                        children: [
                          Icon(online ? Icons.power_settings_new : Icons.power_off, color: Colors.white, size: 56),
                          const SizedBox(height: 12),
                          Text(
                            online ? 'rider.online'.tr : 'rider.offline'.tr,
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            online ? 'rider.online_hint'.tr : 'rider.offline_hint'.tr,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (s.toggling.value)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator(color: GoColors.accent),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Obx(
                () => Column(
                  children: [for (final b in c.blockers) _BlockerCard(blocker: b, controller: c)],
                ),
              ),
              Obx(() {
                final j = s.activeJob.value;
                if (j == null || j.status.isFinal) return const SizedBox.shrink();
                return Card(
                  margin: const EdgeInsets.only(top: 12),
                  color: GoColors.accent,
                  child: ListTile(
                    key: const Key('rider.active_job'),
                    leading: Icon(serviceIcon(j.service.name)),
                    title: Text('rider.active_job'.tr, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${j.code} · ${'status.${j.status.wire}'.tr}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: c.openJob,
                  ),
                );
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Obx(
                      () => _Stat(
                        label: 'rider.today'.tr,
                        value: formatCentavos(c.today.value?.totalCentavos ?? 0),
                        sub: 'rider.jobs_count'.trParams({'n': '${c.today.value?.jobsCount ?? 0}'}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Obx(() {
                      final p = s.profile.value;
                      return _Stat(
                        label: 'rider.wallet'.tr,
                        value: formatCentavos(p?.balanceCentavos ?? 0),
                        sub: 'rider.min_balance'.trParams({'min': formatCentavos(p?.minBalanceCentavos ?? 0)}),
                        warn: p != null && !p.hasEnoughBalance,
                      );
                    }),
                  ),
                ],
              ),
              Obx(
                () => s.online && s.lastPingAt.value != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'rider.location_sent'.trParams({'t': formatManilaTime(s.lastPingAt.value!)}),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: GoColors.muted, fontSize: 12),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockerCard extends StatelessWidget {
  const _BlockerCard({required this.blocker, required this.controller});
  final OnlineBlocker blocker;
  final HomeController controller;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(top: 12),
    color: GoColors.warning.withValues(alpha: 0.12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('rider.blocker.${blocker.name}'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('rider.blocker_body.${blocker.name}'.tr),
          if (blocker == OnlineBlocker.lowBalance)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(onPressed: controller.topUp, child: Text('rider.topup'.tr)),
            ),
          if (blocker == OnlineBlocker.noLocation)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(onPressed: controller.openSettings, child: Text('rider.open_settings'.tr)),
            ),
        ],
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub, this.warn = false});
  final String label;
  final String value;
  final String sub;
  final bool warn;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: GoColors.muted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: warn ? GoColors.danger : GoColors.ink),
          ),
          Text(sub, style: TextStyle(fontSize: 12, color: GoColors.muted)),
        ],
      ),
    ),
  );
}
