import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/data/business_profile_service.dart';

void main() {
  test('assetStoragePath namespaces by user id and kind', () {
    final path = BusinessProfileService.assetStoragePath(
      userId: 'user-123',
      kind: 'logo',
      extension: 'jpg',
    );
    expect(path.startsWith('user-123/logo-'), isTrue);
    expect(path.endsWith('.jpg'), isTrue);
  });
}
