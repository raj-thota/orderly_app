import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';
import 'package:orderly_app/features/orders/data/order.dart';

import '../data/invoice_service.dart';

final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return InvoiceService();
});

final invoiceControllerProvider =
    StateNotifierProvider<InvoiceController, AsyncValue<void>>((ref) {
  return InvoiceController(ref.watch(invoiceServiceProvider), ref);
});

class InvoiceController extends StateNotifier<AsyncValue<void>> {
  InvoiceController(this._service, this._ref)
      : super(const AsyncValue.data(null));

  final InvoiceService _service;
  final Ref _ref;

  /// Assigns (idempotently) and returns the order's invoice number, then
  /// reloads orders so the order carries it. Returns null on failure.
  Future<String?> prepare(Order order) async {
    state = const AsyncValue.loading();
    final res =
        await AsyncValue.guard(() => _service.assignInvoiceNumber(order.id!));
    if (res.hasError) {
      state = AsyncValue.error(res.error!, res.stackTrace!);
      return null;
    }
    state = const AsyncValue.data(null);
    await _ref.read(ordersControllerProvider.notifier).load();
    return res.value;
  }
}
