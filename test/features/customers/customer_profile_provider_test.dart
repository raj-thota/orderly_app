import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/customers/controller/customer_profile_provider.dart';
import 'package:orderly_app/features/customers/data/customer_stats.dart';
import 'package:orderly_app/features/customers/data/customer_stats_service.dart';

class FakeStatsService implements CustomerStatsService {
  final Map<String, CustomerStats> data;
  FakeStatsService(this.data);

  @override
  Future<CustomerStats?> fetchStats(String customerId) async => data[customerId];
}

ProviderContainer _container(FakeStatsService fake) {
  final c = ProviderContainer(overrides: [
    customerStatsServiceProvider.overrideWithValue(fake),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  final stats = CustomerStats(
    customerId: 'c1',
    name: 'Priya',
    totalOrders: 3,
    lifetimeValue: 15000,
    outstanding: 2000,
    lastContactAt: DateTime.now().subtract(const Duration(days: 5)),
    aiFacts: const [AiFact(fact: 'Prefers evening replies')],
  );

  test('customerStatsProvider returns stats from service', () async {
    final c = _container(FakeStatsService({'c1': stats}));
    final result = await c.read(customerStatsProvider('c1').future);
    expect(result?.name, 'Priya');
    expect(result?.totalOrders, 3);
  });

  test('customerStatsProvider returns null when not found', () async {
    final c = _container(FakeStatsService({}));
    final result = await c.read(customerStatsProvider('c1').future);
    expect(result, isNull);
  });

  test('relationshipScoreProvider derives from customerStats', () async {
    final c = _container(FakeStatsService({'c1': stats}));
    await c.read(customerStatsProvider('c1').future);
    final score = c.read(relationshipScoreProvider('c1'));
    expect(score, greaterThan(0));
    expect(score, lessThanOrEqualTo(5.0));
  });

  test('relationshipScoreProvider returns 0 when stats not loaded', () {
    final c = _container(FakeStatsService({}));
    final score = c.read(relationshipScoreProvider('c1'));
    expect(score, 0.0);
  });
}
