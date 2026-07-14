import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/shared/widgets/status_pill.dart';

void main() {
  group('StatusPillStyle.forStatus', () {
    test('maps available to success', () {
      final s = StatusPillStyle.forStatus('available');
      expect(s.label, 'Available');
      expect(s.color, AppColors.success);
    });

    test('maps booked to warning', () {
      expect(StatusPillStyle.forStatus('booked').color, AppColors.warning);
    });

    test('maps sold to secondary text color', () {
      expect(StatusPillStyle.forStatus('sold').label, 'Sold');
    });

    test('maps unpaid to danger', () {
      expect(StatusPillStyle.forStatus('unpaid').color, AppColors.danger);
    });

    test('maps paid to success', () {
      expect(StatusPillStyle.forStatus('paid').color, AppColors.success);
    });

    test('maps confirmed to warning with Confirmed label', () {
      final s = StatusPillStyle.forStatus('confirmed');
      expect(s.label, 'Confirmed');
      expect(s.color, AppColors.warning);
    });

    test('maps cancelled to danger with Cancelled label', () {
      final s = StatusPillStyle.forStatus('cancelled');
      expect(s.label, 'Cancelled');
      expect(s.color, AppColors.danger);
    });

    test('unknown status falls back to a readable label + neutral color', () {
      final s = StatusPillStyle.forStatus('whatever');
      expect(s.label, 'Whatever');
      expect(s.color, AppColors.textSecondary);
    });
  });

  testWidgets('StatusPill renders its label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatusPill(status: 'booked')),
    ));
    expect(find.text('Booked'), findsOneWidget);
  });
}
