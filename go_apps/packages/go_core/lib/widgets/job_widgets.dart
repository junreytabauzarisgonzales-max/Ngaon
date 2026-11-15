import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/enums.dart';
import '../models/geo.dart';
import '../models/job.dart';
import '../theme/go_theme.dart';
import '../utils/job_flow.dart';
import '../utils/time.dart';
import 'common.dart';
import 'go_sheet.dart';

/// Vertical status timeline used in tracking and order detail screens.
class JobTimeline extends StatelessWidget {
  const JobTimeline({super.key, required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final steps = buildTimeline(job);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineRow(step: steps[i], isLast: i == steps.length - 1, cancelled: steps[i].status == JobStatus.cancelled),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.isLast, required this.cancelled});
  final TimelineStep step;
  final bool isLast;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final color = cancelled
        ? GoColors.danger
        : switch (step.state) {
            TimelineStepState.done => GoColors.primary,
            TimelineStepState.current => GoColors.accent,
            TimelineStepState.upcoming => GoColors.line,
          };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: step.state == TimelineStepState.current ? 18 : 14,
                  height: step.state == TimelineStepState.current ? 18 : 14,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: step.state == TimelineStepState.done ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: step.state == TimelineStepState.done ? GoColors.primary : GoColors.line)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'status.${step.status.wire}'.tr,
                      style: TextStyle(
                        fontWeight: step.state == TimelineStepState.current ? FontWeight.w700 : FontWeight.w500,
                        color: step.state == TimelineStepState.upcoming ? GoColors.muted : GoColors.ink,
                      ),
                    ),
                  ),
                  if (step.at != null) Text(formatManilaTime(step.at!), style: TextStyle(color: GoColors.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rider info with call/chat buttons. Never shows the full phone number.
class RiderCard extends StatelessWidget {
  const RiderCard({super.key, required this.rider, this.onCall, this.onChat});
  final JobRider rider;
  final VoidCallback? onCall;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          GoImage(rider.photoUrl, width: 52, height: 52, radius: 26, icon: Icons.person),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(rider.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    if (rider.rating != null) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.star, size: 16, color: GoColors.accent),
                      Text(rider.rating!.toStringAsFixed(1)),
                    ],
                  ],
                ),
                Text('${rider.makeModel} · ${rider.color}', style: TextStyle(color: GoColors.muted)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: GoColors.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: GoColors.line),
                  ),
                  child: Text(rider.plate, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
              ],
            ),
          ),
          if (onChat != null)
            IconButton.filledTonal(onPressed: onChat, icon: const Icon(Icons.chat_bubble_outline), tooltip: 'common.chat'.tr),
          if (onCall != null) IconButton.filled(onPressed: onCall, icon: const Icon(Icons.call), tooltip: 'common.call'.tr),
        ],
      ),
    ),
  );
}

/// Pickup -> drop-off summary.
class StopsCard extends StatelessWidget {
  const StopsCard({super.key, required this.pickup, required this.dropoff, this.pickupLabel, this.dropoffLabel});
  final Stop pickup;
  final Stop dropoff;
  final String? pickupLabel;
  final String? dropoffLabel;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _row(Icons.trip_origin, GoColors.primary, pickupLabel ?? 'common.pickup'.tr, pickup),
          const Padding(
            padding: EdgeInsets.only(left: 11),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 10, child: VerticalDivider(width: 2, thickness: 2)),
            ),
          ),
          _row(Icons.location_on, GoColors.danger, dropoffLabel ?? 'common.dropoff'.tr, dropoff),
        ],
      ),
    ),
  );

  Widget _row(IconData icon, Color color, String label, Stop s) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: GoColors.muted, fontSize: 12)),
            Text(s.address, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (s.contactName != null) Text(s.contactName!, style: TextStyle(color: GoColors.muted)),
            if (s.notes != null) Text('“${s.notes}”', style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    ],
  );
}

/// Opens turn-by-turn navigation in Google Maps or Waze.
Future<void> openNavigation(LatLng to) async {
  final app = await showGoOptions<String>(
    title: 'common.navigate'.tr,
    options: [
      GoOption(value: 'gmaps', label: 'common.google_maps'.tr, icon: Icons.map_outlined),
      GoOption(value: 'waze', label: 'common.waze'.tr, icon: Icons.navigation_outlined),
    ],
  );
  if (app == null) return;
  final native = app == 'gmaps'
      ? Uri.parse('google.navigation:q=${to.lat},${to.lng}&mode=l')
      : Uri.parse('waze://?ll=${to.lat},${to.lng}&navigate=yes');
  final web = app == 'gmaps'
      ? Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${to.lat},${to.lng}&travelmode=two-wheeler')
      : Uri.parse('https://waze.com/ul?ll=${to.lat},${to.lng}&navigate=yes');
  if (!await launchUrl(native, mode: LaunchMode.externalApplication)) {
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

Future<void> dialNumber(String number) => launchUrl(Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^\d+]'), '')));

/// Opens a GCash/Maya checkout page in an in-app browser tab.
Future<void> openCheckoutPage(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
