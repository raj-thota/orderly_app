import 'dart:async';

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

/// A service whose createOrder waits on a completer you control.
class BlockingEnquiriesService extends FakeEnquiriesService {
  int callCount = 0;
  final Completer<String> completer;

  BlockingEnquiriesService(this.completer);

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    callCount += 1;
    return completer.future;
  }
}

/// A service whose createOrder always throws piece_unavailable.
class UnavailableEnquiriesService extends FakeEnquiriesService {
  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    throw Exception('piece_unavailable');
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

  testWidgets('double-tap cannot double-convert', (tester) async {
    final completer = Completer<String>();
    final service = BlockingEnquiriesService(completer);

    await tester.pumpWidget(ProviderScope(
      overrides: [enquiriesServiceProvider.overrideWithValue(service)],
      child: MaterialApp(home: EnquiryDetailScreen(enquiry: enquiry)),
    ));

    // First tap — opens dialog.
    await tester.ensureVisible(find.text('Convert to order'));
    await tester.tap(find.text('Convert to order'));
    await tester.pumpAndSettle();

    // Confirm — starts the in-flight request.
    await tester.tap(find.text('Confirm'));
    await tester.pump(); // one frame so _busy = true is set

    // Button is now in loading state (shows spinner, text gone, onPressed=null).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Second tap: target the FilledButton directly — onPressed is null so it
    // is a no-op; _busy guards any path that could still reach _convert.
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Complete the async call and settle.
    completer.complete('o1');
    await tester.pumpAndSettle();

    // createOrder must have been called exactly once.
    expect(service.callCount, 1);
  });

  testWidgets('unavailable piece shows the specific message', (tester) async {
    final service = UnavailableEnquiriesService();

    await tester.pumpWidget(ProviderScope(
      overrides: [enquiriesServiceProvider.overrideWithValue(service)],
      child: MaterialApp(home: EnquiryDetailScreen(enquiry: enquiry)),
    ));

    await tester.ensureVisible(find.text('Convert to order'));
    await tester.tap(find.text('Convert to order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('This piece is already booked or sold.'), findsOneWidget);
  });
}
