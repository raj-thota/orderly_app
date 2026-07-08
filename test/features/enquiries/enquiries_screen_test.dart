import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/enquiries/presentation/enquiries_screen.dart';

import 'capture_controller_test.dart' show FakeEnquiriesService;

class SeededEnquiriesService extends FakeEnquiriesService {
  SeededEnquiriesService(this.seed);
  final List<Enquiry> seed;
  @override
  Future<List<Enquiry>> fetchEnquiries() async => seed;
}

void main() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));

  Widget app(List<Enquiry> seed) => ProviderScope(
        overrides: [
          enquiriesServiceProvider
              .overrideWithValue(SeededEnquiriesService(seed)),
        ],
        child: const MaterialApp(home: EnquiriesScreen()),
      );

  testWidgets('groups enquiries into buckets', (tester) async {
    await tester.pumpWidget(app([
      Enquiry.fromMap({
        'id': 'e1',
        'status': 'follow',
        'follow_up_date': yesterday.toIso8601String(),
        'customers': {'name': 'Priya'},
      }),
      Enquiry.fromMap({
        'id': 'e2',
        'status': 'new',
        'customers': {'name': 'Anita'},
      }),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Anita'), findsOneWidget);
  });

  testWidgets('search filters by customer name', (tester) async {
    await tester.pumpWidget(app([
      Enquiry.fromMap({
        'id': 'e1',
        'status': 'new',
        'customers': {'name': 'Priya'},
      }),
      Enquiry.fromMap({
        'id': 'e2',
        'status': 'new',
        'customers': {'name': 'Anita'},
      }),
    ]));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('enquiry-search')), 'pri');
    await tester.pumpAndSettle();

    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Anita'), findsNothing);
  });

  testWidgets('empty state renders', (tester) async {
    await tester.pumpWidget(app([]));
    await tester.pumpAndSettle();
    expect(find.textContaining('No enquiries'), findsOneWidget);
  });
}
