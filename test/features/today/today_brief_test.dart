import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/orders/data/order.dart';
import 'package:orderly_app/features/payments/data/payment.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';

void main() {
  final now = DateTime(2026, 7, 11, 10); // Saturday 10:00

  group('buildTodayBrief', () {
    test('zeroes on empty data', () {
      final b = buildTodayBrief(orders: [], enquiries: [], now: now);
      expect(b.outstanding, 0);
      expect(b.dueFollowUps, 0);
      expect(b.ordersToday, 0);
      expect(b.revenueToday, 0);
    });

    test('outstanding sums dues across all orders', () {
      final orders = [
        Order(grandTotal: 1000, payments: [Payment(amount: 400)]), // 600 due
        const Order(grandTotal: 500), // 500 due
        Order(grandTotal: 300, payments: [Payment(amount: 300)]), // paid
        Order(grandTotal: 100, payments: [Payment(amount: 150)]), // over-paid → dues 0
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.outstanding, 1100);
    });

    test('dueFollowUps counts overdue and today buckets only', () {
      final enquiries = [
        Enquiry(status: 'follow', followUpDate: DateTime(2026, 7, 10)), // overdue
        Enquiry(status: 'follow', followUpDate: DateTime(2026, 7, 11, 18)), // today
        Enquiry(status: 'follow', followUpDate: DateTime(2026, 7, 20)), // upcoming
        const Enquiry(status: 'new'), // fresh
      ];
      final b = buildTodayBrief(orders: [], enquiries: enquiries, now: now);
      expect(b.dueFollowUps, 2);
    });

    test('ordersToday counts orders created today only', () {
      final orders = [
        Order(createdAt: DateTime(2026, 7, 11, 1)),
        Order(createdAt: DateTime(2026, 7, 11, 23)),
        Order(createdAt: DateTime(2026, 7, 10, 23)),
        const Order(), // null createdAt
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.ordersToday, 2);
    });

    test('cancelled orders do not count toward outstanding or orders today',
        () {
      final orders = [
        Order(
            grandTotal: 1890,
            status: 'cancelled',
            createdAt: DateTime(2026, 7, 11, 9)), // today
        const Order(grandTotal: 500), // live, unpaid
        // Money already received on a cancelled order still counts as revenue.
        Order(grandTotal: 700, status: 'cancelled', payments: [
          Payment(amount: 200, paidAt: DateTime(2026, 7, 11, 8)),
        ]),
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.outstanding, 500);
      expect(b.outstandingCount, 1);
      expect(b.ordersToday, 0);
      expect(b.revenueToday, 200);
    });

    test('outstandingCount counts only orders with dues', () {
      final orders = [
        Order(grandTotal: 1000, payments: [Payment(amount: 400)]),
        const Order(grandTotal: 500),
        Order(grandTotal: 300, payments: [Payment(amount: 300)]),
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.outstandingCount, 2);
    });

    test('dueName/dueSince track the longest-waiting due follow-up', () {
      final enquiries = [
        Enquiry(
            status: 'follow',
            followUpDate: DateTime(2026, 7, 10, 9),
            customerName: 'Asha'),
        Enquiry(
            status: 'follow',
            followUpDate: DateTime(2026, 7, 9, 9),
            customerName: 'Meera'),
        Enquiry(
            status: 'follow',
            followUpDate: DateTime(2026, 7, 20),
            customerName: 'Later'), // upcoming — ignored
      ];
      final b = buildTodayBrief(orders: [], enquiries: enquiries, now: now);
      expect(b.dueName, 'Meera');
      expect(b.dueSince, DateTime(2026, 7, 9, 9));
    });

    test('dueName is null when nothing is due', () {
      final b = buildTodayBrief(orders: [], enquiries: [], now: now);
      expect(b.dueName, isNull);
      expect(b.dueSince, isNull);
    });

    test('revenueToday sums payments received today across orders', () {
      final orders = [
        Order(grandTotal: 5000, payments: [
          Payment(amount: 2000, paidAt: DateTime(2026, 7, 11, 9)),
          Payment(amount: 1000, paidAt: DateTime(2026, 7, 10, 9)), // yesterday
        ]),
        Order(grandTotal: 800, payments: [
          Payment(amount: 800, paidAt: DateTime(2026, 7, 11, 8)),
        ]),
      ];
      final b = buildTodayBrief(orders: orders, enquiries: [], now: now);
      expect(b.revenueToday, 2800);
    });
  });
}
