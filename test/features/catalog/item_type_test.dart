import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/core/theme/app_colors.dart';
import 'package:orderly_app/features/catalog/data/item_type.dart';

void main() {
  group('ItemType', () {
    test('exposes the four supported types in order', () {
      expect(ItemType.values.map((t) => t.id).toList(),
          ['product', 'service', 'digital', 'other']);
    });

    test('fromId matches a known id', () {
      expect(ItemType.fromId('service'), ItemType.service);
      expect(ItemType.service.label, 'Service');
      expect(ItemType.service.accent, AppColors.typeServiceAccent);
    });

    test('fromId falls back to other for null or unknown', () {
      expect(ItemType.fromId(null), ItemType.other);
      expect(ItemType.fromId('subscription'), ItemType.other);
    });

    test('every type has a two-stop gradient', () {
      for (final t in ItemType.values) {
        expect(t.gradient.length, 2);
        expect(t.icon, isA<IconData>());
      }
    });
  });
}
