import 'package:supabase_flutter/supabase_flutter.dart';
import 'business_profile.dart';

class BusinessProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<BusinessProfile?> fetch() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final row = await _supabase
        .from('business_profile')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return BusinessProfile.fromMap(row);
  }

  Future<bool> exists() async => (await fetch()) != null;

  Future<BusinessProfile> upsert(BusinessProfile profile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');

    final payload = {
      ...profile.toMap(),
      'user_id': user.id,
    };

    final row = await _supabase
        .from('business_profile')
        .upsert(payload, onConflict: 'user_id')
        .select()
        .single();

    return BusinessProfile.fromMap(row);
  }
}
