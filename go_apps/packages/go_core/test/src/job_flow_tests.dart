import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';

Job baseJob({required String service, required String status, List<String> actions = const [], bool? ready, String method = 'cash'}) {
  final j = (jsonDecode(File('assets/mock/jobs.json').readAsStringSync()) as List).first as Map<String, dynamic>;
  j['service'] = service;
  j['status'] = status;
  j['allowed_actions'] = actions;
  j['payment'] = {'method': method, 'status': 'pending'};
  if (ready != null) j['food'] = {'items': <Object>[], 'subtotal_centavos': 0, 'is_ready': ready};
  return Job.fromJson(j);
}

void main() {
  group('rider step mapping (allowed_actions -> button)', () {
    test('ride walk-through', () {
      expect(
        riderNextStep(baseJob(service: 'ride', status: 'rider_assigned', actions: ['arrived_pickup', 'chat']))!.target,
        JobStatus.arrivedPickup,
      );
      expect(riderNextStep(baseJob(service: 'ride', status: 'arrived_pickup', actions: ['picked_up']))!.labelKey, 'rider.step.picked_up');
      expect(riderNextStep(baseJob(service: 'ride', status: 'picked_up', actions: ['arrived_dropoff']))!.target, JobStatus.arrivedDropoff);
      final done = riderNextStep(baseJob(service: 'ride', status: 'arrived_dropoff', actions: ['completed']))!;
      expect(done.target, JobStatus.completed);
      expect(done.needsProofPhoto, isFalse, reason: 'rides need no proof photo');
    });

    test('food/padala/pabili completion needs proof photo', () {
      for (final s in ['food', 'padala', 'pabili']) {
        expect(riderNextStep(baseJob(service: s, status: 'arrived_dropoff', actions: ['completed']))!.needsProofPhoto, isTrue);
      }
    });

    test('pabili needs receipt at the store, then waits for customer', () {
      final step = riderNextStep(baseJob(service: 'pabili', status: 'arrived_pickup', actions: ['items_purchased', 'chat']))!;
      expect(step.target, JobStatus.itemsPurchased);
      expect(step.needsReceipt, isTrue);
      final waiting = baseJob(service: 'pabili', status: 'items_purchased', actions: ['chat']);
      expect(riderNextStep(waiting), isNull);
      expect(riderWaitingReasonKey(waiting), 'rider.wait.customer_confirm');
    });

    test('food waits for the merchant to mark ready', () {
      final j = baseJob(service: 'food', status: 'arrived_pickup', actions: ['chat'], ready: false);
      expect(riderNextStep(j), isNull);
      expect(riderWaitingReasonKey(j), 'rider.wait.food_not_ready');
    });
  });

  group('customer timeline', () {
    test('food with online payment shows payment + merchant steps', () {
      expect(timelineStatusesFor(ServiceType.food, onlinePayment: true).take(3), [
        JobStatus.pendingPayment,
        JobStatus.merchantPending,
        JobStatus.merchantPreparing,
      ]);
      expect(timelineStatusesFor(ServiceType.ride, onlinePayment: false).first, JobStatus.searching);
      expect(timelineStatusesFor(ServiceType.pabili, onlinePayment: false), contains(JobStatus.itemsPurchased));
    });

    test('marks done/current/upcoming', () {
      final steps = buildTimeline(baseJob(service: 'ride', status: 'arrived_pickup'));
      expect(steps.map((s) => s.state).toList(), [
        TimelineStepState.done,
        TimelineStepState.done,
        TimelineStepState.current,
        TimelineStepState.upcoming,
        TimelineStepState.upcoming,
        TimelineStepState.upcoming,
      ]);
    });
  });

  group('job status -> MerchantOrder.status', () {
    MerchantOrderStatus m(JobStatus s, {bool ready = false, PartyRole? by}) => merchantOrderStatusFor(s, isReady: ready, cancelledBy: by);
    test('mapping from Section 7.5', () {
      expect(m(JobStatus.merchantPending), MerchantOrderStatus.newOrder);
      for (final s in [JobStatus.merchantPreparing, JobStatus.searching, JobStatus.riderAssigned, JobStatus.arrivedPickup]) {
        expect(m(s), MerchantOrderStatus.preparing);
        expect(m(s, ready: true), MerchantOrderStatus.ready);
      }
      expect(m(JobStatus.pickedUp), MerchantOrderStatus.pickedUp);
      expect(m(JobStatus.arrivedDropoff), MerchantOrderStatus.pickedUp);
      expect(m(JobStatus.completed), MerchantOrderStatus.completed);
      expect(m(JobStatus.cancelled, by: PartyRole.merchant), MerchantOrderStatus.rejected);
      expect(m(JobStatus.cancelled, by: PartyRole.system), MerchantOrderStatus.cancelled);
      expect(m(JobStatus.cancelled, by: PartyRole.customer), MerchantOrderStatus.cancelled);
    });
  });
}
