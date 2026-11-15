import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class MessagesView extends GetView<MessagesController> {
  const MessagesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('nav.messages'.tr)),
      body: Obx(() {
        // Touch reactive sources so the list rebuilds on job updates.
        c.activeJobs.revision.value;
        final live = c.live;
        final past = c.past.toList();
        if (c.loading.value && live.isEmpty && past.isEmpty) return const LoadingState();
        if (live.isEmpty && past.isEmpty) {
          return EmptyState(icon: Icons.chat_bubble_outline, message: 'messages.empty'.tr);
        }
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, goNavBarClearance),
            children: [
              if (live.isNotEmpty) SectionTitle('messages.live'.tr),
              for (final j in live) _Conversation(job: j, live: true, onTap: () => c.open(j)),
              if (past.isNotEmpty) SectionTitle('messages.earlier'.tr),
              for (final j in past) _Conversation(job: j, live: false, onTap: () => c.open(j)),
            ],
          ),
        );
      }),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.job, required this.live, required this.onTap});
  final Job job;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          GoImage(job.rider?.photoUrl, width: 48, height: 48, radius: 24, icon: Icons.person),
          if (live)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: GoColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: GoColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(job.rider?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${'service.${job.service.name}'.tr} · ${job.code} · ${'status.${job.status.wire}'.tr}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: live
          ? Icon(Icons.chevron_right, color: GoColors.muted)
          : Text(formatManilaDate(job.updatedAt), style: TextStyle(fontSize: 12, color: GoColors.muted)),
    ),
  );
}
