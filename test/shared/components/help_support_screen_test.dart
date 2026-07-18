import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/components/help_and_support_screen.dart';

void main() {
  testWidgets('help content reflects the real Closr workflow', (t) async {
    await t.pumpWidget(const MaterialApp(home: HelpSupportScreen()));
    await t.pumpAndSettle();
    expect(find.text('Capture a lead'), findsOneWidget);
    expect(find.text('Work in Focus Mode'), findsOneWidget);
    expect(find.text('Record payments'), findsOneWidget);
    expect(find.text('Share invoices'), findsOneWidget);
  });

  testWidgets('links to FAQs and no longer duplicates Support/Legal', (t) async {
    await t.pumpWidget(const MaterialApp(home: HelpSupportScreen()));
    await t.pumpAndSettle();
    // Support/Legal moved to Settings (single home) — gone from this screen.
    expect(find.text('Contact Support'), findsNothing);
    expect(find.text('Privacy Policy'), findsNothing);
    expect(find.text('Terms of Service'), findsNothing);
    // FAQs entry present (below the fold — scroll to reveal).
    await t.scrollUntilVisible(
      find.text('Frequently Asked Questions'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Frequently Asked Questions'), findsOneWidget);
  });
}
