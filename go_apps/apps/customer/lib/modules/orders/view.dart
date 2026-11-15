import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import 'controller.dart';

class OrdersView extends GetView<OrdersController> {
  const OrdersView({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text('nav.activity'.tr),
        bottom: TabBar(
          tabs: [
            Tab(text: 'orders.active'.tr),
            Tab(text: 'orders.past'.tr),
          ],
        ),
      ),
      body: TabBarView(children: [_list(controller.active), _list(controller.past)]),
    ),
  );

  Widget _list(JobList l) => Obx(() {
    if (l.loading.value && l.items.isEmpty) return const LoadingState();
    if (l.error.value != null && l.items.isEmpty) return ErrorState(error: l.error.value!, onRetry: () => controller.load(l));
    if (l.items.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'orders.empty'.tr,
        action: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(200, 50)),
          onPressed: () => Get.toNamed(Routes.ride),
          icon: const Icon(Icons.two_wheeler),
          label: Text('orders.empty_cta'.tr),
        ),
      );
    }
    return PagedListView<Job>(
      items: l.items.toList(),
      hasMore: l.hasMore,
      onRefresh: () => controller.load(l),
      onLoadMore: () => controller.load(l, more: true),
      itemBuilder: (_, j) => JobListTile(job: j, onTap: () => controller.open(j)),
    );
  });
}

class JobListTile extends StatelessWidget {
  const JobListTile({super.key, required this.job, required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: serviceColor(job.service.name).withValues(alpha: 0.12),
        child: Icon(serviceIcon(job.service.name), color: serviceColor(job.service.name)),
      ),
      title: Text('${'service.${job.service.name}'.tr} · ${job.code}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(job.dropoff.address, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              StatusChip('status.${job.status.wire}'.tr, color: jobStatusColor(job.status)),
              const Spacer(),
              Text(formatManilaDateTime(job.createdAt), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
      trailing: MoneyText(job.fare.totalCentavos, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
}
