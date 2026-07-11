import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/app_bottom_nav.dart';

void main() {
  Widget harness({required int current, void Function(int)? onTap}) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          currentIndex: current,
          onTap: onTap ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows the four V1 tabs without overflow on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(current: 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in ['Today', 'My Work', 'Orders', 'Business']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('taps report the logical index across the center gap',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(harness(current: 0, onTap: taps.add));

    await tester.tap(find.text('Orders'));
    await tester.tap(find.text('Business'));
    expect(taps, [2, 3]);
  });
}
