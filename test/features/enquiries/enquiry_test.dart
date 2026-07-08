import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';

void main() {
  final row = {
    'id': 'e1',
    'customer_id': 'c1',
    'product_id': 'p1',
    'source': 'paste',
    'message': 'Want the red saree',
    'intent': 'inquiry',
    'status': 'follow',
    'follow_up_date': '2026-07-10T00:00:00.000Z',
    'created_at': '2026-07-08T10:00:00.000Z',
    'customers': {'name': 'Priya', 'phone': '9876543210'},
    'products': {
      'name': 'Red Banarasi',
      'images': ['u1/a.jpg'],
      'price': 5500,
      'is_unique': true,
      'piece_status': 'available',
    },
  };

  test('fromMap flattens customer and product joins', () {
    final e = Enquiry.fromMap(row);
    expect(e.id, 'e1');
    expect(e.customerName, 'Priya');
    expect(e.customerPhone, '9876543210');
    expect(e.productName, 'Red Banarasi');
    expect(e.productImage, 'u1/a.jpg');
    expect(e.productPrice, 5500);
    expect(e.productIsUnique, isTrue);
    expect(e.followUpDate, DateTime.utc(2026, 7, 10));
  });

  test('fromMap tolerates missing joins', () {
    final e = Enquiry.fromMap({'id': 'e2', 'status': 'new'});
    expect(e.customerName, isNull);
    expect(e.productName, isNull);
    expect(e.status, 'new');
  });

  test('bucket assigns overdue/today/upcoming/new', () {
    final now = DateTime(2026, 7, 8, 12);
    Enquiry withFollow(DateTime? d, String status) => Enquiry.fromMap({
          'id': 'x',
          'status': status,
          'follow_up_date': d?.toIso8601String(),
        });
    expect(withFollow(DateTime(2026, 7, 7), 'follow').bucket(now),
        EnquiryBucket.overdue);
    expect(withFollow(DateTime(2026, 7, 8, 18), 'follow').bucket(now),
        EnquiryBucket.today);
    expect(withFollow(DateTime(2026, 7, 9), 'follow').bucket(now),
        EnquiryBucket.upcoming);
    expect(withFollow(null, 'new').bucket(now), EnquiryBucket.fresh);
  });

  test('fromMap reads screenshot_url', () {
    final e = Enquiry.fromMap({
      'id': 'e1',
      'screenshot_url': 'uid/123.jpg',
    });
    expect(e.screenshotUrl, 'uid/123.jpg');
  });
}
