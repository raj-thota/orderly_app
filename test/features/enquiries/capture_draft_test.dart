import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';

void main() {
  test('extracts 10-digit phone with optional +91', () {
    expect(CaptureDraft.fromText('call me on +91 98765 43210').phone,
        '9876543210');
    expect(CaptureDraft.fromText('number 9876543210').phone, '9876543210');
    expect(CaptureDraft.fromText('order 12345').phone, isNull);
  });

  test('extracts name from self-introduction patterns', () {
    expect(CaptureDraft.fromText('Hi this is Priya, want 2 sarees').name,
        'Priya');
    expect(CaptureDraft.fromText("I'm Anita from Pune").name, 'Anita');
    expect(CaptureDraft.fromText('Priya: want the red one').name, 'Priya');
  });

  test('extracts qty + item pairs and rupee prices', () {
    final d = CaptureDraft.fromText('want 2 kurtis at ₹1,500 and 1 saree');
    expect(d.items, hasLength(2));
    expect(d.items.first.name, 'kurtis');
    expect(d.items.first.qty, 2);
    expect(d.items.first.price, 1500);
    expect(d.items.last.name, 'saree');
    expect(d.items.last.qty, 1);
  });

  test('detects order type and follow-up intent with dates', () {
    expect(CaptureDraft.fromText('please confirm my order').type, 'order');
    final d = CaptureDraft.fromText('will confirm tomorrow');
    expect(d.type, 'enquiry');
    expect(d.intent, 'follow_up');
    expect(d.followUpDate, isNotNull);
  });

  test('empty text yields empty draft', () {
    final d = CaptureDraft.fromText('   ');
    expect(d.isEmpty, isTrue);
  });

  test('parses phone from a 12-digit 91-prefixed run', () {
    expect(
      CaptureDraft.fromText('Contact 919876543210').phone,
      '9876543210',
    );
  });

  test('ignores digit runs longer than a phone number', () {
    expect(CaptureDraft.fromText('order #98765432101234').phone, isNull);
  });

  test('normalizePhone strips formatting, country code and trunk zero', () {
    expect(CaptureDraft.normalizePhone('+91 98765 43210'), '9876543210');
    expect(CaptureDraft.normalizePhone('09876543210'), '9876543210');
    expect(CaptureDraft.normalizePhone('abc'), isNull);
  });
}
