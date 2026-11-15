import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';

Object? fixture(String name) => jsonDecode(File('assets/mock/$name').readAsStringSync());
Map<String, dynamic> obj(String name) => fixture(name)! as Map<String, dynamic>;
List<Map<String, dynamic>> list(String name) => (fixture(name)! as List).cast<Map<String, dynamic>>();

/// Every fixture must survive fromJson -> toJson unchanged: this pins the
/// Dart models to the contract examples the Golang backend will use.
void roundTrip<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) from, Map<String, dynamic> Function(T) to) {
  expect(jsonDecode(jsonEncode(to(from(json)))), equals(json));
}

void main() {
  test('User / AuthResult', () {
    for (final u in obj('users.json').values) {
      roundTrip(u as Map<String, dynamic>, User.fromJson, (x) => x.toJson());
    }
    roundTrip(obj('auth_result.json'), AuthResult.fromJson, (x) => x.toJson());
  });

  test('Merchant with full menu', () {
    final ms = list('merchants.json');
    expect(ms, hasLength(5));
    for (final m in ms) {
      roundTrip(m, Merchant.fromJson, (x) => x.toJson());
    }
    final menu = Merchant.fromJson(ms.first).menu!;
    expect(menu.expand((c) => c.items).any((i) => i.addonGroups.isNotEmpty), isTrue);
    expect(menu.expand((c) => c.items).any((i) => !i.isAvailable), isTrue, reason: 'sold-out state is seeded');
  });

  test('Places, geo, service area', () {
    for (final p in list('saved_places.json')) {
      roundTrip(p, SavedPlace.fromJson, (x) => x.toJson());
    }
    for (final g in list('geo_places.json')) {
      roundTrip(g, GeoSearchResult.fromJson, (x) => x.toJson());
    }
    final area = ServiceArea.fromJson(obj('service_area.json'));
    roundTrip(obj('service_area.json'), ServiceArea.fromJson, (x) => x.toJson());
    expect(area.contains(LatLng.bongao), isTrue);
    expect(area.contains(const LatLng(lat: 6.05, lng: 121.0)), isFalse, reason: 'Jolo is outside');
  });

  test('Jobs, quote, quote request, offer', () {
    for (final j in list('jobs.json')) {
      roundTrip(j, Job.fromJson, (x) => x.toJson());
    }
    roundTrip(obj('quote.json'), Quote.fromJson, (x) => x.toJson());
    roundTrip(obj('quote_request.json'), QuoteRequest.fromJson, (x) => x.toJson());
    roundTrip(obj('job_offer.json'), JobOffer.fromJson, (x) => x.toJson());
    final job = Job.fromJson(list('jobs.json').first);
    expect(job.createdAt.isUtc, isTrue);
    expect(job.toJson()['created_at'], '2026-11-13T00:10:00Z');
  });

  test('Rider models', () {
    roundTrip(obj('rider_profile.json'), RiderProfile.fromJson, (x) => x.toJson());
    for (final t in list('wallet_transactions.json')) {
      roundTrip(t, WalletTransaction.fromJson, (x) => x.toJson());
    }
    roundTrip(obj('rider_earnings.json'), Earnings.fromJson, (x) => x.toJson());
  });

  test('Merchant admin models', () {
    roundTrip(obj('merchant_account.json'), MerchantAccount.fromJson, (x) => x.toJson());
    final orders = list('merchant_orders.json');
    for (final o in orders) {
      roundTrip(o, MerchantOrder.fromJson, (x) => x.toJson());
    }
    expect(MerchantOrder.fromJson(orders[1]).status, MerchantOrderStatus.newOrder);
    expect(MerchantOrder.fromJson(orders[1]).toJson()['status'], 'new');
    roundTrip(obj('sales_report.json'), SalesReport.fromJson, (x) => x.toJson());
    for (final p in list('payouts.json')) {
      roundTrip(p, Payout.fromJson, (x) => x.toJson());
    }
  });

  test('Chat, uploads', () {
    for (final m in list('chat_messages.json')) {
      roundTrip(m, ChatMessage.fromJson, (x) => x.toJson());
    }
    roundTrip(obj('upload_ticket.json'), UploadTicket.fromJson, (x) => x.toJson());
  });

  test('MenuItemInput omits ids for new groups/options', () {
    final input = MenuItemInput(
      categoryId: 'c1',
      name: 'Tea',
      priceCentavos: 3000,
      isAvailable: true,
      addonGroups: [
        AddonGroupInput(
          id: 'g1',
          name: 'Size',
          minSelect: 1,
          maxSelect: 1,
          options: [AddonOptionInput(name: 'Large', priceCentavos: 1000, isAvailable: true)],
        ),
      ],
    ).toJson();
    expect(input['addon_groups'][0]['id'], 'g1');
    expect((input['addon_groups'][0]['options'][0] as Map).containsKey('id'), isFalse);
  });

  test('StoreUpdate sends explicit null to resume orders', () {
    expect(StoreUpdate(clearPause: true).toJson(), {'paused_until': null});
    expect(StoreUpdate(isOpen: false).toJson(), {'is_open': false});
  });

  test('enum wire names', () {
    expect(JobStatus.riderAssigned.wire, 'rider_assigned');
    expect(JobStatus.fromWire('items_purchased'), JobStatus.itemsPurchased);
    expect(UploadPurpose.proofOfDelivery.wire, 'proof_of_delivery');
    expect(RejectReason.outOfStock.wire, 'out_of_stock');
    expect(MerchantOrderStatus.newOrder.wire, 'new');
  });
}
