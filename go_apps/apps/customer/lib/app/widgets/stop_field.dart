import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

/// Tappable address row that opens the shared location picker.
class StopField extends StatelessWidget {
  const StopField({
    super.key,
    required this.label,
    required this.stop,
    required this.onPicked,
    this.icon = Icons.place,
    this.color = GoColors.primary,
  });
  final String label;
  final Stop? stop;
  final ValueChanged<Stop> onPicked;
  final IconData icon;
  final Color color;

  bool get _hasAddress => stop != null && stop!.address.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(fontSize: 12, color: GoColors.muted)),
      subtitle: Text(
        _hasAddress ? stop!.address : 'common.choose_location'.tr,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _hasAddress ? GoColors.ink : GoColors.muted),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final r = await Get.toNamed<dynamic>(
          CoreRoutes.locationPicker,
          arguments: PickerArgs(title: label, initial: stop?.location),
        );
        if (r is Stop) onPicked(r);
      },
    ),
  );
}
