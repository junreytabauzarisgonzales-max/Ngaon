import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../../models/enums.dart';
import '../../models/geo.dart';
import '../../models/job.dart';
import '../../models/merchant_admin.dart';
import '../../network/api_exception.dart';
import '../../utils/job_flow.dart';
import '../../utils/time.dart';

typedef JsonMap = Map<String, dynamic>;
typedef FixtureLoader = Future<String> Function(String fileName);

Future<String> bundleFixtureLoader(String name) => rootBundle.loadString('packages/go_core/assets/mock/$name');

/// In-memory backend that behaves like the Golang API in Section 7, and
/// simulates the two parties that are not using this app (Section 8).
///
/// State is kept as contract-shaped JSON so every response is serialized
/// exactly like the real API.
class MockBackend {
  MockBackend({required this.app, FixtureLoader? loader, this.speed = 1.0, this.simulate = true, Random? random})
    : _load = loader ?? bundleFixtureLoader,
      _rand = random ?? Random(7);

  final GoApp app;
  final FixtureLoader _load;
  final Random _rand;

  /// Delay multiplier (1.0 = real-time demo pace).
  double speed;

  /// When false no background timers are started (unit tests).
  bool simulate;

  static const mockOtp = '123456';
  static const _uuid = Uuid();

  final _out = StreamController<JsonMap>.broadcast();
  Stream<JsonMap> get outgoing => _out.stream;

  final _timers = <Timer>{};
  int _codeSeq = 4900;

  // ---- state ----
  late JsonMap _users;
  JsonMap? me;
  String? _phone;
  late List<JsonMap> merchants;
  late List<JsonMap> places;
  late List<JsonMap> geoPlaces;
  late JsonMap serviceArea;
  late List<JsonMap> jobs;
  final Map<String, JsonMap> _quotes = {};
  final Map<String, JsonMap> _quoteRequests = {};
  final Map<String, String> _idempotency = {};
  final Map<String, List<JsonMap>> chats = {};
  late JsonMap riderProfile;
  late List<JsonMap> walletTxs;
  JsonMap? currentOffer;
  String? riderActiveJobId;
  late JsonMap merchantAccount;
  late List<JsonMap> orders;
  late List<JsonMap> payouts;
  late JsonMap _salesExample;
  final Set<String> subscribedJobs = {};
  final Map<String, int> _sessionEarnings = {};

  Future<void> init() async {
    Future<Object?> j(String n) async => jsonDecode(await _load(n));
    List<JsonMap> list(Object? o) => (o as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    _users = (await j('users.json')) as JsonMap;
    merchants = list(await j('merchants.json'));
    places = list(await j('saved_places.json'));
    geoPlaces = list(await j('geo_places.json'));
    serviceArea = (await j('service_area.json')) as JsonMap;
    jobs = list(await j('jobs.json'));
    riderProfile = (await j('rider_profile.json')) as JsonMap;
    walletTxs = list(await j('wallet_transactions.json'));
    merchantAccount = (await j('merchant_account.json')) as JsonMap;
    orders = list(await j('merchant_orders.json'));
    payouts = list(await j('payouts.json'));
    _salesExample = (await j('sales_report.json')) as JsonMap;
    for (final m in list(await j('chat_messages.json'))) {
      chats.putIfAbsent(m['job_id'] as String, () => []).add(m);
    }
    // Rebase "new" fixture orders so their deadline is in the future.
    for (final o in orders.where((o) => o['status'] == 'new')) {
      o['created_at'] = _now();
      o['merchant_accept_deadline'] = toIsoUtc(DateTime.now().add(const Duration(minutes: 3)));
      _scheduleOrderDeadline(o['id'] as String);
    }
  }

  void dispose() {
    stopSimulations();
    _out.close();
  }

  void stopSimulations() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  // ---- helpers ----
  static JsonMap copy(JsonMap m) => jsonDecode(jsonEncode(m)) as JsonMap;
  static String _now() => toIsoUtc(DateTime.now());
  String _id() => _uuid.v4();
  String _code() => 'GO-${_codeSeq++}';

  Duration _d(num seconds) => Duration(milliseconds: max(1, (seconds * 1000 * speed).round()));

  void _after(num seconds, void Function() fn) {
    if (!simulate) return;
    late Timer t;
    t = Timer(_d(seconds), () {
      _timers.remove(t);
      fn();
    });
    _timers.add(t);
  }

  /// Simulated network latency.
  Future<T> call<T>(T Function() fn) async {
    await Future<void>.delayed(Duration(milliseconds: max(1, (200 * speed).round())));
    return fn();
  }

  Never fail(String code, String message, {int status = 400, Map<String, String> fields = const {}}) =>
      throw ApiException(code, message, fields: fields, httpStatus: status);

  void emit(String type, JsonMap data) {
    if (_out.isClosed) return;
    _out.add({'type': type, 'id': _id(), 'data': data});
  }

  void _requireAuth() {
    if (me == null) fail(ErrorCodes.unauthorized, 'Not logged in', status: 401);
  }

  static int _int(Object? v) => (v as num).toInt();

  LatLng _ll(Object? m) => LatLng.fromJson(Map<String, dynamic>.from(m as Map));

  bool _inArea(LatLng p) {
    final zones = (serviceArea['zones'] as List).cast<Map>();
    return zones.any((z) => ServiceZone.fromJson(Map<String, dynamic>.from(z)).contains(p));
  }

  // =================== AUTH ===================
  JsonMap requestOtp(String phone) {
    if (!RegExp(r'^\+639\d{9}$').hasMatch(phone)) {
      fail(ErrorCodes.validationFailed, 'Invalid phone', fields: {'phone': 'invalid'});
    }
    return {'expires_in_seconds': 300, 'resend_after_seconds': 60};
  }

  JsonMap verifyOtp(String phone, String code, GoApp forApp) {
    if (code != mockOtp) fail(ErrorCodes.otpInvalid, 'Wrong code');
    final isNew = phone.endsWith('1111');
    final base = copy(_users[forApp.name] as JsonMap);
    base['phone'] = phone;
    if (isNew) base['name'] = '';
    me = base;
    _phone = phone;
    if (forApp == GoApp.rider && isNew) {
      riderProfile
        ..['status'] = 'incomplete'
        ..remove('vehicle')
        ..remove('rating');
    }
    _startAppSimulation();
    return {'access_token': 'mock-access-${_id()}', 'refresh_token': 'mock-refresh-${_id()}', 'user': copy(me!), 'is_new_user': isNew};
  }

  /// Restores a session after app restart (tokens survive in secure storage).
  void restoreSession() {
    me ??= copy(_users[app.name] as JsonMap);
    _startAppSimulation();
  }

  void logout() {
    stopSimulations();
    me = null;
  }

  JsonMap getMe() {
    _requireAuth();
    return copy(me!);
  }

  JsonMap updateMe(JsonMap patch) {
    _requireAuth();
    me!.addAll(patch);
    return copy(me!);
  }

  void _startAppSimulation() {
    if (app == GoApp.merchant && merchantAccount['merchant']['is_open'] == true) _scheduleNewOrder(8);
    if (app == GoApp.rider && riderProfile['is_online'] == true) _scheduleOffer(5);
  }

  // =================== GEO ===================
  List<JsonMap> getPlaces() => places.map(copy).toList();

  JsonMap addPlace(String label, String address, JsonMap location) {
    final p = {'id': _id(), 'label': label, 'address': address, 'location': location};
    places.add(p);
    return copy(p);
  }

  void deletePlace(String id) => places.removeWhere((p) => p['id'] == id);

  JsonMap reverse(LatLng p) {
    JsonMap? best;
    var bestD = 1 << 30;
    for (final g in [...geoPlaces, ...merchants]) {
      final d = p.distanceTo(_ll(g['location']));
      if (d < bestD) {
        bestD = d;
        best = g;
      }
    }
    if (best == null) return {'address': 'Bongao, Tawi-Tawi'};
    final name = best['name'];
    return {'address': bestD < 80 ? '$name, Bongao' : 'Near $name, Bongao'};
  }

  List<JsonMap> search(String q, LatLng near) {
    final lq = q.toLowerCase().trim();
    final all =
        [
            ...geoPlaces,
            ...merchants.map((m) => {'name': m['name'], 'address': m['address'], 'location': m['location']}),
          ].where((g) => lq.isEmpty || '${g['name']} ${g['address']}'.toLowerCase().contains(lq)).toList()
          ..sort((a, b) => near.distanceTo(_ll(a['location'])).compareTo(near.distanceTo(_ll(b['location']))));
    return all.take(10).map(copy).toList();
  }

  // =================== MERCHANTS (public) ===================
  JsonMap _publicMerchant(JsonMap m, {LatLng? near, bool withMenu = false}) {
    final c = copy(m);
    if (!withMenu) {
      c.remove('menu');
    } else {
      // public menu hides nothing; sold-out items are returned with is_available=false
    }
    if (near != null) c['distance_m'] = near.distanceTo(_ll(m['location']));
    return c;
  }

  (List<JsonMap>, String?) listMerchants(LatLng near, String? q, String? cursor) {
    final lq = (q ?? '').toLowerCase();
    final all =
        merchants
            .where((m) {
              if (lq.isEmpty) return true;
              final names = [
                m['name'],
                for (final c in (m['menu'] as List))
                  for (final i in (c['items'] as List)) i['name'],
              ];
              return names.any((n) => '$n'.toLowerCase().contains(lq));
            })
            .map((m) => _publicMerchant(m, near: near))
            .toList()
          ..sort((a, b) {
            if (a['is_open'] != b['is_open']) return a['is_open'] == true ? -1 : 1;
            return _int(a['distance_m']).compareTo(_int(b['distance_m']));
          });
    return _paginate(all, cursor, 20);
  }

  JsonMap getMerchant(String id) {
    final m = merchants.firstWhere((m) => m['id'] == id, orElse: () => fail(ErrorCodes.notFound, 'Merchant not found', status: 404));
    return _publicMerchant(m, withMenu: true);
  }

  (List<JsonMap>, String?) _paginate(List<JsonMap> all, String? cursor, int limit) {
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = min(start + limit, all.length);
    return (all.sublist(min(start, all.length), end), end < all.length ? '$end' : null);
  }

  // =================== QUOTES & JOBS (customer) ===================
  JsonMap _findItem(JsonMap merchant, String itemId) {
    for (final c in merchant['menu'] as List) {
      for (final i in c['items'] as List) {
        if (i['id'] == itemId) return i as JsonMap;
      }
    }
    fail(ErrorCodes.itemUnavailable, 'Item not found', status: 409);
  }

  JsonMap quote(JsonMap req) {
    _requireAuth();
    final pickup = _ll(req['pickup']['location']);
    final dropoff = _ll(req['dropoff']['location']);
    if (!_inArea(pickup) || !_inArea(dropoff)) fail(ErrorCodes.outOfServiceArea, 'Outside Bongao service area', status: 422);
    final distance = (pickup.distanceTo(dropoff) * 1.3).round(); // road factor
    final duration = max(180, (distance / 1000 / 22 * 3600).round());
    final km = (distance / 1000).ceil();
    final service = req['service'] as String;
    final lines = <JsonMap>[];
    int? maxBudget;
    void line(String label, int amount) => lines.add({'label': label, 'amount_centavos': amount});
    final kmLabel = 'Distance ${(distance / 100).round() / 10} km';
    switch (service) {
      case 'ride':
        line('Base fare', 4000);
        line(kmLabel, max(0, km - 1) * 1500);
      case 'food':
        final f = req['food'] as JsonMap;
        final m = merchants.firstWhere(
          (m) => m['id'] == f['merchant_id'],
          orElse: () => fail(ErrorCodes.notFound, 'Merchant', status: 404),
        );
        if (m['is_open'] != true || _paused(m)) fail(ErrorCodes.merchantClosed, '${m['name']} is closed', status: 409);
        var subtotal = 0;
        for (final it in f['items'] as List) {
          final item = _findItem(m, it['item_id'] as String);
          if (item['is_available'] != true) fail(ErrorCodes.itemUnavailable, '${item['name']} is sold out', status: 409);
          var unit = _int(item['price_centavos']);
          for (final oid in (it['addon_option_ids'] as List)) {
            final o = _findOption(item, oid as String);
            if (o['is_available'] != true) fail(ErrorCodes.itemUnavailable, '${o['name']} is sold out', status: 409);
            unit += _int(o['price_centavos']);
          }
          subtotal += unit * _int(it['quantity']);
        }
        if (subtotal < _int(m['min_order_centavos'])) {
          fail(ErrorCodes.validationFailed, 'Below minimum order', fields: {'food': 'below_min_order'}, status: 422);
        }
        line('Food subtotal', subtotal);
        line('Delivery fee', 3900 + max(0, km - 1) * 1000);
        line('Service fee', 1000);
      case 'pabili':
        maxBudget = 300000;
        final est = _int(req['pabili']['estimated_item_total_centavos']);
        if (est > maxBudget) {
          fail(ErrorCodes.validationFailed, 'Budget too high', fields: {'estimated_item_total_centavos': 'max_$maxBudget'}, status: 422);
        }
        line('Pabili fee', 6000);
        line(kmLabel, max(0, km - 1) * 1000);
      case 'padala':
        final size = req['padala']['size'];
        line('Base fare (${'$size'})', switch (size) {
          'small' => 5000,
          'medium' => 6500,
          _ => 8500,
        });
        line(kmLabel, max(0, km - 1) * 1500);
    }
    final q = {
      'id': _id(),
      'service': service,
      'distance_m': distance,
      'duration_s': duration,
      'expires_at': toIsoUtc(DateTime.now().add(const Duration(minutes: 5))),
      'breakdown': lines,
      'total_centavos': lines.fold<int>(0, (s, l) => s + _int(l['amount_centavos'])),
      'max_item_budget_centavos': ?maxBudget,
    };
    _quotes[q['id'] as String] = q;
    _quoteRequests[q['id'] as String] = copy(req);
    return copy(q);
  }

  JsonMap _findOption(JsonMap item, String id) {
    for (final g in item['addon_groups'] as List) {
      for (final o in g['options'] as List) {
        if (o['id'] == id) return o as JsonMap;
      }
    }
    fail(ErrorCodes.itemUnavailable, 'Add-on not found', status: 409);
  }

  bool _paused(JsonMap m) {
    final p = m['paused_until'];
    return p != null && DateTime.parse(p as String).isAfter(DateTime.now());
  }

  JsonMap createJob(String quoteId, String method, String? notes, String idempotencyKey) {
    _requireAuth();
    final existing = _idempotency[idempotencyKey];
    if (existing != null) return copy(_job(existing));
    final q = _quotes[quoteId];
    if (q == null || DateTime.parse(q['expires_at'] as String).isBefore(DateTime.now())) {
      fail(ErrorCodes.quoteExpired, 'Quote expired', status: 409);
    }
    final req = _quoteRequests[quoteId]!;
    final job = _buildJob(req, q, method, notes);
    jobs.insert(0, job);
    _idempotency[idempotencyKey] = job['id'] as String;
    _quotes.remove(quoteId);
    if (app == GoApp.customer) _runCustomerJob(job['id'] as String);
    return copy(job);
  }

  JsonMap _buildJob(JsonMap req, JsonMap q, String method, String? notes) {
    final service = req['service'] as String;
    final id = _id();
    final online = method != 'cash';
    final dropoff = copy(req['dropoff'] as JsonMap);
    if (notes != null && notes.isNotEmpty) dropoff['notes'] = notes;
    final job = <String, dynamic>{
      'id': id,
      'code': _code(),
      'service': service,
      'status': online ? 'pending_payment' : (service == 'food' ? 'merchant_pending' : 'searching'),
      'created_at': _now(),
      'updated_at': _now(),
      'pickup': copy(req['pickup'] as JsonMap),
      'dropoff': dropoff,
      'fare': {'breakdown': q['breakdown'], 'total_centavos': q['total_centavos']},
      'payment': {'method': method, 'status': 'pending', if (online) 'checkout_url': 'https://pay.example.com/mock-checkout/$id'},
      'allowed_actions': <String>[],
      'timeline': <JsonMap>[],
    };
    if (service == 'food') {
      final f = req['food'] as JsonMap;
      final m = merchants.firstWhere((m) => m['id'] == f['merchant_id']);
      job['pickup'] = {'address': m['address'], 'location': m['location'], 'contact_name': m['name']};
      job['merchant'] = {'id': m['id'], 'name': m['name'], 'phone_masked': '+63 917 ••• 8890'};
      final lines = <JsonMap>[];
      var subtotal = 0;
      for (final it in f['items'] as List) {
        final item = _findItem(m, it['item_id'] as String);
        final opts = [for (final oid in it['addon_option_ids'] as List) _findOption(item, oid as String)];
        final unit = _int(item['price_centavos']) + opts.fold<int>(0, (s, o) => s + _int(o['price_centavos']));
        final total = unit * _int(it['quantity']);
        subtotal += total;
        lines.add({
          'name': item['name'],
          'quantity': it['quantity'],
          'addons': [for (final o in opts) o['name']],
          if (it['note'] != null) 'note': it['note'],
          'line_total_centavos': total,
        });
      }
      job['food'] = {
        'items': lines,
        'subtotal_centavos': subtotal,
        'is_ready': false,
        if (method == 'cash') 'rider_pays_merchant_centavos': subtotal - subtotal ~/ 10,
      };
    } else if (service == 'pabili') {
      final p = req['pabili'] as JsonMap;
      job['pabili'] = {'store_name': p['store_name'], 'items': p['items']};
    } else if (service == 'padala') {
      final p = copy(req['padala'] as JsonMap);
      final key = p.remove('photo_key');
      if (key != null) p['photo_url'] = _urlForKey(key as String);
      job['padala'] = p;
      job['dropoff']['contact_name'] ??= p['recipient_name'];
      job['dropoff']['contact_phone'] ??= p['recipient_phone'];
    }
    _addTimeline(job);
    job['allowed_actions'] = _customerActions(job);
    return job;
  }

  String _urlForKey(String key) => 'https://picsum.photos/seed/${key.hashCode.abs()}/600/800';

  JsonMap _job(String id) => jobs.firstWhere((j) => j['id'] == id, orElse: () => fail(ErrorCodes.notFound, 'Job not found', status: 404));

  void _addTimeline(JsonMap job) {
    (job['timeline'] as List).add({'status': job['status'], 'at': _now()});
    job['updated_at'] = _now();
  }

  List<String> _customerActions(JsonMap job) {
    final s = job['status'] as String;
    final hasRider = job['rider'] != null;
    final live = !{'completed', 'cancelled'}.contains(s);
    return [
      if ({'pending_payment', 'merchant_pending', 'merchant_preparing', 'searching', 'rider_assigned'}.contains(s)) JobActions.cancel,
      if (live && hasRider) ...[JobActions.chat, JobActions.call],
      if (job['service'] == 'ride' && live && hasRider) ...[JobActions.sos, JobActions.share],
      if (s == 'items_purchased') JobActions.confirmItems,
      if (s == 'completed' && job['rated'] != true) JobActions.rate,
    ];
  }

  List<String> _riderActions(JsonMap job) {
    final s = job['status'] as String;
    final live = !{'completed', 'cancelled'}.contains(s);
    final next = switch (s) {
      'rider_assigned' => ['arrived_pickup'],
      'arrived_pickup' =>
        job['service'] == 'pabili'
            ? ['items_purchased']
            : (job['service'] == 'food' && job['food']['is_ready'] != true ? <String>[] : ['picked_up']),
      'picked_up' => ['arrived_dropoff'],
      'arrived_dropoff' => ['completed'],
      _ => <String>[],
    };
    return [
      ...next,
      if (live) ...[JobActions.chat, JobActions.call],
    ];
  }

  List<String> _actionsFor(JsonMap job) => app == GoApp.rider ? _riderActions(job) : _customerActions(job);

  /// Serializes a job for the current app (allowed_actions depend on X-App).
  JsonMap jobView(JsonMap job) {
    final c = copy(job)..remove('rated');
    c['allowed_actions'] = _actionsFor(job);
    return c;
  }

  void _setStatus(JsonMap job, String status) {
    job['status'] = status;
    _addTimeline(job);
    job['allowed_actions'] = _actionsFor(job);
    _publishJob(job);
  }

  void _publishJob(JsonMap job) {
    job['updated_at'] = _now();
    emit('job.updated', {'job': jobView(job)});
  }

  (List<JsonMap>, String?) listJobs(String filter, String? cursor) {
    _requireAuth();
    final active = filter == 'active';
    final list = jobs
        .where((j) => j['offer_only'] != true && ({'completed', 'cancelled'}.contains(j['status']) != active))
        .map(jobView)
        .toList();
    return _paginate(list, cursor, 20);
  }

  JsonMap getJob(String id) => jobView(_job(id));

  JsonMap cancelJob(String id, String reason) {
    final job = _job(id);
    if (!_customerActions(job).contains(JobActions.cancel)) fail(ErrorCodes.jobNotCancellable, 'Too late to cancel', status: 409);
    job['cancel_reason'] = reason;
    job['cancelled_by'] = 'customer';
    _setStatus(job, 'cancelled');
    return jobView(job);
  }

  JsonMap confirmItems(String id, bool approved) {
    final job = _job(id);
    if (job['status'] != 'items_purchased') fail(ErrorCodes.invalidStatusTransition, 'Nothing to confirm', status: 409);
    if (!approved) {
      job['cancel_reason'] = 'Item total disputed by customer. Go support will contact you.';
      job['cancelled_by'] = 'customer';
      _setStatus(job, 'cancelled');
      return jobView(job);
    }
    _setStatus(job, 'picked_up');
    if (app == GoApp.customer) _after(2, () => _driveRider(id, toDropoff: true));
    return jobView(job);
  }

  void rate(String id) => _job(id)['rated'] = true;

  // ---- customer-side simulation (rider + merchant are fake) ----
  void _runCustomerJob(String id) {
    final job = _job(id);
    if (job['status'] == 'pending_payment') {
      _after(6, () {
        if (job['status'] != 'pending_payment') return;
        job['payment']['status'] = 'paid';
        _setStatus(job, job['service'] == 'food' ? 'merchant_pending' : 'searching');
        _runCustomerJob(id);
      });
      return;
    }
    if (job['status'] == 'merchant_pending') {
      _after(5, () {
        if (job['status'] != 'merchant_pending') return;
        job['food']['prep_time_minutes'] = 15;
        _setStatus(job, 'merchant_preparing');
        _after(3, () {
          if (job['status'] != 'merchant_preparing') return;
          _setStatus(job, 'searching');
          _runCustomerJob(id);
        });
      });
      return;
    }
    if (job['status'] == 'searching') {
      _after(4, () {
        if (job['status'] != 'searching') return;
        final pickup = _ll(job['pickup']['location']);
        job['rider'] = {
          'id': riderProfile['id'],
          'name': 'Jamal H.',
          'photo_url': 'https://picsum.photos/seed/rider1/200',
          'phone_masked': '+63 918 ••• 2222',
          'plate': '123 ABC',
          'make_model': 'Honda Click 125i',
          'color': 'Red',
          'rating': 4.9,
          'location': LatLng(lat: pickup.lat + 0.004, lng: pickup.lng - 0.003).toJson(),
        };
        _setStatus(job, 'rider_assigned');
        _addSystemMessage(id, 'Jamal H. accepted your booking and is on the way.');
        _driveRider(id, toDropoff: false);
      });
    }
  }

  /// Moves the fake rider along a straight line, then advances status.
  void _driveRider(String id, {required bool toDropoff, int steps = 8}) {
    final job = _job(id);
    final from = job['rider']?['location'] != null ? _ll(job['rider']['location']) : _ll(job['pickup']['location']);
    final to = _ll(job[toDropoff ? 'dropoff' : 'pickup']['location']);
    void step(int i) {
      if ({'completed', 'cancelled'}.contains(job['status'])) return;
      final p = from.lerp(to, i / steps);
      job['rider']['location'] = p.toJson();
      emit('rider.location', {'job_id': id, 'location': p.toJson(), 'heading': 45.0});
      if (i < steps) {
        _after(1.2, () => step(i + 1));
        return;
      }
      if (!toDropoff) {
        _setStatus(job, 'arrived_pickup');
        _afterArrivedPickup(id);
      } else {
        _setStatus(job, 'arrived_dropoff');
        _after(3, () {
          if (job['status'] != 'arrived_dropoff') return;
          if (job['service'] != 'ride') job['proof_url'] = 'https://picsum.photos/seed/pod-$id/600/800';
          job['payment']['status'] = 'paid';
          _setStatus(job, 'completed');
        });
      }
    }

    step(1);
  }

  void _afterArrivedPickup(String id) {
    final job = _job(id);
    if (job['service'] == 'food') {
      job['food']
        ..['is_ready'] = true
        ..['ready_at'] = _now();
      _publishJob(job);
    }
    if (job['service'] == 'pabili') {
      _after(5, () {
        if (job['status'] != 'arrived_pickup') return;
        final total = 18000 + _rand.nextInt(20) * 500;
        job['pabili']
          ..['receipt_url'] = 'https://picsum.photos/seed/receipt-$id/600/800'
          ..['item_total_centavos'] = total;
        _addItemsToFare(job, total);
        _setStatus(job, 'items_purchased');
      });
      return;
    }
    _after(3, () {
      if (job['status'] != 'arrived_pickup') return;
      _setStatus(job, 'picked_up');
      _driveRider(id, toDropoff: true);
    });
  }

  void _addItemsToFare(JsonMap job, int total) {
    final fare = job['fare'] as JsonMap;
    (fare['breakdown'] as List).add({'label': 'Items (receipt)', 'amount_centavos': total});
    fare['total_centavos'] = _int(fare['total_centavos']) + total;
  }

  // =================== CHAT ===================
  (List<JsonMap>, String?) messages(String jobId, String? cursor) => _paginate((chats[jobId] ?? []).map(copy).toList(), cursor, 50);

  JsonMap sendMessage(String jobId, String? text, String? imageKey) {
    final sender = app == GoApp.rider ? 'rider' : 'customer';
    final m = _addMessage(jobId, sender, text: text, imageUrl: imageKey == null ? null : _urlForKey(imageKey), broadcast: false);
    final other = sender == 'rider' ? 'customer' : 'rider';
    _after(3, () => _addMessage(jobId, other, text: other == 'rider' ? 'Sige po, salamat!' : 'Okay, thank you!'));
    return m;
  }

  void _addSystemMessage(String jobId, String text) => _addMessage(jobId, 'system', text: text);

  JsonMap _addMessage(String jobId, String sender, {String? text, String? imageUrl, bool broadcast = true}) {
    final m = {'id': _id(), 'job_id': jobId, 'sender': sender, 'text': ?text, 'image_url': ?imageUrl, 'created_at': _now()};
    chats.putIfAbsent(jobId, () => []).add(m);
    if (broadcast) emit('chat.message', {'message': copy(m)});
    return copy(m);
  }

  // =================== UPLOADS ===================
  JsonMap createUpload(String purpose) {
    final key = 'uploads/mock/$purpose/${_id()}.jpg';
    return {'upload_url': 'mock://upload/$key', 'key': key, 'expires_at': toIsoUtc(DateTime.now().add(const Duration(minutes: 15)))};
  }

  // =================== RIDER ===================
  JsonMap getRiderProfile() {
    _requireAuth();
    return copy(riderProfile);
  }

  JsonMap submitRiderProfile(JsonMap input) {
    riderProfile
      ..['vehicle'] = input['vehicle']
      ..['status'] = 'pending_review'
      ..remove('rejection_reason');
    _after(8, () {
      riderProfile['status'] = 'approved';
      emit('rider.profile_updated', {'profile': copy(riderProfile)});
    });
    return copy(riderProfile);
  }

  JsonMap setRiderStatus(bool online) {
    if (online) {
      if (riderProfile['status'] != 'approved') fail(ErrorCodes.riderNotApproved, 'Not approved', status: 403);
      if (_int(riderProfile['balance_centavos']) < _int(riderProfile['min_balance_centavos'])) {
        fail(ErrorCodes.insufficientBalance, 'Top up first', status: 402);
      }
    }
    riderProfile['is_online'] = online;
    if (online) {
      _scheduleOffer(5);
    } else {
      stopSimulations();
      currentOffer = null;
    }
    return copy(riderProfile);
  }

  static const _offerTemplates = ['ride', 'food', 'pabili', 'padala'];
  int _offerSeq = 0;

  void _scheduleOffer(num seconds) => _after(seconds, _makeOffer);

  void _makeOffer() {
    if (riderProfile['is_online'] != true || currentOffer != null || riderActiveJobId != null) return;
    final service = _offerTemplates[_offerSeq++ % _offerTemplates.length];
    final spots = [...geoPlaces];
    final a = spots[_rand.nextInt(spots.length)];
    var b = spots[_rand.nextInt(spots.length)];
    if (b == a) b = spots[(spots.indexOf(a) + 1) % spots.length];
    final req = <String, dynamic>{
      'service': service,
      'pickup': {'address': a['name'], 'location': a['location']},
      'dropoff': {'address': b['name'], 'location': b['location'], 'contact_name': 'Customer'},
    };
    if (service == 'food') {
      final m = merchants.first;
      final item = (m['menu'] as List).first['items'][0] as JsonMap;
      req['food'] = {
        'merchant_id': m['id'],
        'items': [
          {'item_id': item['id'], 'quantity': 2, 'addon_option_ids': <String>[]},
        ],
      };
    } else if (service == 'pabili') {
      req['pickup'] = {'address': 'Bongao Public Market', 'location': geoPlaces.first['location']};
      req['pabili'] = {
        'store_name': 'Bongao Public Market',
        'items': [
          {'name': 'Rice (5 kg)', 'quantity': 1},
          {'name': 'Eggs', 'quantity': 12, 'note': 'Medium size'},
          {'name': 'Cooking oil', 'quantity': 1, 'note': '1 liter'},
        ],
        'estimated_item_total_centavos': 60000,
      };
    } else if (service == 'padala') {
      req['padala'] = {'size': 'small', 'description': 'Documents', 'recipient_name': 'Nur Ali', 'recipient_phone': '+639201234567'};
    }
    final savedMe = me;
    me ??= copy(_users['customer'] as JsonMap);
    final q = quote(req);
    me = savedMe;
    final job = _buildJob(req, q, _rand.nextBool() ? 'cash' : 'gcash', null);
    job['status'] = service == 'food' ? 'merchant_preparing' : 'searching';
    job['timeline'] = [
      {'status': job['status'], 'at': _now()},
    ];
    if (job['payment']['method'] != 'cash') job['payment'] = {'method': job['payment']['method'], 'status': 'paid'};
    if (service == 'food') job['food']['prep_time_minutes'] = 10;
    job['offer_only'] = true;
    jobs.add(job);
    final offer = {
      'id': _id(),
      'job': jobView(job),
      'earnings_centavos':
          (_int(q['total_centavos']) * 0.8).round() - (service == 'food' ? _int(job['food']['subtotal_centavos']) * 8 ~/ 10 : 0),
      'pickup_distance_m': 300 + _rand.nextInt(1500),
      'expires_at': toIsoUtc(DateTime.now().add(const Duration(seconds: 15))),
    };
    if (service == 'food') offer['earnings_centavos'] = 4500 + _rand.nextInt(10) * 100;
    currentOffer = offer;
    emit('offer.new', {'offer': copy(offer)});
    final offerId = offer['id'];
    // Expiry is real-time (15 s) regardless of speed.
    if (simulate) {
      late Timer t;
      t = Timer(Duration(milliseconds: (15000 * min(1.0, speed * 4)).round()), () {
        _timers.remove(t);
        if (currentOffer?['id'] == offerId) {
          currentOffer = null;
          emit('offer.expired', {'offer_id': offerId});
          _scheduleOffer(30);
        }
      });
      _timers.add(t);
    }
  }

  JsonMap? getCurrentOffer() {
    final o = currentOffer;
    if (o == null) return null;
    if (DateTime.parse(o['expires_at'] as String).isBefore(DateTime.now())) {
      currentOffer = null;
      return null;
    }
    return copy(o);
  }

  JsonMap acceptOffer(String offerId) {
    final o = currentOffer;
    if (o == null || o['id'] != offerId) fail(ErrorCodes.offerExpired, 'Offer expired', status: 409);
    currentOffer = null;
    final job = _job(o['job']['id'] as String);
    job.remove('offer_only');
    job['rider'] = {
      'id': riderProfile['id'],
      'name': me?['name'] ?? 'Rider',
      'phone_masked': '+63 918 ••• 2222',
      'plate': riderProfile['vehicle']?['plate'] ?? '',
      'make_model': riderProfile['vehicle']?['make_model'] ?? '',
      'color': riderProfile['vehicle']?['color'] ?? '',
      'rating': riderProfile['rating'],
    };
    job['earnings_centavos'] = o['earnings_centavos'];
    riderActiveJobId = job['id'] as String;
    _setStatus(job, 'rider_assigned');
    _addSystemMessage(job['id'] as String, 'Rider assigned. Chat is open.');
    if (job['service'] == 'food') {
      _after(12, () {
        job['food']
          ..['is_ready'] = true
          ..['ready_at'] = _now();
        job['allowed_actions'] = _riderActions(job);
        _publishJob(job);
      });
    }
    return jobView(job);
  }

  void declineOffer(String offerId) {
    if (currentOffer?['id'] == offerId) currentOffer = null;
    _scheduleOffer(30);
  }

  JsonMap? riderActiveJob() => riderActiveJobId == null ? null : jobView(_job(riderActiveJobId!));

  JsonMap riderUpdateStatus(String jobId, JsonMap body) {
    final job = _job(jobId);
    final target = body['status'] as String;
    if (!_riderActions(job).contains(target)) fail(ErrorCodes.invalidStatusTransition, 'Not allowed now', status: 409);
    if (target == 'items_purchased' && (body['receipt_key'] == null || body['item_total_centavos'] == null)) {
      fail(ErrorCodes.validationFailed, 'Receipt required', fields: {'receipt_key': 'required'}, status: 422);
    }
    if (target == 'completed' && job['service'] != 'ride' && body['proof_key'] == null) {
      fail(ErrorCodes.validationFailed, 'Proof photo required', fields: {'proof_key': 'required'}, status: 422);
    }
    if (target == 'items_purchased') {
      job['pabili']
        ..['receipt_url'] = _urlForKey(body['receipt_key'] as String)
        ..['item_total_centavos'] = body['item_total_centavos'];
      _addItemsToFare(job, _int(body['item_total_centavos']));
      _after(5, () {
        if (job['status'] != 'items_purchased') return;
        _setStatus(job, 'picked_up'); // simulated customer approval
      });
    }
    if (target == 'completed') {
      if (body['proof_key'] != null) job['proof_url'] = _urlForKey(body['proof_key'] as String);
      job['payment']['status'] = 'paid';
      _settleRiderJob(job);
    }
    _setStatus(job, target);
    if (target == 'completed') {
      riderActiveJobId = null;
      _scheduleOffer(10);
    }
    return jobView(job);
  }

  void _settleRiderJob(JsonMap job) {
    final earn = _int(job['earnings_centavos'] ?? 5000);
    final commission = (earn * 0.2).round();
    var bal = _int(riderProfile['balance_centavos']);
    bal -= commission;
    riderProfile['balance_centavos'] = bal;
    final today = manilaDateString(DateTime.now());
    _sessionEarnings[today] = (_sessionEarnings[today] ?? 0) + earn;
    walletTxs.insert(0, {
      'id': _id(),
      'type': 'earning',
      'amount_centavos': earn,
      'balance_after_centavos': bal + commission,
      'job_id': job['id'],
      'note': 'Earning ${job['code']}',
      'created_at': _now(),
    });
    walletTxs.insert(0, {
      'id': _id(),
      'type': 'commission',
      'amount_centavos': -commission,
      'balance_after_centavos': bal,
      'job_id': job['id'],
      'note': 'Commission ${job['code']}',
      'created_at': _now(),
    });
  }

  (List<JsonMap>, String?) riderJobs(String? cursor) {
    final list = jobs.where((j) => j['rider']?['id'] == riderProfile['id'] && j['offer_only'] != true).map(jobView).toList();
    return _paginate(list, cursor, 20);
  }

  int _pseudo(String date, int base, int spread) => base + (date.hashCode.abs() % spread);

  JsonMap earnings(String from, String to) {
    final days = <JsonMap>[];
    var d = DateTime.parse(from);
    final end = DateTime.parse(to);
    final today = manilaDateString(DateTime.now());
    while (!d.isAfter(end)) {
      final ds = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final isFuture = ds.compareTo(today) > 0;
      final count = isFuture ? 0 : (ds == today ? 2 : _pseudo(ds, 2, 6));
      final total = isFuture ? 0 : count * _pseudo(ds, 4500, 2000) + (_sessionEarnings[ds] ?? 0);
      days.add({'date': ds, 'total_centavos': total, 'jobs_count': count});
      d = d.add(const Duration(days: 1));
    }
    return {
      'total_centavos': days.fold<int>(0, (s, e) => s + _int(e['total_centavos'])),
      'jobs_count': days.fold<int>(0, (s, e) => s + _int(e['jobs_count'])),
      'days': days,
    };
  }

  JsonMap wallet() => {'balance_centavos': riderProfile['balance_centavos'], 'min_balance_centavos': riderProfile['min_balance_centavos']};

  (List<JsonMap>, String?) transactions(String? cursor) => _paginate(walletTxs.map(copy).toList(), cursor, 20);

  JsonMap topup(int amount, String method, String key) {
    if (amount < 10000) fail(ErrorCodes.validationFailed, 'Minimum ₱100', fields: {'amount_centavos': 'min_10000'}, status: 422);
    final id = _idempotency[key] ?? _id();
    if (!_idempotency.containsKey(key)) {
      _idempotency[key] = id;
      _after(6, () {
        final bal = _int(riderProfile['balance_centavos']) + amount;
        riderProfile['balance_centavos'] = bal;
        walletTxs.insert(0, {
          'id': _id(),
          'type': 'topup',
          'amount_centavos': amount,
          'balance_after_centavos': bal,
          'note': '${method == 'gcash' ? 'GCash' : 'Maya'} top-up',
          'created_at': _now(),
        });
        emit('rider.profile_updated', {'profile': copy(riderProfile)});
      });
    }
    return {'topup_id': id, 'checkout_url': 'https://pay.example.com/mock-topup/$id'};
  }

  void riderLocation(JsonMap ping) {
    final id = riderActiveJobId;
    if (id != null) _job(id)['rider']?['location'] = ping['location'];
  }

  // =================== MERCHANT ===================
  JsonMap get _store => merchantAccount['merchant'] as JsonMap;
  JsonMap get _storeFull => merchants.firstWhere((m) => m['id'] == _store['id']);

  JsonMap merchantMe() {
    _requireAuth();
    if (_phone != null && _phone!.endsWith('0000')) fail(ErrorCodes.forbidden, 'Not a merchant', status: 403);
    return copy(merchantAccount);
  }

  JsonMap updateStore(JsonMap patch) {
    final wasAccepting = _store['is_open'] == true && !_paused(_store);
    for (final k in ['is_open', 'prep_time_minutes', 'min_order_centavos', 'hours', 'name']) {
      if (patch.containsKey(k)) {
        _store[k] = patch[k];
        _storeFull[k] = patch[k];
      }
    }
    if (patch.containsKey('paused_until')) {
      if (patch['paused_until'] == null) {
        _store.remove('paused_until');
        _storeFull.remove('paused_until');
      } else {
        _store['paused_until'] = patch['paused_until'];
        _storeFull['paused_until'] = patch['paused_until'];
      }
    }
    if (patch['logo_key'] != null) _store['logo_url'] = _storeFull['logo_url'] = _urlForKey(patch['logo_key'] as String);
    if (patch['cover_key'] != null) _store['cover_url'] = _storeFull['cover_url'] = _urlForKey(patch['cover_key'] as String);
    final accepting = _store['is_open'] == true && !_paused(_store);
    if (accepting && !wasAccepting) _scheduleNewOrder(8);
    return copy(_store);
  }

  void _scheduleNewOrder(num seconds) => _after(seconds, _makeOrder);

  void _makeOrder() {
    final accepting = _store['is_open'] == true && !_paused(_store);
    if (!accepting) {
      if (_store['is_open'] == true) _scheduleNewOrder(15); // paused: check again later
      return;
    }
    final menu = (_storeFull['menu'] as List).cast<JsonMap>();
    final items = [for (final c in menu) ...(c['items'] as List).cast<JsonMap>()].where((i) => i['is_available'] == true).toList();
    if (items.isEmpty) return _scheduleNewOrder(45);
    final picks = List.generate(1 + _rand.nextInt(3), (_) => items[_rand.nextInt(items.length)]);
    final lines = <JsonMap>[];
    for (final it in picks) {
      final qty = 1 + _rand.nextInt(2);
      final groups = (it['addon_groups'] as List).cast<JsonMap>();
      final addons = <String>[];
      var unit = _int(it['price_centavos']);
      for (final g in groups.where((g) => _int(g['min_select']) > 0 || _rand.nextBool())) {
        final opts = (g['options'] as List).cast<JsonMap>().where((o) => o['is_available'] == true).toList();
        if (opts.isEmpty) continue;
        final o = opts[_rand.nextInt(opts.length)];
        addons.add(o['name'] as String);
        unit += _int(o['price_centavos']);
      }
      lines.add({
        'name': it['name'],
        'quantity': qty,
        'addons': addons,
        if (_rand.nextInt(4) == 0) 'note': 'Less salt please',
        'line_total_centavos': unit * qty,
      });
    }
    final subtotal = lines.fold<int>(0, (s, l) => s + _int(l['line_total_centavos']));
    final commission = subtotal ~/ 10;
    final method = ['cash', 'gcash', 'maya', 'cash'][_rand.nextInt(4)];
    final names = ['Omar', 'Fatima', 'Rashid', 'Aisha', 'Nur', 'Hadji', 'Sitti', 'Jamil'];
    final order = <String, dynamic>{
      'id': _id(),
      'job_id': _id(),
      'code': _code(),
      'status': 'new',
      'created_at': _now(),
      'merchant_accept_deadline': toIsoUtc(DateTime.now().add(const Duration(minutes: 3))),
      'items': lines,
      'subtotal_centavos': subtotal,
      'commission_centavos': commission,
      'net_centavos': subtotal - commission,
      'payment_method': method,
      if (method == 'cash') 'rider_pays_at_pickup_centavos': subtotal - commission,
      'customer_first_name': names[_rand.nextInt(names.length)],
      if (_rand.nextInt(3) == 0) 'notes': 'Please include utensils',
      'allowed_actions': [OrderActions.accept, OrderActions.reject],
    };
    orders.insert(0, order);
    emit('order.new', {'order': copy(order)});
    _scheduleOrderDeadline(order['id'] as String);
    _scheduleNewOrder(45);
  }

  void _scheduleOrderDeadline(String id) {
    if (!simulate) return;
    final o = _order(id);
    final deadline = DateTime.parse(o['merchant_accept_deadline'] as String);
    late Timer t;
    t = Timer(deadline.difference(DateTime.now()) + const Duration(milliseconds: 200), () {
      _timers.remove(t);
      if (o['status'] != 'new') return;
      o['status'] = 'cancelled';
      o['allowed_actions'] = <String>[];
      emit('order.updated', {'order': copy(o)});
    });
    _timers.add(t);
  }

  JsonMap _order(String id) =>
      orders.firstWhere((o) => o['id'] == id, orElse: () => fail(ErrorCodes.notFound, 'Order not found', status: 404));

  (List<JsonMap>, String?) listOrders(String status, String? from, String? to, String? cursor) {
    bool inRange(JsonMap o) {
      final d = manilaDateString(DateTime.parse(o['created_at'] as String));
      return (from == null || d.compareTo(from) >= 0) && (to == null || d.compareTo(to) <= 0);
    }

    final match = switch (status) {
      'done' => (JsonMap o) => {'picked_up', 'completed', 'rejected', 'cancelled'}.contains(o['status']) && inRange(o),
      _ => (JsonMap o) => o['status'] == status,
    };
    return _paginate(orders.where(match).map(copy).toList(), cursor, 50);
  }

  JsonMap getOrder(String id) => copy(_order(id));

  void _publishOrder(JsonMap o) => emit('order.updated', {'order': copy(o)});

  JsonMap acceptOrder(String id, int prep) {
    final o = _order(id);
    if (o['status'] != 'new') fail(ErrorCodes.orderAlreadyHandled, 'Order already handled', status: 409);
    o
      ..['status'] = merchantOrderStatusFor(JobStatus.merchantPreparing, isReady: false).wire
      ..['prep_time_minutes'] = prep
      ..['allowed_actions'] = [OrderActions.ready]
      ..remove('merchant_accept_deadline');
    _after(8, () {
      if (!{'preparing', 'ready'}.contains(o['status'])) return;
      o['rider'] = {
        'name': 'Jamal H.',
        'photo_url': 'https://picsum.photos/seed/rider1/200',
        'plate': '123 ABC',
        'phone_masked': '+63 918 ••• 2222',
      };
      _publishOrder(o);
      if (o['status'] == 'ready') _simulatePickup(o);
    });
    return copy(o);
  }

  JsonMap rejectOrder(String id, String reason) {
    final o = _order(id);
    if (o['status'] != 'new') fail(ErrorCodes.orderAlreadyHandled, 'Order already handled', status: 409);
    o
      ..['status'] = merchantOrderStatusFor(JobStatus.cancelled, isReady: false, cancelledBy: PartyRole.merchant).wire
      ..['reject_reason'] = reason
      ..['commission_centavos'] = 0
      ..['net_centavos'] = 0
      ..['allowed_actions'] = <String>[]
      ..remove('rider_pays_at_pickup_centavos')
      ..remove('merchant_accept_deadline');
    return copy(o);
  }

  JsonMap markReady(String id) {
    final o = _order(id);
    if (!(o['allowed_actions'] as List).contains(OrderActions.ready)) {
      fail(ErrorCodes.invalidStatusTransition, 'Cannot mark ready', status: 409);
    }
    o
      ..['status'] = 'ready'
      ..['ready_at'] = _now()
      ..['allowed_actions'] = <String>[];
    if (o['rider'] != null) _simulatePickup(o);
    return copy(o);
  }

  void _simulatePickup(JsonMap o) {
    _after(6, () {
      if (o['status'] != 'ready') return;
      o['status'] = 'picked_up';
      _publishOrder(o);
      _after(15, () {
        o['status'] = 'completed';
        _publishOrder(o);
      });
    });
  }

  List<JsonMap> merchantMenu() => (_storeFull['menu'] as List).cast<JsonMap>().map(copy).toList();

  List<JsonMap> get _menu => (_storeFull['menu'] as List).cast<JsonMap>();

  JsonMap addCategory(String name) {
    final c = {'id': _id(), 'name': name, 'sort_order': _menu.length, 'items': <JsonMap>[]};
    (_storeFull['menu'] as List).add(c);
    return copy(c);
  }

  JsonMap _category(String id) =>
      _menu.firstWhere((c) => c['id'] == id, orElse: () => fail(ErrorCodes.notFound, 'Category not found', status: 404));

  JsonMap renameCategory(String id, String name) => copy(_category(id)..['name'] = name);

  void deleteCategory(String id) {
    final c = _category(id);
    if ((c['items'] as List).isNotEmpty) {
      fail(ErrorCodes.validationFailed, 'Category not empty', fields: {'category': 'not_empty'}, status: 422);
    }
    _menu.remove(c);
  }

  void reorderCategories(List<String> ids) {
    final menu = _menu;
    menu.sort((a, b) => ids.indexOf(a['id'] as String).compareTo(ids.indexOf(b['id'] as String)));
    for (var i = 0; i < menu.length; i++) {
      menu[i]['sort_order'] = i;
    }
  }

  (JsonMap, JsonMap) _itemWithCategory(String id) {
    for (final c in _menu) {
      for (final i in (c['items'] as List).cast<JsonMap>()) {
        if (i['id'] == id) return (c, i);
      }
    }
    fail(ErrorCodes.notFound, 'Item not found', status: 404);
  }

  JsonMap _applyItemInput(JsonMap input, {String? id, JsonMap? existing}) {
    final groups = [
      for (final g in (input['addon_groups'] as List).cast<JsonMap>())
        {
          'id': g['id'] ?? _id(),
          'name': g['name'],
          'min_select': g['min_select'],
          'max_select': g['max_select'],
          'options': [
            for (final o in (g['options'] as List).cast<JsonMap>())
              {'id': o['id'] ?? _id(), 'name': o['name'], 'price_centavos': o['price_centavos'], 'is_available': o['is_available']},
          ],
        },
    ];
    final photo = input['photo_key'] != null ? _urlForKey(input['photo_key'] as String) : existing?['photo_url'];
    return {
      'id': id ?? _id(),
      'category_id': input['category_id'],
      'name': input['name'],
      if (input['description'] != null) 'description': input['description'],
      'photo_url': ?photo,
      'price_centavos': input['price_centavos'],
      'is_available': input['is_available'],
      'addon_groups': groups,
    };
  }

  JsonMap createItem(JsonMap input) {
    final c = _category(input['category_id'] as String);
    final item = _applyItemInput(input);
    (c['items'] as List).add(item);
    return copy(item);
  }

  JsonMap updateItem(String id, JsonMap input) {
    final (cat, existing) = _itemWithCategory(id);
    final item = _applyItemInput(input, id: id, existing: existing);
    final list = cat['items'] as List;
    if (cat['id'] == input['category_id']) {
      list[list.indexOf(existing)] = item;
    } else {
      list.remove(existing);
      (_category(input['category_id'] as String)['items'] as List).add(item);
    }
    return copy(item);
  }

  void deleteItem(String id) {
    final (cat, item) = _itemWithCategory(id);
    (cat['items'] as List).remove(item);
  }

  JsonMap setItemAvailability(String id, bool available) {
    final (_, item) = _itemWithCategory(id);
    item['is_available'] = available;
    return copy(item);
  }

  void setOptionAvailability(String id, bool available) {
    for (final c in _menu) {
      for (final i in (c['items'] as List).cast<JsonMap>()) {
        for (final g in (i['addon_groups'] as List).cast<JsonMap>()) {
          for (final o in (g['options'] as List).cast<JsonMap>()) {
            if (o['id'] == id) {
              o['is_available'] = available;
              return;
            }
          }
        }
      }
    }
    fail(ErrorCodes.notFound, 'Option not found', status: 404);
  }

  JsonMap sales(String from, String to) {
    final example = {for (final d in (_salesExample['days'] as List).cast<JsonMap>()) d['date']: d};
    final days = <JsonMap>[];
    var d = DateTime.parse(from);
    final end = DateTime.parse(to);
    final today = manilaDateString(DateTime.now());
    while (!d.isAfter(end)) {
      final ds = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (ds.compareTo(today) > 0) break;
      final ex = example[ds];
      final session = orders.where((o) => o['status'] == 'completed' && manilaDateString(DateTime.parse(o['created_at'] as String)) == ds);
      final count = (ex != null ? _int(ex['orders_count']) : _pseudo(ds, 5, 8)) + session.length;
      final gross =
          (ex != null ? _int(ex['gross_centavos']) : count * _pseudo(ds, 12000, 8000)) +
          session.fold<int>(0, (s, o) => s + _int(o['subtotal_centavos']));
      days.add({'date': ds, 'orders_count': count, 'gross_centavos': gross, 'net_centavos': gross - gross ~/ 10});
      d = d.add(const Duration(days: 1));
    }
    final gross = days.fold<int>(0, (s, e) => s + _int(e['gross_centavos']));
    final net = days.fold<int>(0, (s, e) => s + _int(e['net_centavos']));
    return {
      'from': from,
      'to': to,
      'orders_count': days.fold<int>(0, (s, e) => s + _int(e['orders_count'])),
      'gross_centavos': gross,
      'commission_centavos': gross - net,
      'net_centavos': net,
      'days': days,
    };
  }

  (List<JsonMap>, String?) listPayouts(String? cursor) => _paginate(payouts.map(copy).toList(), cursor, 20);
}
