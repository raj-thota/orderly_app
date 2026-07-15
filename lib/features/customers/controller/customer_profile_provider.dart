import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/customer_stats.dart';
import '../data/customer_stats_service.dart';

final customerStatsServiceProvider = Provider<CustomerStatsService>(
  (_) => SupabaseCustomerStatsService(),
);

final customerStatsProvider = FutureProvider.autoDispose
    .family<CustomerStats?, String>((ref, customerId) async {
  final svc = ref.watch(customerStatsServiceProvider);
  return svc.fetchStats(customerId);
});

/// Derives a 0–5 score from loaded stats; returns 0 while still loading.
final relationshipScoreProvider =
    Provider.autoDispose.family<double, String>((ref, customerId) {
  final async = ref.watch(customerStatsProvider(customerId));
  return async.valueOrNull?.relationshipScore ?? 0.0;
});
