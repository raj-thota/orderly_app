import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('five tabs do not overflow on a narrow screen', (tester) async {
    // Emulate a small phone width where 5 tabs are tightest.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          currentIndex: 4, // Invoices selected — shows its label
          onTap: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // A RenderFlex overflow would have been thrown during layout.
    expect(tester.takeException(), isNull);
    expect(find.text('Invoices'), findsOneWidget);
  });
}
