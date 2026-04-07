import 'package:flutter_test/flutter_test.dart';

import 'package:orderly_app/main.dart';

void main() {
  testWidgets('shows setup guidance when Supabase is not configured', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const OrderlyApp());

    expect(find.text('Closr needs configuration'), findsOneWidget);
    expect(find.textContaining('--dart-define=SUPABASE_URL'), findsOneWidget);
  });
}
