import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/orders/controller/orders_provider.dart';

import '../data/payments_service.dart';

final paymentsServiceProvider = Provider<PaymentsService>((ref) {
  ref.watch(authUserIdProvider.select((v) => v.valueOrNull));
  return PaymentsService();
});

final paymentsControllerProvider =
    StateNotifierProvider<PaymentsController, AsyncValue<void>>((ref) {
  return PaymentsController(ref.watch(paymentsServiceProvider), ref);
});

class PaymentsController extends StateNotifier<AsyncValue<void>> {
  PaymentsController(this._service, this._ref)
      : super(const AsyncValue.data(null));

  final PaymentsService _service;
  final Ref _ref;

  /// Records a payment and reloads orders. Returns true on success.
  Future<bool> recordPayment(
    String orderId,
    double amount,
    String method,
  ) async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(
        () => _service.recordPayment(orderId, amount, method));
    state = result.hasError ? result : const AsyncValue.data(null);
    if (result.hasError) return false;
    await _ref.read(ordersControllerProvider.notifier).load();
    return true;
  }
}
