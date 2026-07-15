import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/business/controller/business_profile_provider.dart';
import 'package:orderly_app/features/business/data/business_profile.dart';
import 'package:orderly_app/features/catalog/controller/products_provider.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/catalog/data/products_service.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';
import 'package:orderly_app/features/enquiries/presentation/capture_screen.dart';

import 'capture_controller_test.dart'
    show
        FakeAiParseService,
        FakeConversationsService,
        FakeCustomersService,
        FakeEnquiriesService,
        FakeFollowUpsService;

class _StubProductsService implements ProductsService {
  @override
  Future<List<Product>> fetchProducts() async =>
      const [Product(id: 'p1', name: 'Silk Saree', price: 2500)];
  @override
  Future<Product> addProduct(Product product) async => product;
  @override
  Future<Product> updateProduct(String id, Map<String, dynamic> changes) async =>
      const Product(id: 'p1', name: 'Silk Saree', price: 2500);
  @override
  Future<void> archiveProduct(String id) async {}
  @override
  Future<String> uploadImage(String localPath) async => 'x';
  @override
  Future<void> removeImages(List<String> paths) async {}
  @override
  Future<String> signedUrl(String path) async => 'https://s/$path';
}

Widget wrap(Widget child, FakeEnquiriesService enquiries, {AiParseService? ai}) {
  return ProviderScope(
    overrides: [
      customersServiceProvider.overrideWithValue(FakeCustomersService()),
      enquiriesServiceProvider.overrideWithValue(enquiries),
      aiParseServiceProvider.overrideWithValue(ai ?? FakeAiParseService(null)),
      productsServiceProvider.overrideWithValue(_StubProductsService()),
      businessProfileProvider.overrideWith(
          (ref) async => const BusinessProfile(name: 'Rekha Boutique')),
      conversationsServiceProvider
          .overrideWithValue(FakeConversationsService()),
      followUpsServiceProvider.overrideWithValue(FakeFollowUpsService()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('typing fills the draft card and save button reads enquiry',
      (tester) async {
    await tester.pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));

    await tester.enterText(find.byKey(const Key('capture-input')),
        'This is Priya 9876543210, want 2 kurtis, will confirm tomorrow');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('Save enquiry'), findsOneWidget);
  });

  testWidgets('order text flips save button to Create order', (tester) async {
    await tester.pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));

    await tester.enterText(find.byKey(const Key('capture-input')),
        'Priya: confirm order 2 kurtis at ₹1500');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Create order'), findsOneWidget);
  });

  testWidgets('save creates enquiry and pops', (tester) async {
    final enquiries = FakeEnquiriesService();
    await tester.pumpWidget(wrap(const CaptureScreen(), enquiries));

    await tester.enterText(
        find.byKey(const Key('capture-input')), 'Priya wants a saree');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Save enquiry'));
    await tester.pumpAndSettle();

    expect(enquiries.enquiries, hasLength(1));
  });

  testWidgets('offers an attach-screenshot action', (tester) async {
    await tester
        .pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));
    expect(find.text('Screenshot'), findsOneWidget);
  });

  testWidgets('Send quote previews the composed message', (tester) async {
    await tester
        .pumpWidget(wrap(const CaptureScreen(), FakeEnquiriesService()));

    await tester.enterText(
        find.byKey(const Key('capture-input')), 'Priya wants 2 saree');
    await tester.pump(const Duration(milliseconds: 400));

    final sendQuote = find.text('Send quote');
    await tester.scrollUntilVisible(sendQuote, 200,
        scrollable: find.byType(Scrollable).first);
    expect(sendQuote, findsOneWidget);
    await tester.tap(sendQuote);
    await tester.pumpAndSettle();

    expect(find.textContaining('Rekha Boutique'), findsOneWidget);
    expect(find.textContaining('Silk Saree x 2'), findsOneWidget);
    expect(find.text('Share on WhatsApp'), findsOneWidget);
  });

  testWidgets('shows the AI refining indicator while a refine is in flight',
      (tester) async {
    await tester.pumpWidget(wrap(
      const CaptureScreen(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(null,
          delay: const Duration(milliseconds: 500)),
    ));

    await tester.enterText(
        find.byKey(const Key('capture-input')), 'order two sarees please');
    await tester.pump(const Duration(milliseconds: 350)); // debounce elapses
    expect(find.text('AI refining…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('AI refining…'), findsNothing);
  });
}
