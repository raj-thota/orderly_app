import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/capture_draft.dart';
import '../data/customers_service.dart';
import '../data/enquiries_service.dart';
import 'enquiries_provider.dart';

class CaptureState {
  const CaptureState({
    this.draft = const CaptureDraft(),
    this.attachedProductId,
    this.attachedProductName,
    this.attachedProductIsUnique = false,
    this.saving = false,
  });

  final CaptureDraft draft;
  final String? attachedProductId;
  final String? attachedProductName;
  final bool attachedProductIsUnique;
  final bool saving;

  CaptureState copyWith({
    CaptureDraft? draft,
    String? attachedProductId,
    String? attachedProductName,
    bool? attachedProductIsUnique,
    bool? saving,
  }) =>
      CaptureState(
        draft: draft ?? this.draft,
        attachedProductId: attachedProductId ?? this.attachedProductId,
        attachedProductName: attachedProductName ?? this.attachedProductName,
        attachedProductIsUnique:
            attachedProductIsUnique ?? this.attachedProductIsUnique,
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
    // Manual edits to name/phone survive re-parses of the message text.
    // Previously attached/edited items are preserved when the re-parsed text
    // yields no item patterns (e.g. "confirm order for 9876543210" has no
    // qty+item pairs, so we keep whatever was attached via attachProduct).
    state = state.copyWith(
      draft: parsed.copyWith(
        name: state.draft.name ?? parsed.name,
        phone: state.draft.phone ?? parsed.phone,
        items: parsed.items.isEmpty ? state.draft.items : parsed.items,
      ),
    );
  }

  void editDraft(CaptureDraft draft) => state = state.copyWith(draft: draft);

  void attachProduct({
    required String id,
    required String name,
    required bool isUnique,
    required double price,
  }) {
    state = state.copyWith(
      attachedProductId: id,
      attachedProductName: name,
      attachedProductIsUnique: isUnique,
      draft: state.draft.copyWith(items: [
        DraftItem(name: name, qty: 1, price: price),
        ...state.draft.items,
      ]),
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
