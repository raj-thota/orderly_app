import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/orders/data/create_order_draft.dart';
import 'package:orderly_app/features/orders/data/orders_service.dart';

import 'orders_provider.dart';

class CreateOrderState {
  const CreateOrderState({
    required this.draft,
    this.submitting = false,
    this.error,
  });

  final CreateOrderDraft draft;
  final bool submitting;
  final String? error;

  CreateOrderState copyWith({
    CreateOrderDraft? draft,
    bool? submitting,
    String? error,
  }) =>
      CreateOrderState(
        draft: draft ?? this.draft,
        submitting: submitting ?? this.submitting,
        error: error,
      );
}

class CreateOrderNotifier extends StateNotifier<CreateOrderState> {
  CreateOrderNotifier(this._service, String customerId, String customerName)
      : super(CreateOrderState(
          draft: CreateOrderDraft(
            customerId: customerId,
            customerName: customerName,
          ),
        ));

  final OrdersService _service;

  void addItem(CreateOrderItem item) {
    final items = List<CreateOrderItem>.of(state.draft.items);
    if (item.productId != null) {
      final i = items.indexWhere((e) => e.productId == item.productId);
      if (i != -1) {
        items[i] = items[i].copyWith(qty: items[i].qty + item.qty);
        state = state.copyWith(draft: state.draft.copyWith(items: items));
        return;
      }
    }
    items.add(item);
    state = state.copyWith(draft: state.draft.copyWith(items: items));
  }

  void setQty(int index, int qty) {
    final items = List<CreateOrderItem>.of(state.draft.items);
    if (index < 0 || index >= items.length) return;
    if (qty <= 0) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(qty: qty);
    }
    state = state.copyWith(draft: state.draft.copyWith(items: items));
  }

  void removeItem(int index) {
    final items = List<CreateOrderItem>.of(state.draft.items)..removeAt(index);
    state = state.copyWith(draft: state.draft.copyWith(items: items));
  }

  void updateItem(int index, CreateOrderItem item) {
    final items = List<CreateOrderItem>.of(state.draft.items);
    items[index] = item;
    state = state.copyWith(draft: state.draft.copyWith(items: items));
  }

  void setDiscount(double v) =>
      state = state.copyWith(draft: state.draft.copyWith(discount: v));

  void setShippingFee(double v) =>
      state = state.copyWith(draft: state.draft.copyWith(shippingFee: v));

  void setExpectedDate(DateTime? d) =>
      state = state.copyWith(draft: state.draft.copyWith(expectedDate: d));

  void setNotes(String? n) =>
      state = state.copyWith(draft: state.draft.copyWith(notes: n));

  Future<String?> submit() async {
    if (!state.draft.canSubmit) return null;
    state = state.copyWith(submitting: true);
    try {
      final id = await _service.createOrder(
        customerId: state.draft.customerId,
        items: state.draft.items,
        discount: state.draft.discount,
        shippingFee: state.draft.shippingFee,
        expectedDate: state.draft.expectedDate,
        notes: state.draft.notes,
      );
      if (mounted) state = state.copyWith(submitting: false);
      return id;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(submitting: false, error: e.toString());
      }
      return null;
    }
  }
}

final createOrderProvider = StateNotifierProvider.family
    .autoDispose<CreateOrderNotifier, CreateOrderState, (String, String)>(
  (ref, args) => CreateOrderNotifier(
    ref.watch(ordersServiceProvider),
    args.$1,
    args.$2,
  ),
);
