import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_profile.dart';
import '../data/business_profile_service.dart';

final businessProfileServiceProvider =
    Provider<BusinessProfileService>((ref) => BusinessProfileService());

/// Loads the current user's business profile (null if not set up yet).
final businessProfileProvider = FutureProvider<BusinessProfile?>((ref) async {
  return ref.watch(businessProfileServiceProvider).fetch();
});
