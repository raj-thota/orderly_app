import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/conversations/controller/conversation_provider.dart' show conversationsServiceProvider;
import 'package:orderly_app/features/conversations/data/conversation.dart';
import 'package:orderly_app/features/conversations/data/conversations_service.dart';
import 'package:orderly_app/features/conversations/data/message.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/ai_parse_service.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/customer.dart';
import 'package:orderly_app/features/enquiries/data/customers_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';
import 'package:orderly_app/features/followups/data/follow_up.dart';
import 'package:orderly_app/features/followups/data/follow_ups_service.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';
import 'package:orderly_app/features/work/controller/work_items_provider.dart';
import 'package:orderly_app/features/work/data/ai_work_items_service.dart';

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
    String? screenshotPath,
    String? quoteText,
  }) async {
    enquiries.add({
      'customer_id': customerId,
      'product_id': productId,
      'source': source,
      'status': followUpDate != null ? 'follow' : 'new',
      'screenshot_path': screenshotPath,
      'quote_text': quoteText,
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
    double discount = 0,
    double shippingFee = 0,
    DateTime? expectedDate,
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
  Future<String> uploadScreenshot(String localPath) async => 'fake/$localPath';
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
  Uint8List? lastImage;

  @override
  Future<AiParse?> refine(String text,
      {Uint8List? image, String mime = 'image/jpeg'}) async {
    lastImage = image;
    if (delay != Duration.zero) await Future.delayed(delay);
    return _result;
  }
}

class FakeConversationsService implements ConversationsService {
  final List<Map<String, dynamic>> messages = [];
  int getOrCreateCalls = 0;

  @override
  Future<Conversation> getOrCreate(String customerId) async {
    getOrCreateCalls++;
    return Conversation(id: 'cv-new', customerId: customerId);
  }

  @override
  Future<Message> addMessage({
    required String conversationId,
    required String direction,
    required String source,
    required String body,
    DateTime? sentAt,
    Map<String, dynamic> meta = const {},
  }) async {
    messages.add({
      'conversation_id': conversationId,
      'direction': direction,
      'source': source,
      'body': body,
    });
    return Message(
        id: 'm-new',
        conversationId: conversationId,
        direction: direction,
        source: source,
        body: body);
  }

  @override
  Future<Conversation?> fetchByCustomerId(String customerId) async => null;
  @override
  Future<List<Message>> fetchMessages(String conversationId) async => [];
}

class FakeFollowUpsService implements FollowUpsService {
  final List<Map<String, dynamic>> upserted = [];

  @override
  Future<FollowUp> upsertForLead({
    required String customerId,
    required String leadId,
    required DateTime dueAt,
    String kind = 'general',
    String? note,
  }) async {
    upserted.add({'customer_id': customerId, 'lead_id': leadId, 'kind': kind});
    return FollowUp(
        id: 'fu-new',
        customerId: customerId,
        dueAt: dueAt,
        kind: kind,
        status: 'pending');
  }

  @override
  Future<List<FollowUp>> fetchPending() async => [];
  @override
  Future<List<FollowUp>> fetchForWeek(DateTime weekStart) async => [];
  @override
  Future<void> markDone(String id) async {}
  @override
  Future<void> markSkipped(String id) async {}
}

ProviderContainer makeContainer(
    FakeCustomersService customers, FakeEnquiriesService enquiries,
    {AiParseService? ai,
    FakeConversationsService? conversations,
    FakeFollowUpsService? followUps}) {
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(customers),
    enquiriesServiceProvider.overrideWithValue(enquiries),
    aiParseServiceProvider.overrideWithValue(ai ?? FakeAiParseService(null)),
    conversationsServiceProvider
        .overrideWithValue(conversations ?? FakeConversationsService()),
    followUpsServiceProvider
        .overrideWithValue(followUps ?? FakeFollowUpsService()),
  ]);
  addTearDown(container.dispose);
  // Keep the autoDispose controller alive across async gaps, as a listening
  // widget would in production; otherwise it disposes and resets mid-test.
  container.listen(captureControllerProvider, (_, _) {}, fireImmediately: true);
  return container;
}

/// Spy controllers that count reloads without touching Supabase, so we can
/// assert [refreshAfterCapture] fans out to every list surface.
class SpyEnquiriesController extends EnquiriesController {
  SpyEnquiriesController() : super(FakeEnquiriesService());
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

class SpyOrdersController extends OrdersController {
  SpyOrdersController() : super(OrdersService());
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

class SpyWorkItemsNotifier extends WorkItemsNotifier {
  SpyWorkItemsNotifier() : super(SupabaseAiWorkItemsService());
  int loads = 0;
  @override
  Future<void> load() async => loads++;
}

Enquiry _openEnquiry({String? name, String? phone, String status = 'new'}) =>
    Enquiry.fromMap({
      'id': 'e-$name-$phone',
      'status': status,
      'source': 'paste',
      'customers': {'name': name, 'phone': phone},
    });

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

  test('attachScreenshot stores the shot and refines with the image', () async {
    final fakeAi = FakeAiParseService(const AiParse(
      name: 'Priya',
      intent: 'order',
      type: 'order',
      confidence: 0.9,
    ));
    final c = makeContainer(
        FakeCustomersService(), FakeEnquiriesService(), ai: fakeAi);
    final controller = c.read(captureControllerProvider.notifier);

    final bytes = Uint8List.fromList([9, 8, 7]);
    controller.attachScreenshot(bytes, path: '/tmp/shot.jpg');
    await Future<void>.delayed(Duration.zero);

    final state = c.read(captureControllerProvider);
    expect(state.screenshotPath, '/tmp/shot.jpg');
    expect(state.screenshotBytes, bytes);
    expect(fakeAi.lastImage, bytes); // image reached the AI service
    expect(state.draft.name, 'Priya'); // merge ran
    expect(state.aiRefining, isFalse);
  });

  test('clearScreenshot detaches the shot and discards its refine', () async {
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      ai: FakeAiParseService(const AiParse(name: 'Late', confidence: 0.9),
          delay: const Duration(milliseconds: 60)),
    );
    final controller = c.read(captureControllerProvider.notifier);

    controller.attachScreenshot(Uint8List.fromList([1, 2, 3]),
        path: '/tmp/shot.jpg');
    controller.clearScreenshot();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final state = c.read(captureControllerProvider);
    expect(state.screenshotPath, isNull);
    expect(state.screenshotBytes, isNull);
    expect(state.draft.name, isNot('Late')); // superseded refine dropped
    expect(state.aiRefining, isFalse);
  });

  test('save forwards the quote text to addEnquiry', () async {
    final customers = FakeCustomersService();
    final enquiries = FakeEnquiriesService();
    final c = makeContainer(customers, enquiries);
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('Priya wants a saree');
    await controller.save(quoteText: 'QUOTE-BODY');

    expect(enquiries.enquiries.single['quote_text'], 'QUOTE-BODY');
  });

  test('buildQuotation composes from the draft, catalog and business', () async {
    final c = makeContainer(FakeCustomersService(), FakeEnquiriesService());
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('Priya wants 2 saree');

    final quote = controller.buildQuotation(
      businessName: 'Rekha Boutique',
      upiId: 'rekha@upi',
      upiName: 'Rekha',
      products: const [Product(id: 'p1', name: 'Silk Saree', price: 2500)],
    );

    expect(quote.total, 5000);
    expect(quote.message, contains('Rekha Boutique'));
    expect(quote.message, contains('Silk Saree x 2'));
    expect(quote.message, contains('₹5,000'));
  });

  // M2: conversations + follow_ups writes
  test('save writes a conversation and inbound message for an enquiry', () async {
    final conversations = FakeConversationsService();
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      conversations: conversations,
    );
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('Priya 9876543210 want 2 sarees');
    await controller.save();

    expect(conversations.getOrCreateCalls, 1);
    expect(conversations.messages, hasLength(1));
    expect(conversations.messages.single['direction'], 'inbound');
    expect(conversations.messages.single['source'], 'paste');
  });

  test('save skips message when raw text is empty', () async {
    final conversations = FakeConversationsService();
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      conversations: conversations,
    );
    final controller = c.read(captureControllerProvider.notifier);

    controller.setName('Priya');
    await controller.save();

    expect(conversations.getOrCreateCalls, 1);
    expect(conversations.messages, isEmpty);
  });

  test('save writes follow_up when intent is follow_up and date is set', () async {
    final followUps = FakeFollowUpsService();
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      followUps: followUps,
    );
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('Priya will confirm tomorrow');
    await controller.save();

    expect(followUps.upserted, hasLength(1));
    expect(followUps.upserted.single['customer_id'], 'c-new');
    expect(followUps.upserted.single['lead_id'], 'e-new');
  });

  test('save does not write follow_up when no follow-up date', () async {
    final followUps = FakeFollowUpsService();
    final c = makeContainer(
      FakeCustomersService(),
      FakeEnquiriesService(),
      followUps: followUps,
    );
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('Priya want 2 sarees');
    await controller.save();

    expect(followUps.upserted, isEmpty);
  });

  test('AI refine propagates budget and notes into draft', () async {
    final ai = FakeAiParseService(const AiParse(
      name: 'Priya',
      confidence: 0.9,
      budget: 8000,
      notes: 'prefers evening',
    ));
    final c = makeContainer(FakeCustomersService(), FakeEnquiriesService(),
        ai: ai);
    final controller = c.read(captureControllerProvider.notifier);

    controller.setText('want 2 sarees my budget is 8k');
    await Future<void>.delayed(Duration.zero);

    final state = c.read(captureControllerProvider);
    expect(state.draft.budget, 8000);
    expect(state.draft.notes, 'prefers evening');
    expect(state.draft.confidence, 0.9);
  });

  // ── refreshAfterCapture: the single post-save fan-out ──────────────────────
  testWidgets(
      'refreshAfterCapture reloads enquiries, orders and work items',
      (tester) async {
    final spyEnquiries = SpyEnquiriesController();
    final spyOrders = SpyOrdersController();
    final spyWork = SpyWorkItemsNotifier();
    late WidgetRef capturedRef;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        enquiriesControllerProvider.overrideWith((_) => spyEnquiries),
        ordersControllerProvider.overrideWith((_) => spyOrders),
        workItemsProvider.overrideWith((_) => spyWork),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          capturedRef = ref;
          return const SizedBox.shrink();
        },
      ),
    ));

    refreshAfterCapture(capturedRef);

    // An order capture must refresh Orders, not only Enquiries — the original
    // bug was that only the enquiries list was reloaded.
    expect(spyEnquiries.loads, 1);
    expect(spyOrders.loads, 1);
    expect(spyWork.loads, 1);
  });

  // ── hasOpenEnquiryFor: non-blocking duplicate awareness ────────────────────
  group('hasOpenEnquiryFor', () {
    test('matches an open enquiry by normalized phone', () {
      final existing = [_openEnquiry(name: 'Priya', phone: '9876543210')];
      expect(
        hasOpenEnquiryFor(
            existing: existing, phone: '+91 98765 43210', name: 'Someone Else'),
        isTrue,
      );
    });

    test('falls back to case-insensitive name when no phone', () {
      final existing = [_openEnquiry(name: 'Anita Rao')];
      expect(hasOpenEnquiryFor(existing: existing, name: 'anita rao'), isTrue);
    });

    test('ignores the placeholder "Unknown" name', () {
      final existing = [_openEnquiry(name: 'Unknown')];
      expect(hasOpenEnquiryFor(existing: existing, name: 'Unknown'), isFalse);
    });

    test('no match returns false', () {
      final existing = [_openEnquiry(name: 'Priya', phone: '9876543210')];
      expect(
        hasOpenEnquiryFor(existing: existing, phone: '9000000000'),
        isFalse,
      );
    });
  });
}
