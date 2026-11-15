import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';

/// Full-screen job offer with a 15 s countdown from `expires_at`.
class OfferView extends StatelessWidget {
  const OfferView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Get.find<RiderSessionService>();
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: GoColors.night,
        body: SafeArea(
          child: Obx(() {
            final o = s.offer.value;
            if (o == null) return const Center(child: CircularProgressIndicator());
            final j = o.job;
            final total = o.expiresAt.difference(o.job.createdAt).inSeconds.clamp(1, 60);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: serviceColor(j.service.name), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            Icon(serviceIcon(j.service.name), color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'service.${j.service.name}'.tr,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      CountdownText(
                        key: ValueKey(o.id),
                        deadline: o.expiresAt,
                        onExpired: () => s.decline(reason: 'timeout'),
                        builder: (_, left) => SizedBox(
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: (left.inMilliseconds / 1000 / (total > 15 ? 15 : total)).clamp(0, 1),
                                strokeWidth: 6,
                                color: GoColors.accent,
                                backgroundColor: Colors.white12,
                              ),
                              Text(
                                '${left.inSeconds}',
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('rider.offer.earn'.tr, style: const TextStyle(color: Colors.white70)),
                  Text(
                    formatCentavos(o.earningsCentavos),
                    key: const Key('offer.earnings'),
                    style: const TextStyle(color: GoColors.accent, fontSize: 48, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'rider.offer.away'.trParams({'d': formatDistance(o.pickupDistanceM)}),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  Theme(
                    data: ThemeData.light(),
                    child: StopsCard(pickup: j.pickup, dropoff: j.dropoff),
                  ),
                  if (j.payment.method == PaymentMethod.cash) ...[
                    const SizedBox(height: 12),
                    Text(
                      'rider.offer.cash'.trParams({'amount': formatCentavos(j.fare.totalCentavos)}),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    height: 72,
                    child: FilledButton(
                      key: const Key('offer.accept'),
                      style: FilledButton.styleFrom(backgroundColor: GoColors.accent, foregroundColor: GoColors.night),
                      onPressed: s.accept,
                      child: Text('rider.offer.accept'.tr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('offer.decline'),
                    onPressed: () => s.decline(),
                    child: Text('rider.offer.decline'.tr, style: const TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
