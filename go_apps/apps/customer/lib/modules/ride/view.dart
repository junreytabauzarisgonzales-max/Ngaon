import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/widgets/stop_field.dart';
import 'controller.dart';

class RideView extends GetView<RideController> {
  const RideView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('service.ride'.tr)),
      body: Column(
        children: [
          Expanded(
            child: Obx(
              () => GoMap(
                center: c.pickup.value?.location ?? LatLng.bongao,
                interactive: false,
                markers: [
                  if (c.pickup.value != null) GoMarker('p', c.pickup.value!.location, MarkerKind.pickup),
                  if (c.dropoff.value != null) GoMarker('d', c.dropoff.value!.location, MarkerKind.dropoff),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Obx(
                () => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StopField(
                      label: 'common.pickup'.tr,
                      stop: c.pickup.value,
                      icon: Icons.trip_origin,
                      onPicked: (s) => c.pickup.value = s,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(onPressed: c.swap, icon: const Icon(Icons.swap_vert), tooltip: 'ride.swap'.tr),
                    ),
                    StopField(
                      label: 'ride.where_to'.tr,
                      stop: c.dropoff.value,
                      color: GoColors.danger,
                      onPicked: (s) => c.dropoff.value = s,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('ride.see_price'),
                      onPressed: c.ready ? c.seePrice : null,
                      child: Text('ride.see_price'.tr),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
