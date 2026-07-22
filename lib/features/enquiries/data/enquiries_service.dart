import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'capture_draft.dart';
import 'enquiry.dart';

const _selectWithJoins =
    '*, customers(name, phone, email), products(name, images, price, is_unique, piece_status)';

class EnquiriesService {
  SupabaseClient get _client => Supabase.instance.client;
  String get _userId => _client.auth.currentUser!.id;

  static const _attachmentsBucket = 'enquiry-attachments';

  /// Compresses and uploads a screenshot to the private attachments bucket,
  /// returning the stored object path (scoped under the user's folder).
  Future<String> uploadScreenshot(String localPath) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      localPath,
      minWidth: 1280,
      minHeight: 1280,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    final data = bytes ?? await File(localPath).readAsBytes();
    final path =
        '$_userId/${DateTime.now().millisecondsSinceEpoch}_${data.length}.jpg';
    await _client.storage.from(_attachmentsBucket).uploadBinary(
          path,
          Uint8List.fromList(data),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    return path;
  }

  Future<List<Enquiry>> fetchEnquiries() async {
    final rows = await _client
        .from('leads')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .inFilter('status', ['new', 'follow'])
        .order('created_at', ascending: false);
    return rows.map<Enquiry>((r) => Enquiry.fromMap(r)).toList();
  }

  Future<Enquiry?> fetchById(String id) async {
    final row = await _client
        .from('leads')
        .select(_selectWithJoins)
        .eq('user_id', _userId)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Enquiry.fromMap(row);
  }

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
    String? screenshotUrl;
    if (screenshotPath != null && screenshotPath.isNotEmpty) {
      try {
        screenshotUrl = await uploadScreenshot(screenshotPath);
      } catch (_) {
        // Best-effort: a storage hiccup must never block saving the enquiry.
        screenshotUrl = null;
      }
    }
    final row = await _client
        .from('leads')
        .insert({
          'user_id': _userId,
          'customer_id': customerId,
          'product_id': ?productId,
          'source': source,
          if (message != null && message.isNotEmpty) 'message': message,
          'intent': ?intent,
          'screenshot_url': ?screenshotUrl,
          'status': followUpDate != null ? 'follow' : 'new',
          if (followUpDate != null)
            'follow_up_date': followUpDate.toIso8601String(),
          'activities': [
            {
              'type': 'created',
              'note': 'Enquiry captured',
              'time': DateTime.now().toIso8601String(),
            },
            if (quoteText != null && quoteText.isNotEmpty)
              {
                'type': 'quote_sent',
                'note': quoteText,
                'time': DateTime.now().toIso8601String(),
              },
          ],
        })
        .select(_selectWithJoins)
        .single();
    return Enquiry.fromMap(row);
  }

  /// Appends a quote_sent activity to an existing enquiry. Read-modify-write
  /// is fine here: rows are per-user and edited from one device, so a lost
  /// update is not a realistic risk and an RPC would be needless surface.
  Future<void> appendQuoteActivity(String enquiryId, String quoteText) async {
    final row = await _client
        .from('leads')
        .select('activities')
        .eq('id', enquiryId)
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return; // lead deleted while the share sheet was open
    final activities = [
      ...(row['activities'] as List? ?? const []),
      {
        'type': 'quote_sent',
        'note': quoteText,
        'time': DateTime.now().toIso8601String(),
      },
    ];
    await updateEnquiry(enquiryId, {'activities': activities});
  }

  Future<void> updateEnquiry(String id, Map<String, dynamic> changes) async {
    await _client
        .from('leads')
        .update(changes)
        .eq('id', id)
        .eq('user_id', _userId);
  }

  /// Atomic: order + items + lead → won + optional unique-piece booking.
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
    final payload = <Map<String, dynamic>>[
      for (var i = 0; i < items.length; i++)
        {
          'name': items[i].name,
          'qty': items[i].qty,
          'unit_price': items[i].price ?? 0,
          if (productIds != null && productIds[i] != null)
            'product_id': productIds[i],
        }
    ];
    final orderId = await _client.rpc('create_order_with_items', params: {
      'p_customer_id': customerId,
      'p_lead_id': leadId,
      'p_items': payload,
      'p_book_product_id': bookProductId,
      'p_notes': notes,
      'p_discount': discount,
      'p_shipping_fee': shippingFee,
      'p_expected_date': expectedDate?.toIso8601String().substring(0, 10),
    });
    return orderId.toString();
  }

  /// Legacy-shaped maps for surviving pre-spec screens (Dashboard, Orders,
  /// notifications). Retired when stages 4 and 7 rebuild those screens.
  Future<List<Map<String, dynamic>>> fetchLegacyMaps() async {
    final leads = await _client
        .from('leads')
        .select('*, customers(name, phone)')
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    final orders = await _client
        .from('orders')
        .select('*, customers(name, phone), order_items(*)')
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return buildLegacyMaps(
      leads: List<Map<String, dynamic>>.from(leads),
      orders: List<Map<String, dynamic>>.from(orders),
    );
  }
}

/// Pure mapping so it can be unit-tested without Supabase.
/// Legacy screens expect: name, msg, status ("closed" = order), items with
/// product_name/quantity/price/total, follow_up_date, intent.
List<Map<String, dynamic>> buildLegacyMaps({
  required List<Map<String, dynamic>> leads,
  required List<Map<String, dynamic>> orders,
}) {
  String customerName(Map<String, dynamic> row) {
    final c = row['customers'];
    return c is Map ? (c['name'] ?? 'Customer').toString() : 'Customer';
  }

  final result = <Map<String, dynamic>>[];

  for (final lead in leads) {
    if (lead['status'] == 'won') continue; // shown via its order row
    result.add({
      ...lead,
      'name': customerName(lead),
      'msg': lead['message'] ?? '',
      'items': const <Map<String, dynamic>>[],
    });
  }

  for (final order in orders) {
    result.add({
      'id': order['id'],
      'order_id': order['id'],
      'name': customerName(order),
      'msg': order['notes'] ?? '',
      'status': 'closed',
      'order_status': order['status'] ?? 'confirmed',
      'intent': 'order',
      'created_at': order['created_at'],
      'follow_up_date': null,
      'activities': const <Map<String, dynamic>>[],
      'items': [
        for (final item in (order['order_items'] as List? ?? const []))
          {
            'product_name': item['name'],
            'quantity': item['qty'],
            'price': item['unit_price'],
            'total': item['line_total'],
          }
      ],
    });
  }

  result.sort((a, b) => (b['created_at'] ?? '')
      .toString()
      .compareTo((a['created_at'] ?? '').toString()));
  return result;
}
