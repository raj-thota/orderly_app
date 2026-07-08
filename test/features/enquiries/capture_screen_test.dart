import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';
import 'package:orderly_app/features/enquiries/presentation/capture_screen.dart';

import 'capture_controller_test.dart'
    show FakeAiParseService, FakeCustomersService, FakeEnquiriesService;

Widget wrap(Widget child, FakeEnquiriesService enquiries, {AiParseService? ai}) {
  return ProviderScope(
    overrides: [
      customersServiceProvider.overrideWithValue(FakeCustomersService()),
      enquiriesServiceProvider.overrideWithValue(enquiries),
      aiParseServiceProvider.overrideWithValue(ai ?? FakeAiParseService(null)),
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
