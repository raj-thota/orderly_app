import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/app_header.dart';

void main() {
  final now = DateTime(2026, 7, 9, 12);

  Map<String, dynamic> lead({String? status, String? followUp}) => {
        'status': ?status,
        'follow_up_date': ?followUp,
      };

  group('dashboardDailyBrief', () {
    test('all-clear when nothing is pending', () {
      expect(dashboardDailyBrief([], now), "You're all caught up today 🎉");
    });

    test('counts overdue and due-today follow-ups, excludes future', () {
      final leads = [
        lead(status: 'follow', followUp: '2026-07-08'), // overdue
        lead(status: 'follow', followUp: '2026-07-09'), // today
        lead(status: 'follow', followUp: '2026-07-20'), // future
      ];
      expect(dashboardDailyBrief(leads, now), '2 follow-ups due');
    });

    test('uses singular for a single follow-up', () {
      final leads = [lead(status: 'follow', followUp: '2026-07-09')];
      expect(dashboardDailyBrief(leads, now), '1 follow-up due');
    });

    test('counts fresh enquiries to chase', () {
      final leads = [lead(status: 'new'), lead(status: 'new')];
      expect(dashboardDailyBrief(leads, now), '2 enquiries to chase');
    });

    test('singular enquiry phrasing', () {
      expect(dashboardDailyBrief([lead(status: 'new')], now),
          '1 enquiry to chase');
    });

    test('joins both parts', () {
      final leads = [
        lead(status: 'follow', followUp: '2026-07-08'),
        lead(status: 'new'),
      ];
      expect(dashboardDailyBrief(leads, now),
          '1 follow-up due · 1 enquiry to chase');
    });

    test('ignores won/lost/closed leads', () {
      final leads = [
        lead(status: 'won', followUp: '2026-07-08'),
        lead(status: 'lost', followUp: '2026-07-08'),
        lead(status: 'closed', followUp: '2026-07-08'),
      ];
      expect(dashboardDailyBrief(leads, now), "You're all caught up today 🎉");
    });
  });
}
