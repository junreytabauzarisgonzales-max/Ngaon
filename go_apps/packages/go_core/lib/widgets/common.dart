import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../network/ws_client.dart';
import '../services/network_status.dart';
import '../theme/go_theme.dart';
import '../utils/error_handler.dart';
import '../utils/money.dart';

/// `₱1,234.50`
class MoneyText extends StatelessWidget {
  const MoneyText(this.centavos, {super.key, this.style, this.showSign = false});
  final int centavos;
  final TextStyle? style;
  final bool showSign;
  @override
  Widget build(BuildContext context) => Text(formatCentavos(centavos, showSign: showSign), style: style);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.icon = Icons.inbox_outlined, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: GoColors.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: GoColors.muted, fontSize: 15),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off,
    message: GoErrors.message(error),
    action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text('common.retry'.tr)),
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Shown at the top of every screen when requests fail or the socket is down.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final net = Get.find<NetworkStatus>();
    final ws = Get.isRegistered<GoWsClient>() ? Get.find<GoWsClient>() : null;
    return Obx(() {
      final offline = !net.online.value;
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: offline
            ? Material(
                color: GoColors.warning,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('common.offline'.tr, style: const TextStyle(color: Colors.white)),
                        ),
                        if (ws != null && ws.state.value == WsState.connecting)
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      );
    });
  }
}

Future<bool> confirmDialog({required String title, String? message, String? confirmText, bool danger = false}) async {
  final r = await Get.dialog<bool>(
    AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: Text('common.cancel'.tr)),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: GoColors.danger, minimumSize: const Size(88, 44))
              : FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Get.back(result: true),
          child: Text(confirmText ?? 'common.confirm'.tr),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Lazy-loaded, disk-cached network image with a light placeholder.
class GoImage extends StatelessWidget {
  const GoImage(this.url, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.radius = 12, this.icon = Icons.image});
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: GoColors.line,
      child: Icon(icon, color: GoColors.muted),
    );
    final u = url;
    Widget child;
    if (u == null || u.isEmpty || !AppConfig.current.enablePlatformPlugins) {
      child = placeholder;
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      child = CachedNetworkImage(
        imageUrl: u,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: width == null ? null : (width! * dpr).round(),
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
      ],
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.color = GoColors.primary});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );
}

Color jobStatusColor(JobStatus s) => switch (s) {
  JobStatus.completed => GoColors.success,
  JobStatus.cancelled => GoColors.danger,
  JobStatus.pendingPayment || JobStatus.itemsPurchased => GoColors.warning,
  _ => GoColors.primary,
};

class FareBreakdown extends StatelessWidget {
  const FareBreakdown({super.key, required this.lines, required this.total});
  final List<({String label, int amount})> lines;
  final int total;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(l.label)),
              MoneyText(l.amount),
            ],
          ),
        ),
      const Divider(height: 16),
      Row(
        children: [
          Expanded(
            child: Text('common.total'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          MoneyText(total, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ],
      ),
    ],
  );
}

/// Counts down to [deadline]; calls [onExpired] once.
class CountdownText extends StatefulWidget {
  const CountdownText({super.key, required this.deadline, this.style, this.onExpired, this.builder});
  final DateTime deadline;
  final TextStyle? style;
  final VoidCallback? onExpired;
  final Widget Function(BuildContext, Duration left)? builder;
  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _t;
  bool _fired = false;

  Duration get _left {
    final d = widget.deadline.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_left == Duration.zero && !_fired) {
        _fired = true;
        widget.onExpired?.call();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    if (widget.builder != null) return widget.builder!(context, left);
    final m = left.inMinutes, s = left.inSeconds % 60;
    return Text('$m:${s.toString().padLeft(2, '0')}', style: widget.style);
  }
}

/// Pull-to-refresh list with "load more" for cursor pagination.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onRefresh,
    required this.hasMore,
    required this.onLoadMore,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, goNavBarClearanceLocal),
    this.separator = const SizedBox(height: 10),
  });
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  final Future<void> Function() onRefresh;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final EdgeInsets padding;
  final Widget separator;

  static const goNavBarClearanceLocal = 110.0;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView.separated(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => separator,
      itemBuilder: (c, i) {
        if (i == items.length) {
          onLoadMore();
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return itemBuilder(c, items[i]);
      },
    ),
  );
}
