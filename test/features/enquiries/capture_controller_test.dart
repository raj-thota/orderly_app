import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/capture_provider.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
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

ProviderContainer makeContainer(
    FakeCustomersService customers, FakeEnquiriesService enquiries) {
  final container = ProviderContainer(overrides: [
    customersServiceProvider.overrideWithValue(customers),
    enquiriesServiceProvider.overrideWithValue(enquiries),
  ]);
  addTearDown(container.dispose);
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
}
