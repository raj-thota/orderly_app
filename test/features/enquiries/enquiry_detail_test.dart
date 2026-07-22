import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/data/products_service.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiry_detail_screen.dart';

import 'capture_controller_test.dart' show FakeEnquiriesService;

class QuoteRecordingService extends FakeEnquiriesService {
  final quoteCalls = <(String, String)>[];

  @override
  Future<void> appendQuoteActivity(String enquiryId, String quoteText) async {
    quoteCalls.add((enquiryId, quoteText));
  }
}

class _EmptyProductsService extends Fake implements ProductsService {
  @override
  Future<List<Product>> fetchProducts() async => const [];
}

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
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
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
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
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
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
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

  Future<void> pumpWithQuoteOverrides(
      WidgetTester tester, QuoteRecordingService service) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        enquiriesServiceProvider.overrideWithValue(service),
        productsServiceProvider.overrideWithValue(_EmptyProductsService()),
        businessProfileProvider.overrideWith(
            (ref) async => const BusinessProfile(name: 'Rekha Boutique')),
      ],
      child: MaterialApp(home: EnquiryDetailScreen(enquiry: enquiry)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('send quote shares and records a quote_sent activity',
      (tester) async {
    // Clipboard.setData goes over the platform channel; give it a handler.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
    final service = QuoteRecordingService();
    await pumpWithQuoteOverrides(tester, service);

    await tester.ensureVisible(find.text('Send quote'));
    await tester.tap(find.text('Send quote'));
    await tester.pumpAndSettle();

    // Sheet is prefilled from the enquiry's product and business profile.
    expect(find.text('Send quotation'), findsOneWidget);
    final preview = tester.widget<TextField>(find.byType(TextField));
    expect(preview.controller!.text, contains('Rekha Boutique'));
    expect(preview.controller!.text, contains('Red Banarasi'));

    // Copy always succeeds, so it must record the activity.
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(service.quoteCalls, hasLength(1));
    expect(service.quoteCalls.single.$1, 'e1');
    expect(service.quoteCalls.single.$2, contains('Red Banarasi'));
    expect(find.text('Quote sent'), findsOneWidget);
  });

  testWidgets('dismissing the quote sheet records nothing', (tester) async {
    final service = QuoteRecordingService();
    await pumpWithQuoteOverrides(tester, service);

    await tester.ensureVisible(find.text('Send quote'));
    await tester.tap(find.text('Send quote'));
    await tester.pumpAndSettle();
    expect(find.text('Send quotation'), findsOneWidget);

    // Dismiss via the barrier above the sheet.
    await tester.tapAt(const Offset(200, 50));
    await tester.pumpAndSettle();

    expect(service.quoteCalls, isEmpty);
  });
}
