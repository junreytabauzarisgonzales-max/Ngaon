import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class RatingView extends GetView<RatingController> {
  const RatingView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('tracking.rate'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'rating.rider'.trParams({'name': c.job.rider?.name ?? ''}),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Obx(() => _Stars(value: c.riderStars.value, onChanged: (v) => c.riderStars.value = v)),
          Obx(
            () => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in RatingController.tagKeys)
                  FilterChip(label: Text('rating.tag.$t'.tr), selected: c.tags.contains(t), onSelected: (_) => c.toggle(t)),
              ],
            ),
          ),
          if (c.job.service == ServiceType.food) ...[
            const SizedBox(height: 24),
            Text(
              'rating.merchant'.trParams({'name': c.job.merchant?.name ?? ''}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Obx(() => _Stars(value: c.merchantStars.value, onChanged: (v) => c.merchantStars.value = v)),
          ],
          const SizedBox(height: 24),
          TextField(
            maxLines: 3,
            decoration: InputDecoration(labelText: 'rating.comment'.tr),
            onChanged: (v) => c.comment.value = v,
          ),
          const SizedBox(height: 24),
          Obx(() => FilledButton(onPressed: c.sending.value ? null : c.submit, child: Text('rating.submit'.tr))),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 1; i <= 5; i++)
        IconButton(
          iconSize: 40,
          onPressed: () => onChanged(i),
          icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: GoColors.accent),
        ),
    ],
  );
}
