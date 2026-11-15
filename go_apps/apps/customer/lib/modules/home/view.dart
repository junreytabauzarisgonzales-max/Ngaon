import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  static const _barHeight = 74.0;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: RefreshIndicator(
        edgeOffset: top + _barHeight,
        onRefresh: c.refreshAll,
        child: CustomScrollView(
          controller: c.scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Sticky search + profile header.
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(controller: c, topPadding: top, barHeight: _barHeight),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                child: Obx(
                  () => Text(
                    c.greetingKey.trParams({'name': c.auth.user.value?.firstName ?? ''}),
                    key: const Key('home.greeting'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('home.subtitle'.tr, style: TextStyle(color: GoColors.muted, fontSize: 15)),
              ),
            ),
            SliverToBoxAdapter(
              child: Obx(() {
                c.activeJobs.revision.value;
                return Column(
                  children: [for (final j in c.activeJobs.active) _ActiveBanner(job: j, onTap: () => c.track(j))],
                );
              }),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
                children: [for (final s in ServiceType.values) _ServiceTile(service: s, onTap: () => c.open(s))],
              ),
            ),
            SliverToBoxAdapter(
              child: Obx(() {
                if (c.loadingRecent.value) return const _RecentSkeleton();
                if (c.recent.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      'home.recent'.tr,
                      trailing: TextButton(onPressed: c.openActivity, child: Text('home.see_all'.tr)),
                    ),
                    SizedBox(
                      height: 136,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: c.recent.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _RecentCard(job: c.recent[i], onTap: () => c.track(c.recent[i])),
                      ),
                    ),
                  ],
                );
              }),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: goNavBarClearance)),
          ],
        ),
      ),
    );
  }
}

/// Pinned header: stays on top while scrolling and gains a hairline + soft
/// shadow once content slides underneath it.
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate({required this.controller, required this.topPadding, required this.barHeight});
  final HomeController controller;
  final double topPadding;
  final double barHeight;

  @override
  double get minExtent => topPadding + barHeight;
  @override
  double get maxExtent => topPadding + barHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final raised = overlapsContent || shrinkOffset > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: GoColors.background,
        border: Border(bottom: BorderSide(color: raised ? GoColors.line : Colors.transparent)),
        boxShadow: raised ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))] : const [],
      ),
      child: _TopBar(controller: controller),
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate old) => true;
}

/// Search pill with the profile avatar beside it.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});
  final HomeController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'home.search_hint'.tr,
            child: Material(
              color: GoColors.surface,
              shape: StadiumBorder(side: BorderSide(color: GoColors.line)),
              child: InkWell(
                key: const Key('home.search'),
                customBorder: const StadiumBorder(),
                onTap: controller.openSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: GoColors.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'home.search_hint'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: GoColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Obx(() {
          final name = controller.auth.user.value?.name.trim() ?? '';
          final initials = name.isEmpty ? '?' : name.split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
          return Semantics(
            button: true,
            label: 'common.profile'.tr,
            child: Material(
              color: Theme.of(context).colorScheme.primary,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                key: const Key('home.profile'),
                customBorder: const CircleBorder(),
                onTap: controller.openProfile,
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    ),
  );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});
  final ServiceType service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = serviceColor(service.name);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('home.tile.${service.name}'),
        onTap: onTap,
        child: Stack(
          children: [
            // Oversized faded icon for depth.
            Positioned(
              right: -18,
              bottom: -18,
              child: Icon(serviceIcon(service.name), size: 110, color: Colors.white.withValues(alpha: 0.12)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                    child: Icon(serviceIcon(service.name), color: Colors.white, size: 26),
                  ),
                  const Spacer(),
                  Text(
                    'service.${service.name}'.tr,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'home.tile.${service.name}'.tr,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.job, required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: Material(
      color: GoColors.night,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: serviceColor(job.service.name), shape: BoxShape.circle),
                child: Icon(serviceIcon(job.service.name), color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _LiveDot(),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'status.${job.status.wire}'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${'service.${job.service.name}'.tr} · ${job.code}', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              Text(
                'home.track'.tr,
                style: const TextStyle(color: GoColors.accent, fontWeight: FontWeight.w800),
              ),
              const Icon(Icons.chevron_right, color: GoColors.accent),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Small pulsing dot that signals a live, updating trip.
class _LiveDot extends StatefulWidget {
  const _LiveDot();
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
    child: Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(color: GoColors.success, shape: BoxShape.circle),
    ),
  );
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.job, required this.onTap});
  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(serviceIcon(job.service.name), size: 18, color: serviceColor(job.service.name)),
                  const SizedBox(width: 6),
                  Text('service.${job.service.name}'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  MoneyText(job.fare.totalCentavos, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              // Takes the leftover space and ellipsizes, so the card never overflows.
              Expanded(
                child: Text(job.dropoff.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: GoColors.muted)),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(formatManilaDate(job.createdAt), style: TextStyle(fontSize: 12, color: GoColors.muted)),
                  ),
                  StatusChip('status.${job.status.wire}'.tr, color: jobStatusColor(job.status)),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Lightweight placeholder while recent orders load (no shimmer: cheap on low-end phones).
class _RecentSkeleton extends StatelessWidget {
  const _RecentSkeleton();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
    child: Row(
      children: [
        for (var i = 0; i < 2; i++) ...[
          Expanded(
            child: Container(
              height: 128,
              decoration: BoxDecoration(color: GoColors.line.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
            ),
          ),
          if (i == 0) const SizedBox(width: 10),
        ],
      ],
    ),
  );
}
