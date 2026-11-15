"""Generates assets/mock/*.json contract fixtures. Run: python tool/gen_fixtures.py"""
import json, os, uuid

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'mock')
NS = uuid.UUID('6b1f8c1e-0000-4000-8000-00000000b0b0')
def uid(name): return str(uuid.uuid5(NS, name))
def ll(lat, lng): return {'lat': lat, 'lng': lng}
def hours(o='07:00', c='21:00', closed=()):
    return [{'weekday': d, 'opens': o, 'closes': c} for d in range(7) if d not in closed]

def opt(mid, name, price, avail=True): return {'id': uid(mid + name), 'name': name, 'price_centavos': price, 'is_available': avail}
def grp(mid, name, mn, mx, opts): return {'id': uid(mid + 'g' + name), 'name': name, 'min_select': mn, 'max_select': mx, 'options': opts}
def item(mid, cid, name, price, desc=None, groups=(), avail=True):
    d = {'id': uid(mid + 'i' + name), 'category_id': cid, 'name': name, 'price_centavos': price, 'is_available': avail, 'addon_groups': list(groups)}
    if desc: d['description'] = desc
    return d

def menu(mid, cats):
    out = []
    for i, (cname, items) in enumerate(cats):
        cid = uid(mid + 'c' + cname)
        out.append({'id': cid, 'name': cname, 'sort_order': i, 'items': [f(cid) for f in items]})
    return out

M = []
def merchant(key, name, addr, loc, prep, rating, min_order, is_open, cats, dist, h=None):
    mid = uid('merchant-' + key)
    m = {'id': mid, 'name': name, 'logo_url': f'https://picsum.photos/seed/{key}-logo/200', 'cover_url': f'https://picsum.photos/seed/{key}-cover/800/400',
         'address': addr, 'location': loc, 'is_open': is_open, 'hours': h or hours(), 'prep_time_minutes': prep, 'rating': rating,
         'min_order_centavos': min_order, 'distance_m': dist}
    m['menu'] = menu(mid, cats(mid))
    M.append(m)

rice = lambda m: grp(m, 'Rice', 0, 1, [opt(m, 'Plain rice', 2000), opt(m, 'Garlic rice', 3000), opt(m, 'Java rice', 3000, False)])
drink = lambda m: grp(m, 'Drink', 0, 1, [opt(m, 'Iced tea', 3500), opt(m, 'Calamansi juice', 4000), opt(m, 'Bottled water', 2000)])
spice = lambda m: grp(m, 'Spice level', 1, 1, [opt(m, 'Mild', 0), opt(m, 'Spicy', 0), opt(m, 'Extra spicy', 1000)])

merchant('kusina', 'Kusina Bongao', 'Datu Halun St., Poblacion, Bongao', ll(5.0291, 119.7712), 20, 4.7, 10000, True, lambda m: [
    ('Rice meals', [
        lambda c: item(m, c, 'Chicken adobo', 9500, 'Braised chicken in soy and vinegar, with rice.', [rice(m), drink(m)]),
        lambda c: item(m, c, 'Beef kaldereta', 13000, 'Beef stew in tomato sauce with potatoes.', [rice(m), drink(m)]),
        lambda c: item(m, c, 'Fried bangus', 11000, 'Crispy marinated milkfish.', [rice(m)]),
        lambda c: item(m, c, 'Chicken curry', 10500, None, [rice(m), spice(m)], avail=False),
    ]),
    ('Soups', [
        lambda c: item(m, c, 'Sinigang na isda', 14000, 'Sour tamarind fish soup, good for 2.'),
        lambda c: item(m, c, 'Tinola', 12000, 'Chicken ginger soup with papaya.'),
    ]),
    ('Drinks', [
        lambda c: item(m, c, 'Iced tea (large)', 4500),
        lambda c: item(m, c, 'Buko juice', 5000, 'Fresh young coconut.'),
    ]),
], 350)

merchant('pantay', 'Pantay Grill & Seafood', 'Pantay Bay Rd., Bongao', ll(5.0312, 119.7745), 30, 4.5, 15000, True, lambda m: [
    ('Grill', [
        lambda c: item(m, c, 'Grilled tuna panga', 22000, 'Tuna jaw, char-grilled.', [rice(m), grp(m, 'Sauce', 0, 2, [opt(m, 'Soy-calamansi', 0), opt(m, 'Spicy vinegar', 0), opt(m, 'Garlic butter', 2500)])]),
        lambda c: item(m, c, 'Chicken inasal', 12500, None, [rice(m), drink(m)]),
        lambda c: item(m, c, 'Grilled squid', 18000, 'Stuffed with tomato and onion.', [rice(m)]),
    ]),
    ('Seafood', [
        lambda c: item(m, c, 'Shrimp in garlic butter', 24000, None, [rice(m)]),
        lambda c: item(m, c, 'Kinilaw na tuna', 16000, 'Fresh tuna ceviche with coconut vinegar.', [spice(m)]),
        lambda c: item(m, c, 'Seaweed salad (lato)', 6000),
    ]),
], 520)

merchant('sitti', 'Sitti Bakeshop', 'Lamion, Bongao', ll(5.0277, 119.7758), 10, 4.8, 5000, True, lambda m: [
    ('Breads', [
        lambda c: item(m, c, 'Pandesal (10 pcs)', 3000),
        lambda c: item(m, c, 'Ube cheese pandesal (6 pcs)', 9000),
        lambda c: item(m, c, 'Spanish bread (6 pcs)', 6000),
    ]),
    ('Local snacks', [
        lambda c: item(m, c, 'Panyalam', 2500, 'Tausug rice-flour pancake.'),
        lambda c: item(m, c, 'Daral', 3000, 'Crepe rolled with sweet coconut.'),
        lambda c: item(m, c, 'Tiyulah itum', 15000, 'Traditional black beef soup.', [rice(m)]),
    ]),
    ('Coffee', [
        lambda c: item(m, c, 'Kahawa sug', 4000, 'Native brewed coffee.', [grp(m, 'Sweetness', 1, 1, [opt(m, 'Black', 0), opt(m, 'Regular', 0), opt(m, 'Extra sweet', 0)])]),
    ]),
], 480)

merchant('tiula', 'Tiula Halo-Halo & Snacks', 'Tubig Tanah, Bongao', ll(5.0305, 119.7701), 15, 4.4, 8000, True, lambda m: [
    ('Halo-halo', [
        lambda c: item(m, c, 'Halo-halo special', 12000, 'Shaved ice, milk, ube, leche flan.', [grp(m, 'Extras', 0, 3, [opt(m, 'Extra leche flan', 2000), opt(m, 'Extra ube', 1500), opt(m, 'Ice cream scoop', 2500, False)])]),
        lambda c: item(m, c, 'Mais con yelo', 7000),
    ]),
    ('Snacks', [
        lambda c: item(m, c, 'Chicken lumpia (6 pcs)', 8000),
        lambda c: item(m, c, 'Banana cue (3 sticks)', 4500),
        lambda c: item(m, c, 'Turon (3 pcs)', 4500),
    ]),
], 610)

merchant('budcoffee', 'Bud Bongao Coffee', 'Pasiagan, Bongao', ll(5.0268, 119.7724), 10, 4.9, 5000, False, lambda m: [
    ('Coffee', [
        lambda c: item(m, c, 'Iced latte', 11000, None, [grp(m, 'Milk', 1, 1, [opt(m, 'Fresh milk', 0), opt(m, 'Oat milk', 2500)]), grp(m, 'Size', 1, 1, [opt(m, '12 oz', 0), opt(m, '16 oz', 2000)])]),
        lambda c: item(m, c, 'Americano', 8000, None, [grp(m, 'Size', 1, 1, [opt(m, '12 oz', 0), opt(m, '16 oz', 2000)])]),
    ]),
    ('Pastries', [
        lambda c: item(m, c, 'Banana bread', 6500),
        lambda c: item(m, c, 'Cheese roll', 4500),
    ]),
], 300, hours('08:00', '18:00', closed=(5,)))

def dump(name, data):
    with open(os.path.join(OUT, name), 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')

dump('merchants.json', M)

customer = {'id': uid('user-customer'), 'phone': '+639171234567', 'name': 'Aisha Tan', 'language': 'en', 'roles': ['customer'], 'created_at': '2026-06-01T02:00:00Z'}
rider_user = {'id': uid('user-rider'), 'phone': '+639181112222', 'name': 'Jamal Hassan', 'language': 'fil', 'roles': ['customer', 'rider'], 'created_at': '2026-05-10T02:00:00Z'}
merchant_user = {'id': uid('user-merchant'), 'phone': '+639193334444', 'name': 'Mering Abdulla', 'language': 'en', 'roles': ['customer', 'merchant'], 'created_at': '2026-04-02T02:00:00Z'}
dump('users.json', {'customer': customer, 'rider': rider_user, 'merchant': merchant_user})

dump('saved_places.json', [
    {'id': uid('place-home'), 'label': 'Home', 'address': 'Lamion, near Barangay Hall, Bongao', 'location': ll(5.0251, 119.7769)},
    {'id': uid('place-work'), 'label': 'Work', 'address': 'Provincial Capitol, Bongao', 'location': ll(5.0362, 119.7795)},
])

dump('geo_places.json', [
    {'name': 'Bongao Public Market', 'address': 'Poblacion, Bongao', 'location': ll(5.0296, 119.7727)},
    {'name': 'Tawi-Tawi Provincial Capitol', 'address': 'Capitol Hill, Bongao', 'location': ll(5.0362, 119.7795)},
    {'name': 'MSU Tawi-Tawi', 'address': 'Sanga-Sanga, Bongao', 'location': ll(5.0467, 119.7484)},
    {'name': 'Bongao Port', 'address': 'Port Area, Bongao', 'location': ll(5.0288, 119.7741)},
    {'name': 'Sanga-Sanga Airport', 'address': 'Sanga-Sanga, Bongao', 'location': ll(5.0466, 119.7426)},
    {'name': 'Bud Bongao Trailhead', 'address': 'Pasiagan, Bongao', 'location': ll(5.0252, 119.7655)},
    {'name': 'Tawi-Tawi Provincial Hospital', 'address': 'Tubig Boh, Bongao', 'location': ll(5.0327, 119.7767)},
    {'name': 'Bongao Municipal Hall', 'address': 'Poblacion, Bongao', 'location': ll(5.0302, 119.7735)},
])

dump('service_area.json', {'zones': [{'id': uid('zone-bongao'), 'name': 'Bongao mainland', 'polygon': [
    ll(5.0700, 119.7350), ll(5.0700, 119.8050), ll(4.9950, 119.8050), ll(4.9950, 119.7350)]}]})

rider_info = {'id': uid('rider-1'), 'name': 'Jamal H.', 'photo_url': 'https://picsum.photos/seed/rider1/200', 'phone_masked': '+63 918 ••• 2222',
              'plate': '123 ABC', 'make_model': 'Honda Click 125i', 'color': 'Red', 'rating': 4.9}
def fare(lines):
    return {'breakdown': [{'label': l, 'amount_centavos': a} for l, a in lines], 'total_centavos': sum(a for _, a in lines)}
def tl(*pairs): return [{'status': s, 'at': t} for s, t in pairs]

home = {'address': 'Lamion, near Barangay Hall, Bongao', 'location': ll(5.0251, 119.7769)}
market = {'address': 'Bongao Public Market', 'location': ll(5.0296, 119.7727)}
capitol = {'address': 'Provincial Capitol, Bongao', 'location': ll(5.0362, 119.7795)}
k = M[0]
jobs = [
    {'id': uid('job-ride-1'), 'code': 'GO-4821', 'service': 'ride', 'status': 'completed', 'created_at': '2026-11-13T00:10:00Z', 'updated_at': '2026-11-13T00:31:00Z',
     'pickup': home, 'dropoff': capitol, 'rider': rider_info, 'fare': fare([('Base fare', 4000), ('Distance 1.6 km', 2400)]),
     'payment': {'method': 'cash', 'status': 'paid'}, 'allowed_actions': ['rate'],
     'timeline': tl(('searching', '2026-11-13T00:10:00Z'), ('rider_assigned', '2026-11-13T00:11:00Z'), ('arrived_pickup', '2026-11-13T00:16:00Z'),
                    ('picked_up', '2026-11-13T00:18:00Z'), ('arrived_dropoff', '2026-11-13T00:30:00Z'), ('completed', '2026-11-13T00:31:00Z'))},
    {'id': uid('job-food-1'), 'code': 'GO-4790', 'service': 'food', 'status': 'completed', 'created_at': '2026-11-12T04:00:00Z', 'updated_at': '2026-11-12T04:52:00Z',
     'pickup': {'address': k['address'], 'location': k['location'], 'contact_name': k['name']}, 'dropoff': home, 'rider': rider_info,
     'merchant': {'id': k['id'], 'name': k['name'], 'phone_masked': '+63 917 ••• 8890'},
     'food': {'items': [{'name': 'Chicken adobo', 'quantity': 2, 'addons': ['Garlic rice'], 'line_total_centavos': 25000},
                        {'name': 'Buko juice', 'quantity': 1, 'addons': [], 'note': 'Less ice', 'line_total_centavos': 5000}],
              'subtotal_centavos': 30000, 'prep_time_minutes': 20, 'ready_at': '2026-11-12T04:25:00Z', 'is_ready': True},
     'fare': fare([('Food subtotal', 30000), ('Delivery fee', 4900), ('Service fee', 1000)]),
     'payment': {'method': 'gcash', 'status': 'paid'}, 'proof_url': 'https://picsum.photos/seed/pod1/600/800', 'allowed_actions': [],
     'timeline': tl(('pending_payment', '2026-11-12T04:00:00Z'), ('merchant_pending', '2026-11-12T04:01:00Z'), ('merchant_preparing', '2026-11-12T04:03:00Z'),
                    ('searching', '2026-11-12T04:15:00Z'), ('rider_assigned', '2026-11-12T04:16:00Z'), ('arrived_pickup', '2026-11-12T04:24:00Z'),
                    ('picked_up', '2026-11-12T04:30:00Z'), ('arrived_dropoff', '2026-11-12T04:50:00Z'), ('completed', '2026-11-12T04:52:00Z'))},
    {'id': uid('job-pabili-1'), 'code': 'GO-4755', 'service': 'pabili', 'status': 'completed', 'created_at': '2026-11-10T07:00:00Z', 'updated_at': '2026-11-10T07:55:00Z',
     'pickup': market, 'dropoff': home, 'rider': rider_info,
     'pabili': {'store_name': 'Bongao Public Market', 'items': [{'name': 'Tomatoes', 'quantity': 1, 'note': '1 kilo'}, {'name': 'Eggs', 'quantity': 12}],
                'receipt_url': 'https://picsum.photos/seed/receipt1/600/800', 'item_total_centavos': 21500},
     'fare': fare([('Pabili fee', 6000), ('Items (receipt)', 21500)]), 'payment': {'method': 'cash', 'status': 'paid'},
     'proof_url': 'https://picsum.photos/seed/pod2/600/800', 'allowed_actions': [],
     'timeline': tl(('searching', '2026-11-10T07:00:00Z'), ('rider_assigned', '2026-11-10T07:02:00Z'), ('arrived_pickup', '2026-11-10T07:12:00Z'),
                    ('items_purchased', '2026-11-10T07:35:00Z'), ('picked_up', '2026-11-10T07:37:00Z'), ('arrived_dropoff', '2026-11-10T07:53:00Z'), ('completed', '2026-11-10T07:55:00Z'))},
    {'id': uid('job-padala-1'), 'code': 'GO-4702', 'service': 'padala', 'status': 'cancelled', 'created_at': '2026-11-08T09:00:00Z', 'updated_at': '2026-11-08T09:05:00Z',
     'pickup': home, 'dropoff': {'address': 'MSU Tawi-Tawi, Sanga-Sanga', 'location': ll(5.0467, 119.7484), 'contact_name': 'Nur Ali', 'contact_phone': '+639201234567'},
     'padala': {'size': 'small', 'description': 'Documents in an envelope', 'recipient_name': 'Nur Ali', 'recipient_phone': '+639201234567'},
     'fare': fare([('Base fare', 5000), ('Distance 4.1 km', 6200)]), 'payment': {'method': 'cash', 'status': 'pending'},
     'cancel_reason': 'Changed my mind', 'cancelled_by': 'customer', 'allowed_actions': [],
     'timeline': tl(('searching', '2026-11-08T09:00:00Z'), ('cancelled', '2026-11-08T09:05:00Z'))},
]
dump('jobs.json', jobs)

dump('quote.json', {'id': uid('quote-1'), 'service': 'ride', 'distance_m': 1600, 'duration_s': 420, 'expires_at': '2026-11-14T14:10:00Z',
                    'breakdown': [{'label': 'Base fare', 'amount_centavos': 4000}, {'label': 'Distance 1.6 km', 'amount_centavos': 2400}], 'total_centavos': 6400})
dump('quote_request.json', {'service': 'food', 'pickup': {'address': k['address'], 'location': k['location']}, 'dropoff': home,
     'food': {'merchant_id': k['id'], 'items': [{'item_id': k['menu'][0]['items'][0]['id'], 'quantity': 2,
              'addon_option_ids': [k['menu'][0]['items'][0]['addon_groups'][0]['options'][1]['id']], 'note': 'No onions'}]}})

offer_job = json.loads(json.dumps(jobs[0]))
offer_job.update({'id': uid('job-offer-1'), 'code': 'GO-4830', 'status': 'searching', 'created_at': '2026-11-14T14:00:00Z', 'updated_at': '2026-11-14T14:00:00Z',
                  'payment': {'method': 'cash', 'status': 'pending'}, 'allowed_actions': [], 'timeline': tl(('searching', '2026-11-14T14:00:00Z'))})
del offer_job['rider']
dump('job_offer.json', {'id': uid('offer-1'), 'job': offer_job, 'earnings_centavos': 5100, 'pickup_distance_m': 800, 'expires_at': '2026-11-14T14:00:15Z'})

dump('rider_profile.json', {'id': uid('rider-1'), 'user_id': rider_user['id'], 'status': 'approved', 'is_online': False,
     'vehicle': {'plate': '123 ABC', 'make_model': 'Honda Click 125i', 'color': 'Red'}, 'rating': 4.9, 'balance_centavos': 35000, 'min_balance_centavos': 10000})

txs, bal = [], 35000
entries = [('commission', -1300, uid('job-ride-1'), 'Commission GO-4821', '2026-11-13T00:31:00Z'), ('earning', 6400, uid('job-ride-1'), 'Cash fare GO-4821', '2026-11-13T00:31:00Z'),
           ('commission', -1200, uid('job-food-1'), 'Commission GO-4790', '2026-11-12T04:52:00Z'), ('topup', 20000, None, 'GCash top-up', '2026-11-11T01:00:00Z'),
           ('adjustment', 500, None, 'Weather bonus', '2026-11-09T10:00:00Z')]
for i, (t, amt, jid, note, at) in enumerate(entries):
    tx = {'id': uid(f'tx-{i}'), 'type': t, 'amount_centavos': amt, 'balance_after_centavos': bal, 'note': note, 'created_at': at}
    if jid: tx['job_id'] = jid
    if t == 'earning':
        tx['balance_after_centavos'] = bal  # cash earnings do not change the commission wallet
    txs.append(tx)
    if t != 'earning': bal -= amt
dump('wallet_transactions.json', txs)

dump('rider_earnings.json', {'total_centavos': 52300, 'jobs_count': 9, 'days': [
    {'date': '2026-11-12', 'total_centavos': 18100, 'jobs_count': 3}, {'date': '2026-11-13', 'total_centavos': 21400, 'jobs_count': 4}, {'date': '2026-11-14', 'total_centavos': 12800, 'jobs_count': 2}]})

macct = {'merchant': {kk: v for kk, v in k.items() if kk not in ('menu', 'distance_m')}, 'role': 'owner', 'staff_name': 'Mering'}
dump('merchant_account.json', macct)

orders = [
    {'id': uid('order-1'), 'job_id': uid('job-food-1'), 'code': 'GO-4790', 'status': 'completed', 'created_at': '2026-11-12T04:01:00Z', 'prep_time_minutes': 20,
     'ready_at': '2026-11-12T04:25:00Z', 'items': jobs[1]['food']['items'], 'subtotal_centavos': 30000, 'commission_centavos': 3000, 'net_centavos': 27000,
     'payment_method': 'gcash', 'rider': {'name': 'Jamal H.', 'photo_url': 'https://picsum.photos/seed/rider1/200', 'plate': '123 ABC', 'phone_masked': '+63 918 ••• 2222'},
     'customer_first_name': 'Aisha', 'allowed_actions': []},
    {'id': uid('order-2'), 'job_id': uid('job-food-2'), 'code': 'GO-4831', 'status': 'new', 'created_at': '2026-11-14T14:00:00Z', 'merchant_accept_deadline': '2026-11-14T14:03:00Z',
     'items': [{'name': 'Beef kaldereta', 'quantity': 1, 'addons': ['Plain rice', 'Iced tea'], 'line_total_centavos': 18500}],
     'subtotal_centavos': 18500, 'commission_centavos': 1850, 'net_centavos': 16650, 'payment_method': 'cash', 'rider_pays_at_pickup_centavos': 16650,
     'customer_first_name': 'Omar', 'notes': 'Please add extra sauce', 'allowed_actions': ['accept', 'reject']},
    {'id': uid('order-3'), 'job_id': uid('job-food-3'), 'code': 'GO-4777', 'status': 'rejected', 'created_at': '2026-11-11T11:00:00Z',
     'items': [{'name': 'Chicken curry', 'quantity': 1, 'addons': ['Spicy'], 'line_total_centavos': 10500}], 'subtotal_centavos': 10500, 'commission_centavos': 0,
     'net_centavos': 0, 'payment_method': 'maya', 'customer_first_name': 'Fatima', 'reject_reason': 'out_of_stock', 'allowed_actions': []},
]
dump('merchant_orders.json', orders)

dump('sales_report.json', {'from': '2026-11-08', 'to': '2026-11-14', 'orders_count': 61, 'gross_centavos': 1043500, 'commission_centavos': 104350, 'net_centavos': 939150,
     'days': [{'date': f'2026-11-{d:02d}', 'orders_count': n, 'gross_centavos': g, 'net_centavos': g - g // 10} for d, n, g in
              [(8, 7, 118000), (9, 10, 171500), (10, 8, 140000), (11, 9, 152000), (12, 11, 189000), (13, 9, 160500), (14, 7, 112500)]]})

dump('payouts.json', [
    {'id': uid('payout-1'), 'period_from': '2026-11-02', 'period_to': '2026-11-08', 'amount_centavos': 412500, 'type': 'payout', 'status': 'paid', 'paid_at': '2026-11-10T03:00:00Z'},
    {'id': uid('payout-2'), 'period_from': '2026-11-02', 'period_to': '2026-11-08', 'amount_centavos': 38200, 'type': 'commission_invoice', 'status': 'pending'},
    {'id': uid('payout-3'), 'period_from': '2026-10-26', 'period_to': '2026-11-01', 'amount_centavos': 29900, 'type': 'commission_invoice', 'status': 'overdue'},
    {'id': uid('payout-4'), 'period_from': '2026-11-09', 'period_to': '2026-11-15', 'amount_centavos': 0, 'type': 'payout', 'status': 'pending'},
])

dump('chat_messages.json', [
    {'id': uid('msg-1'), 'job_id': uid('job-ride-1'), 'sender': 'system', 'text': 'Rider Jamal H. is on the way.', 'created_at': '2026-11-13T00:11:00Z'},
    {'id': uid('msg-2'), 'job_id': uid('job-ride-1'), 'sender': 'rider', 'text': 'Nasa gate na po ako.', 'created_at': '2026-11-13T00:16:00Z'},
    {'id': uid('msg-3'), 'job_id': uid('job-ride-1'), 'sender': 'customer', 'text': 'Okay, palabas na po.', 'created_at': '2026-11-13T00:16:30Z'},
    {'id': uid('msg-4'), 'job_id': uid('job-ride-1'), 'sender': 'customer', 'image_url': 'https://picsum.photos/seed/chat1/400', 'created_at': '2026-11-13T00:17:00Z'},
])
dump('upload_ticket.json', {'upload_url': 'https://storage.example.com/uploads/abc?X-Signature=...', 'key': 'uploads/2026/11/14/abc.jpg', 'expires_at': '2026-11-14T14:15:00Z'})
dump('auth_result.json', {'access_token': 'eyJ.mock.access', 'refresh_token': 'mock-refresh', 'user': customer, 'is_new_user': False})
print('ok', len(os.listdir(OUT)))
