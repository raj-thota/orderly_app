import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/enquiries/controller/enquiries_provider.dart';
import 'package:orderly_app/features/enquiries/data/capture_draft.dart';
import 'package:orderly_app/features/enquiries/data/enquiries_service.dart';
import 'package:orderly_app/features/enquiries/data/enquiry.dart';

/// Fetch that never resolves until [gate] is completed, so a test can dispose
/// the controller while a load is mid-flight. Other methods are unused here.
class GatedEnquiriesService implements EnquiriesService {
  GatedEnquiriesService(this.gate);
  final Completer<List<Enquiry>> gate;

  @override
  Future<List<Enquiry>> fetchEnquiries() => gate.future;

  @override
  Future<Enquiry?> fetchById(String id) async => null;
  @override
  Future<String> uploadScreenshot(String localPath) async => '';
  @override
  Future<void> updateEnquiry(String id, Map<String, dynamic> changes) async {}
  @override
  Future<List<Map<String, dynamic>>> fetchLegacyMaps() async => [];
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
  }) async =>
      const Enquiry();
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
  }) async =>
      '';
}

void main() {
  test('load does not throw when disposed mid-fetch', () async {
    // An auth change rebuilds the service provider, disposing this controller
    // while its constructor-kicked load() is still awaiting the server.
    final gate = Completer<List<Enquiry>>();
    final controller = EnquiriesController(GatedEnquiriesService(gate));
    final loadFuture = controller.load();
    controller.dispose();
    gate.complete(const [Enquiry()]);
    await expectLater(loadFuture, completes);
  });
}
