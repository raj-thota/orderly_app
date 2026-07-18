import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/shared/widgets/settings_tile.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('default tile fires onTap', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(SettingsTile(
      icon: Icons.star,
      title: 'Go',
      onTap: () => tapped = true,
    )));
    await t.tap(find.text('Go'));
    expect(tapped, isTrue);
  });

  testWidgets('comingSoon tile is disabled and labelled', (t) async {
    var tapped = false;
    await t.pumpWidget(_host(SettingsTile(
      icon: Icons.star,
      title: 'Theme',
      comingSoon: true,
      onTap: () => tapped = true,
    )));
    expect(find.text('Coming soon'), findsOneWidget);
    await t.tap(find.text('Theme'));
    expect(tapped, isFalse); // disabled
  });
}
