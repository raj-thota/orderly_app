import 'package:supabase_flutter/supabase_flutter.dart';

import 'subscription.dart';

abstract class SubscriptionService {
  Stream<Subscription?> watchSubscription();
  Future<void> ensureTrial();
}

class SupabaseSubscriptionService implements SubscriptionService {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Stream<Subscription?> watchSubscription() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();

    return _client
        .from('subscriptions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) {
          if (rows.isEmpty) return null;
          return Subscription.fromMap(rows.first);
        });
  }

  @override
  Future<void> ensureTrial() async {
    await _client.rpc('ensure_trial');
  }
}
