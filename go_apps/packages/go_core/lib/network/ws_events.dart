import '../models/geo.dart';
import '../models/job.dart';
import '../models/merchant.dart';
import '../models/merchant_admin.dart';
import '../models/misc.dart';
import '../models/rider.dart';

/// Event type names (Section 7.6).
class WsTypes {
  WsTypes._();
  static const ping = 'ping';
  static const pong = 'pong';
  static const riderLocation = 'rider.location';
  static const jobSubscribe = 'job.subscribe';
  static const jobUnsubscribe = 'job.unsubscribe';
  static const jobUpdated = 'job.updated';
  static const offerNew = 'offer.new';
  static const offerExpired = 'offer.expired';
  static const riderProfileUpdated = 'rider.profile_updated';
  static const chatMessage = 'chat.message';
  static const orderNew = 'order.new';
  static const orderUpdated = 'order.updated';
  static const merchantUpdated = 'merchant.updated';
}

/// Typed server -> client events.
sealed class WsEvent {
  const WsEvent(this.id);
  final String id;

  static WsEvent parse(Map<String, dynamic> msg) {
    final id = '${msg['id'] ?? ''}';
    final type = '${msg['type']}';
    final data = Map<String, dynamic>.from((msg['data'] as Map?) ?? const {});
    Map<String, dynamic> m(String k) => Map<String, dynamic>.from(data[k] as Map);
    try {
      return switch (type) {
        WsTypes.pong => PongEvent(id),
        WsTypes.jobUpdated => JobUpdatedEvent(id, Job.fromJson(m('job'))),
        WsTypes.riderLocation => RiderLocationEvent(
          id,
          '${data['job_id']}',
          LatLng.fromJson(m('location')),
          (data['heading'] as num?)?.toDouble(),
        ),
        WsTypes.offerNew => OfferNewEvent(id, JobOffer.fromJson(m('offer'))),
        WsTypes.offerExpired => OfferExpiredEvent(id, '${data['offer_id']}'),
        WsTypes.riderProfileUpdated => RiderProfileUpdatedEvent(id, RiderProfile.fromJson(m('profile'))),
        WsTypes.chatMessage => ChatMessageEvent(id, ChatMessage.fromJson(m('message'))),
        WsTypes.orderNew => OrderNewEvent(id, MerchantOrder.fromJson(m('order'))),
        WsTypes.orderUpdated => OrderUpdatedEvent(id, MerchantOrder.fromJson(m('order'))),
        WsTypes.merchantUpdated => MerchantUpdatedEvent(id, Merchant.fromJson(m('merchant'))),
        _ => UnknownEvent(id, type, data),
      };
    } catch (_) {
      return UnknownEvent(id, type, data);
    }
  }
}

class PongEvent extends WsEvent {
  const PongEvent(super.id);
}

class JobUpdatedEvent extends WsEvent {
  const JobUpdatedEvent(super.id, this.job);
  final Job job;
}

class RiderLocationEvent extends WsEvent {
  const RiderLocationEvent(super.id, this.jobId, this.location, this.heading);
  final String jobId;
  final LatLng location;
  final double? heading;
}

class OfferNewEvent extends WsEvent {
  const OfferNewEvent(super.id, this.offer);
  final JobOffer offer;
}

class OfferExpiredEvent extends WsEvent {
  const OfferExpiredEvent(super.id, this.offerId);
  final String offerId;
}

class RiderProfileUpdatedEvent extends WsEvent {
  const RiderProfileUpdatedEvent(super.id, this.profile);
  final RiderProfile profile;
}

class ChatMessageEvent extends WsEvent {
  const ChatMessageEvent(super.id, this.message);
  final ChatMessage message;
}

class OrderNewEvent extends WsEvent {
  const OrderNewEvent(super.id, this.order);
  final MerchantOrder order;
}

class OrderUpdatedEvent extends WsEvent {
  const OrderUpdatedEvent(super.id, this.order);
  final MerchantOrder order;
}

class MerchantUpdatedEvent extends WsEvent {
  const MerchantUpdatedEvent(super.id, this.merchant);
  final Merchant merchant;
}

class UnknownEvent extends WsEvent {
  const UnknownEvent(super.id, this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
}
