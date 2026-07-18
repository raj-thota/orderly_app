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

  /// Path under the `business-assets` bucket. First segment = uid so the
  /// storage RLS policy authorizes the write.
  static String assetStoragePath({
    required String userId,
    required String kind, // 'logo' | 'signature'
    required String extension,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '$userId/$kind-$ts.$extension';
  }

  /// Prefix + starting number are DB-owned and excluded from `toMap`. Update
  /// them explicitly (rare; only from Invoice Settings).
  Future<void> updateInvoiceNumbering({
    String? prefix,
    int? nextNumber,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    final patch = <String, dynamic>{};
    if (prefix != null) patch['invoice_prefix'] = prefix;
    if (nextNumber != null) patch['next_invoice_number'] = nextNumber;
    if (patch.isEmpty) return;
    await _supabase
        .from('business_profile')
        .update(patch)
        .eq('user_id', user.id);
  }
}
