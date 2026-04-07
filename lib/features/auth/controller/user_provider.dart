import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;

  if (user == null) return null;

  final data = await Supabase.instance.client
      .from('users')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  final metadata = user.userMetadata ?? {};

  return {
    ...(data ?? {}),

    "business_name":
        data?["business_name"] ??
        metadata["full_name"] ??
        metadata["name"] ??
        "Your Business",

    "phone": data?["phone"] ?? "",
    "email": user.email,

    "avatar_url": metadata["avatar_url"],
  };
});
