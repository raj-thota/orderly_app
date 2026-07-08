import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/capture_draft.dart';
import '../data/customers_service.dart';
import '../data/enquiries_service.dart';
import 'enquiries_provider.dart';

class CaptureState {
  const CaptureState({
    this.draft = const CaptureDraft(),
    this.manualName,
    this.manualPhone,
    this.attachedProductId,
    this.attachedProductName,
    this.attachedProductIsUnique = false,
    this.attachedItem,
    this.saving = false,
  });

  final CaptureDraft draft;

  /// Values the user typed by hand; they win over every re-parse.
  final String? manualName;
  final String? manualPhone;
  final String? attachedProductId;
  final String? attachedProductName;
  final bool attachedProductIsUnique;

  /// Line item pinned by attachProduct; survives re-parses of the text.
  final DraftItem? attachedItem;
  final bool saving;

  CaptureState copyWith({
    CaptureDraft? draft,
    String? manualName,
    String? manualPhone,
    String? attachedProductId,
    String? attachedProductName,
    bool? attachedProductIsUnique,
    DraftItem? attachedItem,
    bool clearAttachment = false,
    bool? saving,
  }) =>
      CaptureState(
        draft: draft ?? this.draft,
        manualName: manualName ?? this.manualName,
        manualPhone: manualPhone ?? this.manualPhone,
        attachedProductId:
            clearAttachment ? null : (attachedProductId ?? this.attachedProductId),
        attachedProductName:
            clearAttachment ? null : (attachedProductName ?? this.attachedProductName),
        attachedProductIsUnique: clearAttachment
            ? false
            : (attachedProductIsUnique ?? this.attachedProductIsUnique),
        attachedItem: clearAttachment ? null : (attachedItem ?? this.attachedItem),
        saving: saving ?? this.saving,
      );
}

enum SaveKind { enquiry, order }

class SaveResult {
  const SaveResult(this.kind, this.customerName);
  final SaveKind kind;
  final String customerName;
}

final captureControllerProvider =
    StateNotifierProvider.autoDispose<CaptureController, CaptureState>((ref) {
  return CaptureController(
    ref.watch(customersServiceProvider),
    ref.watch(enquiriesServiceProvider),
  );
});

class CaptureController extends StateNotifier<CaptureState> {
  CaptureController(this._customers, this._enquiries)
      : super(const CaptureState());

  final CustomersService _customers;
  final EnquiriesService _enquiries;

  void setText(String text) {
    final parsed = CaptureDraft.fromText(text);
    // Fresh parse is the base; only explicit manual edits and the pinned
    // attached product survive across re-parses.
    state = state.copyWith(
      draft: parsed.copyWith(
        name: state.manualName ?? parsed.name,
        phone: state.manualPhone ?? parsed.phone,
        items: [?state.attachedItem, ...parsed.items],
      ),
    );
  }

  void setName(String name) {
    final v = name.trim();
    if (v.isEmpty) return;
    state = state.copyWith(manualName: v, draft: state.draft.copyWith(name: v));
  }

  void setPhone(String phone) {
    final v = CaptureDraft.normalizePhone(phone);
    if (v == null) return;
    state = state.copyWith(manualPhone: v, draft: state.draft.copyWith(phone: v));
  }

  void editDraft(CaptureDraft draft) => state = state.copyWith(draft: draft);

  void attachProduct({
    required String id,
    required String name,
    required bool isUnique,
    required double price,
  }) {
    final item = DraftItem(name: name, qty: 1, price: price);
    state = state.copyWith(
      attachedProductId: id,
      attachedProductName: name,
      attachedProductIsUnique: isUnique,
      attachedItem: item,
      draft: state.draft.copyWith(items: [item, ...state.draft.items]),
    );
  }

  void removeItem(int index) {
    final removed = state.draft.items[index];
    final items = [...state.draft.items]..removeAt(index);
    state = state.copyWith(
      draft: state.draft.copyWith(items: items),
      // Removing the attached product's row also releases the attachment so a
      // save no longer links/books that product.
      clearAttachment: identical(removed, state.attachedItem),
    );
  }

  Future<SaveResult> save() async {
    final draft = state.draft;
    state = state.copyWith(saving: true);
    try {
      final customer = await _customers.createOrLink(
        name: draft.name ?? 'Customer',
        phone: draft.phone,
      );

      final source = state.attachedProductId != null
          ? 'product'
          : (draft.raw.trim().isEmpty ? 'manual' : 'paste');

      if (draft.type == 'order' && draft.items.isNotEmpty) {
        await _enquiries.createOrder(
          customerId: customer.id!,
          items: draft.items,
          bookProductId:
              state.attachedProductIsUnique ? state.attachedProductId : null,
          productIds: [
            for (var i = 0; i < draft.items.length; i++)
              i == 0 ? state.attachedProductId : null,
          ],
          notes: draft.raw.trim().isEmpty ? null : draft.raw.trim(),
        );
        return SaveResult(SaveKind.order, customer.name);
      }

      await _enquiries.addEnquiry(
        customerId: customer.id!,
        productId: state.attachedProductId,
        source: source,
        message: draft.raw.trim(),
        intent: draft.intent,
        followUpDate: draft.followUpDate,
      );
      return SaveResult(SaveKind.enquiry, customer.name);
    } finally {
      if (mounted) state = state.copyWith(saving: false);
    }
  }
}
