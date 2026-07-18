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
    // Scroll to reveal items below the fold before checking.
    await t.scrollUntilVisible(
      find.text('Contact Support'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Contact Support'), findsOneWidget);
  });
}
