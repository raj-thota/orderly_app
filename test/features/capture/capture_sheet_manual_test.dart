import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/capture/presentation/capture_sheet.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/contacts_service.dart';
import 'package:orderly_app/features/enquiries/data/customers_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';

/// Stubs for the two services that would otherwise reach Supabase auth at
/// provider construction. No methods are called in these tests (we never save).
class _StubCustomers implements CustomersService {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _StubEnquiries implements EnquiriesService {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeContacts implements ContactsService {
  _FakeContacts(this._pick);
  final ContactPick? _pick;
  @override
  Future<ContactPick?> pickContact() async => _pick;
}

Finder _fieldByHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

Future<ProviderContainer> _pumpManualForm(
  WidgetTester tester, {
  ContactsService? contacts,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      customersServiceProvider.overrideWithValue(_StubCustomers()),
      enquiriesServiceProvider.overrideWithValue(_StubEnquiries()),
      if (contacts != null)
        contactsServiceProvider.overrideWithValue(contacts),
    ],
    child: const MaterialApp(home: Scaffold(body: CaptureSheet())),
  ));
  // Choose the Manual Entry source to reveal the structured form.
  await tester.tap(find.text('Manual Entry'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(CaptureSheet)));
}

void main() {
  testWidgets('typed name lands in the draft (no more "Unknown")',
      (tester) async {
    final container = await _pumpManualForm(tester);

    await tester.enterText(_fieldByHint('Customer name'), 'Rahul');
    await tester.pump();

    expect(container.read(captureControllerProvider).draft.name, 'Rahul');
  });

  testWidgets('Pick from Contacts prefills name and phone', (tester) async {
    final container = await _pumpManualForm(
      tester,
      contacts: _FakeContacts(
          const ContactPick(name: 'Meera', phone: '9876543210')),
    );

    await tester.tap(find.byTooltip('Pick from Contacts'));
    await tester.pumpAndSettle();

    final draft = container.read(captureControllerProvider).draft;
    expect(draft.name, 'Meera');
    expect(draft.phone, '9876543210');
    // Fields reflect the imported values so the user can edit them.
    expect(_fieldByHint('Customer name'), findsOneWidget);
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
  });
}
