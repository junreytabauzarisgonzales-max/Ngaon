import '../models/enums.dart';
import '../models/job.dart';

/// The single next action a rider can take on a job, derived from
/// `allowed_actions` (which lists target statuses for the rider app).
class RiderStep {
  const RiderStep({required this.target, required this.labelKey, this.needsProofPhoto = false, this.needsReceipt = false});

  final JobStatus target;

  /// Translation key for the primary button.
  final String labelKey;
  final bool needsProofPhoto;
  final bool needsReceipt;
}

/// Forward order of rider-driven statuses.
const _riderTargets = [
  JobStatus.arrivedPickup,
  JobStatus.itemsPurchased,
  JobStatus.pickedUp,
  JobStatus.arrivedDropoff,
  JobStatus.completed,
];

/// Returns the rider's next step, or null when the rider must wait (e.g. food
/// not ready, Pabili awaiting customer confirmation, or job final).
RiderStep? riderNextStep(Job job) {
  for (final target in _riderTargets) {
    if (!job.allowedActions.contains(target.wire)) continue;
    return switch (target) {
      JobStatus.arrivedPickup => const RiderStep(target: JobStatus.arrivedPickup, labelKey: 'rider.step.arrived_pickup'),
      JobStatus.itemsPurchased => const RiderStep(
        target: JobStatus.itemsPurchased,
        labelKey: 'rider.step.items_purchased',
        needsReceipt: true,
      ),
      JobStatus.pickedUp => const RiderStep(target: JobStatus.pickedUp, labelKey: 'rider.step.picked_up'),
      JobStatus.arrivedDropoff => const RiderStep(target: JobStatus.arrivedDropoff, labelKey: 'rider.step.arrived_dropoff'),
      _ => RiderStep(target: JobStatus.completed, labelKey: 'rider.step.completed', needsProofPhoto: job.service != ServiceType.ride),
    };
  }
  return null;
}

/// Why a rider is waiting when [riderNextStep] is null.
String? riderWaitingReasonKey(Job job) {
  if (job.status.isFinal) return null;
  if (job.status == JobStatus.itemsPurchased) return 'rider.wait.customer_confirm';
  if (job.service == ServiceType.food && job.food?.isReady == false && job.status == JobStatus.arrivedPickup) {
    return 'rider.wait.food_not_ready';
  }
  return 'rider.wait.generic';
}

/// Statuses shown on the customer timeline for a service, in order.
List<JobStatus> timelineStatusesFor(ServiceType service, {required bool onlinePayment}) => [
  if (onlinePayment) JobStatus.pendingPayment,
  if (service == ServiceType.food) ...[JobStatus.merchantPending, JobStatus.merchantPreparing],
  JobStatus.searching,
  JobStatus.riderAssigned,
  JobStatus.arrivedPickup,
  if (service == ServiceType.pabili) JobStatus.itemsPurchased,
  JobStatus.pickedUp,
  JobStatus.arrivedDropoff,
  JobStatus.completed,
];

enum TimelineStepState { done, current, upcoming }

class TimelineStep {
  const TimelineStep(this.status, this.state, this.at);
  final JobStatus status;
  final TimelineStepState state;
  final DateTime? at;
}

/// Builds the timeline rows for a job. Cancelled jobs show what happened
/// plus a final cancelled row.
List<TimelineStep> buildTimeline(Job job) {
  final reached = {for (final t in job.timeline) t.status: t.at};
  if (job.status == JobStatus.cancelled) {
    return [for (final t in job.timeline) TimelineStep(t.status, TimelineStepState.done, t.at)];
  }
  final statuses = timelineStatusesFor(job.service, onlinePayment: job.payment.method.isOnline);
  final currentIdx = statuses.indexOf(job.status);
  return [
    for (var i = 0; i < statuses.length; i++)
      TimelineStep(
        statuses[i],
        job.status == JobStatus.completed || (currentIdx >= 0 && i < currentIdx)
            ? TimelineStepState.done
            : (i == currentIdx ? TimelineStepState.current : TimelineStepState.upcoming),
        reached[statuses[i]],
      ),
  ];
}

/// Job status -> `MerchantOrder.status` (Section 7.5). This is backend logic,
/// mirrored here for the mock backend and tested against the contract.
MerchantOrderStatus merchantOrderStatusFor(JobStatus status, {required bool isReady, PartyRole? cancelledBy}) {
  switch (status) {
    case JobStatus.pendingPayment:
    case JobStatus.merchantPending:
      return MerchantOrderStatus.newOrder;
    case JobStatus.merchantPreparing:
    case JobStatus.searching:
    case JobStatus.riderAssigned:
    case JobStatus.arrivedPickup:
    case JobStatus.itemsPurchased:
      return isReady ? MerchantOrderStatus.ready : MerchantOrderStatus.preparing;
    case JobStatus.pickedUp:
    case JobStatus.arrivedDropoff:
      return MerchantOrderStatus.pickedUp;
    case JobStatus.completed:
      return MerchantOrderStatus.completed;
    case JobStatus.cancelled:
      return cancelledBy == PartyRole.merchant ? MerchantOrderStatus.rejected : MerchantOrderStatus.cancelled;
  }
}
