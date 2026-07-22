import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/quotations/presentation/quote_share_sheet.dart';

void main() {
  const message = 'Rekha Boutique\nQuotation for Priya\n\nSaree x 1 = 2500';

  /// Pumps a host screen with a button that opens the sheet and records the
  /// result the sheet resolves with.
  Future<String? Function()> pumpHost(
    WidgetTester tester,
    QuoteShareRequest request, {
    QuoteUrlLauncher? launcher,
  }) async {
    String? result;
    var resolved = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result =
                  await showQuoteShareSheet(context, request, launcher: launcher);
              resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () {
      expect(resolved, isTrue, reason: 'sheet future should have resolved');
      return result;
    };
  }

  testWidgets('email button disabled without an email address', (tester) async {
    await pumpHost(tester, const QuoteShareRequest(message: message));
    final email = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text('Email'), matching: find.byType(OutlinedButton)));
    expect(email.onPressed, isNull);
  });

  testWidgets('email button enabled with an email address', (tester) async {
    await pumpHost(tester,
        const QuoteShareRequest(message: message, customerEmail: 'a@b.com'));
    final email = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text('Email'), matching: find.byType(OutlinedButton)));
    expect(email.onPressed, isNotNull);
  });

  testWidgets('copy returns the edited message text', (tester) async {
    // Clipboard.setData goes over the platform channel; give it a handler.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async => null);
    final getResult =
        await pumpHost(tester, const QuoteShareRequest(message: message));

    await tester.enterText(find.byType(TextField), '$message\nFree delivery');
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(getResult(), '$message\nFree delivery');
  });

  testWidgets('whatsapp launches wa.me with normalized phone and encoded text',
      (tester) async {
    Uri? launchedUri;
    final getResult = await pumpHost(
      tester,
      const QuoteShareRequest(
          message: message, customerPhone: '+91 98765 43210'),
      launcher: (uri) async {
        launchedUri = uri;
        return true;
      },
    );

    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();

    expect(launchedUri.toString(), startsWith('https://wa.me/919876543210?text='));
    expect(launchedUri!.queryParameters['text'], message);
    expect(getResult(), message);
  });

  testWidgets('whatsapp falls back to bare wa.me when phone is missing',
      (tester) async {
    Uri? launchedUri;
    await pumpHost(
      tester,
      const QuoteShareRequest(message: message),
      launcher: (uri) async {
        launchedUri = uri;
        return true;
      },
    );

    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();

    expect(launchedUri.toString(), startsWith('https://wa.me/?text='));
  });

  testWidgets('failed launch keeps sheet open and dismissal returns null',
      (tester) async {
    final getResult = await pumpHost(
      tester,
      const QuoteShareRequest(message: message, customerPhone: '9876543210'),
      launcher: (_) async => false,
    );

    await tester.tap(find.text('WhatsApp'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open WhatsApp'), findsOneWidget);
    expect(find.text('Send quotation'), findsOneWidget); // still open

    // Dismiss by tapping the barrier above the sheet.
    await tester.tapAt(const Offset(200, 50));
    await tester.pumpAndSettle();
    expect(getResult(), isNull);
  });

  testWidgets('email launch builds a mailto uri with subject and body',
      (tester) async {
    Uri? launchedUri;
    final getResult = await pumpHost(
      tester,
      const QuoteShareRequest(
        message: message,
        customerEmail: 'priya@example.com',
        businessName: 'Rekha Boutique',
      ),
      launcher: (uri) async {
        launchedUri = uri;
        return true;
      },
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();

    expect(launchedUri!.scheme, 'mailto');
    expect(launchedUri!.path, 'priya@example.com');
    expect(launchedUri.toString(),
        contains(Uri.encodeComponent('Quotation from Rekha Boutique')));
    expect(getResult(), message);
  });
}
