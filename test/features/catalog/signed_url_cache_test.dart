import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/catalog/data/signed_url_cache.dart';

void main() {
  group('SignedUrlCache', () {
    test('returns null on miss', () {
      final cache = SignedUrlCache();
      expect(cache.get('u/a.jpg'), isNull);
    });

    test('returns stored url before expiry', () {
      var now = DateTime(2026, 1, 1, 12, 0);
      final cache = SignedUrlCache(
        ttl: const Duration(hours: 1),
        clock: () => now,
      );
      cache.put('u/a.jpg', 'https://signed/a');
      now = DateTime(2026, 1, 1, 12, 50);
      expect(cache.get('u/a.jpg'), 'https://signed/a');
    });

    test('drops urls within the refresh margin of expiry', () {
      var now = DateTime(2026, 1, 1, 12, 0);
      final cache = SignedUrlCache(
        ttl: const Duration(hours: 1),
        refreshMargin: const Duration(minutes: 5),
        clock: () => now,
      );
      cache.put('u/a.jpg', 'https://signed/a');
      now = DateTime(2026, 1, 1, 12, 56); // expiry 13:00, inside 5-min margin
      expect(cache.get('u/a.jpg'), isNull);
    });
  });
}
