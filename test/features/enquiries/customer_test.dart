import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/customer.dart';

void main() {
  test('fromMap parses a row', () {
    final c = Customer.fromMap({
      'id': 'c1',
      'name': 'Priya',
      'phone': '9876543210',
      'tags': ['vip'],
    });
    expect(c.id, 'c1');
    expect(c.name, 'Priya');
    expect(c.phone, '9876543210');
    expect(c.tags, ['vip']);
  });

  test('fromMap tolerates null phone and missing tags', () {
    final c = Customer.fromMap({'id': 'c2', 'name': 'Walk-in'});
    expect(c.phone, isNull);
    expect(c.tags, isEmpty);
  });

  test('toMap omits nulls and never includes id/user_id', () {
    const c = Customer(name: 'Priya', phone: '9876543210');
    final map = c.toMap();
    expect(map, {'name': 'Priya', 'phone': '9876543210'});
  });
}
