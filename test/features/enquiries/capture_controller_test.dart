import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/customer.dart';
import 'package:orderly_app/features/enquiries/data/customers_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';

class FakeCustomersService implements CustomersService {
  final created = <Map<String, String?>>[];
  Customer? existing;

  @override
  Future<Customer> createOrLink({required String name, String? phone}) async {
    if (existing != null && phone != null && existing!.phone == phone) {
      return existing!;
    }
    created.add({'name': name, 'phone': phone});
    return Customer(id: 'c-new', name: name, phone: phone);
  }
}

class FakeEnquiriesService implements EnquiriesService {
  final enquiries = <Map<String, dynamic>>[];
  final orders = <Map<String, dynamic>>[];

  @override
  Future<Enquiry> addEnquiry({
    required String customerId,
    String? productId,
    required String source,
    String? message,
    String? intent,
    DateTime? followUpDate,
  }) async {
    enquiries.add({
      'customer_id': customerId,
      'product_id': productId,
      'source': source,
      'status': followUpDate != null ? 'follow' : 'new',
    });
    return Enquiry.fromMap({'id': 'e-new', 'customer_id': customerId});
  }

  @override
  Future<String> createOrder({
    required String customerId,
    String? leadId,
    required List<DraftItem> items,
    String? bookProductId,
    List<String?>? productIds,
    String? notes,
  }) async {
    orders.add({
      'customer_id': customerId,
      'lead_id': leadId,
      'items': items.length,
      'book': bookProductId,
    });
    return 'o-new';
  }

  @override
  Future<List<Enquiry>> fetchEnquiries() async => [];
  @override
  Future<Enquiry?> fetchById(String id) async => null;
  @override
  Future<void> updateEnquiry(String id, Map<String, dynamic> changes) async {}
  @override
  Future<List<Map<String, dynamic>>> fetchLegacyMaps() async => [];
}

class FakeAiParseService extends AiParseService {
  FakeAiParseService(this._result, {this.delay = Duration.zero})
      : super(invoker: (_) async => null);
  final AiParse? _result;
  final Duration delay;

  @override
  Future<AiParse?> refine(String text) async {
    if (delay != Duration.zero) await Future.delayed(delay);
    return _result;
  }
}

ProviderContainer makeContainer(
    FakeCustomersService customers, FakeEnquiriesService enquiries,
    {AiParseService? ai}) {
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(customers),
    enquiriesServiceProvider.overrideWithValue(enquiries),
    aiParseServiceProvider.overrideWithValue(ai ?? FakeAiParseService(null)),
  ]);
  addTearDown(container.dispose);
  // Keep the autoDispose controller alive across async gaps, as a listening
  // widget would in production; otherwise it disposes and resets mid-test.
  container.listen(captureControllerProvider, (_, _) {}, fireImmediately: true);
  return container;
}

void main() {
  test('save creates customer then enquiry with follow status', () async {
    final customers = FakeCustomersService();
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('This is Priya 9876543210, will confirm tomorrow');
    final result = await controller.save();

    expect(result.kind, SaveKind.enquiry);
    expect(customers.created.single['phone'], '9876543210');
    expect(enquiries.enquiries.single['status'], 'follow');
    expect(enquiries.enquiries.single['source'], 'paste');
  });

  test('save links existing customer by phone', () async {
    final customers = FakeCustomersService()
      ..existing = const Customer(id: 'c1', name: 'Priya', phone: '9876543210');
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('This is Priya 9876543210, price?');
    await controller.save();

    expect(customers.created, isEmpty);
    expect(enquiries.enquiries.single['customer_id'], 'c1');
  });

  test('order-type draft with items creates an order, books unique piece',
      () async {
    final customers = FakeCustomersService();
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.attachProduct(
        id: 'p1', name: 'Red Banarasi', isUnique: true, price: 5500);
    controller.setText('confirm order for 9876543210');
    final result = await controller.save();

    expect(result.kind, SaveKind.order);
    expect(enquiries.orders.single['book'], 'p1');
    expect(enquiries.enquiries, isEmpty);
  });

  test('manual field edits survive re-parse of message text', () async {
    final c = makeContainer(FakeCustomersService(), FakeEnquiriesService());
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('want 2 kurtis');
    controller.setName('Anita');
    controller.setText('want 2 kurtis tomorrow');

    expect(c.read(captureControllerProvider).draft.name, 'Anita');
  });

  test('re-parsed text replaces previously parsed name and phone', () async {
    final c = makeContainer(FakeCustomersService(), FakeEnquiriesService());
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('Hi this is Priya 9876543210');
    controller.setText('Hi this is Anita 9123456789');

    expect(c.read(captureControllerProvider).draft.name, 'Anita');
    expect(c.read(captureControllerProvider).draft.phone, '9123456789');
  });

  test('manual edits survive re-parse', () async {
    final c = makeContainer(FakeCustomersService(), FakeEnquiriesService());
    final controller = c.read(captureControllerProvider.notifier);

    controller.setName('Bob');
    controller.setPhone('+91 91234 56789');
    controller.setText('Hi this is Anita 9876543210');

    expect(c.read(captureControllerProvider).draft.name, 'Bob');
    expect(c.read(captureControllerProvider).draft.phone, '9123456789');
  });

  test('removing the attached item clears product linkage on save', () async {
    final customers = FakeCustomersService();
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.attachProduct(
        id: 'p1', name: 'Red Banarasi', isUnique: true, price: 5500);
    controller.removeItem(0);
    controller.setText('book 2 sarees at 500 for 9876543210');
    await controller.save();

    expect(enquiries.orders.single['book'], isNull);
  });

  test('AI refine overlays fields the user did not edit', () async {
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(const AiParse(
        name: 'Priya',
        phone: '9876543210',
        intent: 'order',
        type: 'order',
        confidence: 0.9,
      )),
    );
    final controller = c.read(captureControllerProvider.notifier);
    controller.setText('order some things please');
    await Future<void>.delayed(Duration.zero);

    final state = c.read(captureControllerProvider);
    expect(state.draft.name, 'Priya');
    expect(state.draft.phone, '9876543210');
    expect(state.draft.type, 'order');
    expect(state.aiRefining, isFalse);
    expect(state.aiHighlight, contains('name'));
  });

  test('manual edits are not overwritten by AI', () async {
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(const AiParse(
        name: 'Priya',
        phone: '9876543210',
        confidence: 0.9,
      )),
    );
    final controller = c.read(captureControllerProvider.notifier);
    controller.setName('Bob');
    controller.setText('some message');
    await Future<void>.delayed(Duration.zero);

    final state = c.read(captureControllerProvider);
    expect(state.draft.name, 'Bob'); // manual wins
    expect(state.draft.phone, '9876543210'); // AI fills the un-edited field
    expect(state.aiHighlight, isNot(contains('name')));
  });

  test('stale AI responses are discarded', () async {
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(
        const AiParse(name: 'Stale', confidence: 0.9),
        delay: const Duration(milliseconds: 60),
      ),
    );
    final controller = c.read(captureControllerProvider.notifier);
    controller.setText('first message');
    controller.setText('second message'); // supersedes the first
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final state = c.read(captureControllerProvider);
    expect(state.aiRefining, isFalse);
    expect(state.draft.raw, 'second message');
  });

  test('AI item list replaces rules items but keeps the attached product first',
      () async {
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(const AiParse(
        items: [DraftItem(name: 'Blouse', qty: 3, price: 200)],
        intent: 'order',
        type: 'order',
        confidence: 0.8,
      )),
    );
    final controller = c.read(captureControllerProvider.notifier);
    controller.attachProduct(
        id: 'p1', name: 'Silk Saree', isUnique: true, price: 5000);
    controller.setText('order 2 kurtis');
    await Future<void>.delayed(Duration.zero);

    final items = c.read(captureControllerProvider).draft.items;
    expect(items.first.name, 'Silk Saree'); // attachment pinned first
    expect(items.any((i) => i.name == 'Blouse'), isTrue); // AI item present
  });

  test('a manual edit during an in-flight refine discards that refine',
      () async {
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(
        const AiParse(
          items: [DraftItem(name: 'Blouse', qty: 5)],
          intent: 'order',
          type: 'order',
          confidence: 0.9,
        ),
        delay: const Duration(milliseconds: 60),
      ),
    );
    final controller = c.read(captureControllerProvider.notifier);
    controller.setText('customer wants some items');
    // While the refine is in flight, the user edits the draft by hand.
    final d = c.read(captureControllerProvider).draft;
    controller.editDraft(
        d.copyWith(followUpDate: DateTime(2026, 12, 25), intent: 'follow_up'));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final state = c.read(captureControllerProvider);
    expect(state.draft.followUpDate, DateTime(2026, 12, 25)); // manual survived
    expect(state.draft.intent, 'follow_up'); // AI 'order' discarded
    expect(state.aiRefining, isFalse);
  });
}
