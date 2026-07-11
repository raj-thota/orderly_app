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
