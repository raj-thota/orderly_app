import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiry_detail_screen.dart';

import 'capture_controller_test.dart' show FakeEnquiriesService;

class RecordingEnquiriesService extends FakeEnquiriesService {
  String? convertedLeadId;
  String? bookedProductId;

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    convertedLeadId = leadId;
    bookedProductId = bookProductId;
    return 'o1';
  }
}

void main() {
  final enquiry = Enquiry.fromMap({
    'id': 'e1',
    'customer_id': 'c1',
    'product_id': 'p1',
    'status': 'new',
    'message': 'Wants the red saree',
    'customers': {'name': 'Priya', 'phone': '9876543210'},
    'products': {
      'name': 'Red Banarasi',
      'images': <String>[],
      'price': 5500,
      'is_unique': true,
      'piece_status': 'available',
    },
  });

  testWidgets('convert to order books the unique piece', (tester) async {
    final service = RecordingEnquiriesService();
    await tester.pumpWidget(ProviderScope(
      overrides: [enquiriesServiceProvider.overrideWithValue(service)],
      child: MaterialApp(home: EnquiryDetailScreen(enquiry: enquiry)),
    ));

    await tester.ensureVisible(find.text('Convert to order'));
    await tester.tap(find.text('Convert to order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(service.convertedLeadId, 'e1');
    expect(service.bookedProductId, 'p1');
  });
}
