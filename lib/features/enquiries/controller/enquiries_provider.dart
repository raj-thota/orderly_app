import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:orderly_app/core/providers/auth_providers.dart';
import '../data/capture_draft.dart';
import '../data/contacts_service.dart';
import '../data/customers_service.dart';
import '../data/enquiries_service.dart';
import '../data/enquiry.dart';

final customersServiceProvider = Provider<CustomersService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return CustomersService();
});

/// Native OS contact picker for the manual add form. Injected so tests can
/// override it with a fake instead of hitting the platform picker.
final contactsServiceProvider =
    Provider<ContactsService>((ref) => DeviceContactsService());

final enquiriesServiceProvider = Provider<EnquiriesService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return EnquiriesService();
});

final enquiriesControllerProvider = StateNotifierProvider<EnquiriesController,
    AsyncValue<List<Enquiry>>>((ref) {
  return EnquiriesController(ref.watch(enquiriesServiceProvider))..load();
});

class EnquiriesController extends StateNotifier<AsyncValue<List<Enquiry>>> {
  EnquiriesController(this._service) : super(const AsyncValue.loading());

  final EnquiriesService _service;

  Future<void> load() async {
    final next = await AsyncValue.guard(_service.fetchEnquiries);
    if (!mounted) return; // disposed mid-fetch by an auth-driven rebuild
    state = next;
  }

  Future<void> reschedule(String id, DateTime date, {String? note}) async {
    await _service.updateEnquiry(id, {
      'status': 'follow',
      'follow_up_date': date.toIso8601String(),
      'follow_up_note': ?note,
    });
    await load();
  }

  Future<void> markLost(String id) async {
    await _service.updateEnquiry(id, {'status': 'lost'});
    await load();
  }

  /// Converts to an order; books the attached unique piece.
  Future<String> convertToOrder(Enquiry enquiry, List<DraftItem> items) async {
    final orderId = await _service.createOrder(
      customerId: enquiry.customerId!,
      leadId: enquiry.id,
      items: items,
      bookProductId: enquiry.productIsUnique ? enquiry.productId : null,
      productIds: [
        for (var i = 0; i < items.length; i++)
          i == 0 ? enquiry.productId : null,
      ],
    );
    await load();
    return orderId;
  }
}
