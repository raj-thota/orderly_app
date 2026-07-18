import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_profile.dart';
import '../data/business_profile_service.dart';

final businessProfileServiceProvider =
    Provider<BusinessProfileService>((ref) => BusinessProfileService());

/// Loads the current user's business profile (null if not set up yet).
final businessProfileProvider = FutureProvider<BusinessProfile?>((ref) async {
  return ref.watch(businessProfileServiceProvider).fetch();
});

/// Decrypted bank account number + PAN, read via the owner-scoped RPC. Kept
/// separate from [businessProfileProvider] because these columns are encrypted
/// at rest and never returned by a plain profile select.
final businessSensitiveProvider =
    FutureProvider<({String? bankAccountNumber, String? pan})>((ref) async {
  return ref.watch(businessProfileServiceProvider).fetchSensitive();
});
