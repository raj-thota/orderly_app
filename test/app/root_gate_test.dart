import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/app/root_gate.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';

void main() {
  test('not authenticated -> intro', () {
    expect(
      rootDestinationFor(authed: false, profile: const AsyncValue.data(null)),
      RootDestination.intro,
    );
  });

  test('authed but no profile -> setup', () {
    expect(
      rootDestinationFor(authed: true, profile: const AsyncValue.data(null)),
      RootDestination.setup,
    );
  });

  test('authed with profile -> main', () {
    expect(
      rootDestinationFor(
        authed: true,
        profile: AsyncValue.data(const BusinessProfile(name: 'Shop')),
      ),
      RootDestination.main,
    );
  });

  test('authed while profile loading -> loading', () {
    expect(
      rootDestinationFor(authed: true, profile: const AsyncValue.loading()),
      RootDestination.loading,
    );
  });
}
