import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';

void main() {
  test('leads keep legacy keys; won leads are skipped', () {
    final maps = buildLegacyMaps(
      leads: [
        {
          'id': 'l1',
          'status': 'follow',
          'message': 'wants saree',
          'created_at': '2026-07-08T10:00:00Z',
          'customers': {'name': 'Priya'},
        },
        {'id': 'l2', 'status': 'won', 'created_at': '2026-07-08T09:00:00Z'},
      ],
      orders: [],
    );
    expect(maps, hasLength(1));
    expect(maps.first['name'], 'Priya');
    expect(maps.first['msg'], 'wants saree');
  });

  test('orders become status closed with legacy item keys', () {
    final maps = buildLegacyMaps(leads: [], orders: [
      {
        'id': 'o1',
        'status': 'confirmed',
        'created_at': '2026-07-08T10:00:00Z',
        'customers': {'name': 'Anita'},
        'order_items': [
          {'name': 'Kurti', 'qty': 2, 'unit_price': 500, 'line_total': 1000},
        ],
      }
    ]);
    expect(maps.single['status'], 'closed');
    expect(maps.single['order_status'], 'confirmed');
    expect(maps.single['items'], [
      {'product_name': 'Kurti', 'quantity': 2, 'price': 500, 'total': 1000},
    ]);
  });
}
