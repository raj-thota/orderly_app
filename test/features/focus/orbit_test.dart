import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/presentation/orbit.dart';

void main() {
  testWidgets('renders each mood without error', (tester) async {
    for (final mood in OrbitMood.values) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: Orbit(mood: mood, size: 96)))));
      expect(find.byType(Orbit), findsOneWidget);
    }
  });
}
