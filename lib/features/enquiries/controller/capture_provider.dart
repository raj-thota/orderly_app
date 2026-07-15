import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orderly_app/features/catalog/data/product.dart';
import 'package:orderly_app/features/conversations/controller/conversation_provider.dart' show conversationsServiceProvider;
import 'package:orderly_app/features/conversations/data/conversations_service.dart';
import 'package:orderly_app/features/followups/data/follow_ups_service.dart';
import 'package:orderly_app/features/quotations/data/quotation.dart';

import '../data/ai_parse_service.dart';
import '../data/capture_draft.dart';
import '../data/customers_service.dart';
import '../data/enquiries_service.dart';
import 'enquiries_provider.dart';

final followUpsServiceProvider =
    Provider<FollowUpsService>((ref) => FollowUpsService());

class CaptureState {
  const CaptureState({
    this.draft = const CaptureDraft(),
    this.manualName,
    this.manualPhone,
    this.attachedProductId,
    this.attachedProductName,
    this.attachedProductIsUnique = false,
    this.attachedItem,
    this.screenshotPath,
    this.screenshotBytes,
    this.aiRefining = false,
    this.aiHighlight = const {},
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

  /// Local path + bytes of an attached chat screenshot (null when none).
  final String? screenshotPath;
  final Uint8List? screenshotBytes;

  /// True while an async AI refine is in flight for the current text.
  final bool aiRefining;

  /// Field keys the AI just refined, for a subtle highlight:
  /// 'name', 'phone', 'items', 'followUp', 'intent'.
  final Set<String> aiHighlight;
  final bool saving;

  CaptureState copyWith({
    CaptureDraft? draft,
    String? manualName,
    String? manualPhone,
    String? attachedProductId,
    String? attachedProductName,
    bool? attachedProductIsUnique,
    DraftItem? attachedItem,
    String? screenshotPath,
    Uint8List? screenshotBytes,
    bool? aiRefining,
    Set<String>? aiHighlight,
    bool clearAttachment = false,
    bool clearScreenshot = false,
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
        screenshotPath:
            clearScreenshot ? null : (screenshotPath ?? this.screenshotPath),
        screenshotBytes:
            clearScreenshot ? null : (screenshotBytes ?? this.screenshotBytes),
        aiRefining: aiRefining ?? this.aiRefining,
        aiHighlight: aiHighlight ?? this.aiHighlight,
        saving: saving ?? this.saving,
      );
}

enum SaveKind { enquiry, order }

class SaveResult {
  const SaveResult(this.kind, this.customerName);
  final SaveKind kind;
  final String customerName;
}

final aiParseServiceProvider =
    Provider<AiParseService>((ref) => AiParseService());

final captureControllerProvider =
    StateNotifierProvider.autoDispose<CaptureController, CaptureState>((ref) {
  return CaptureController(
    ref.watch(customersServiceProvider),
    ref.watch(enquiriesServiceProvider),
    ref.watch(aiParseServiceProvider),
    ref.watch(conversationsServiceProvider),
    ref.watch(followUpsServiceProvider),
  );
});

class CaptureController extends StateNotifier<CaptureState> {
  CaptureController(
    this._customers,
    this._enquiries,
    this._ai,
    this._conversations,
    this._followUps,
  ) : super(const CaptureState());

  final CustomersService _customers;
  final EnquiriesService _enquiries;
  final AiParseService _ai;
  final ConversationsService _conversations;
  final FollowUpsService _followUps;

  int _parseToken = 0;

  void setText(String text) {
    _parseToken++;
    final token = _parseToken;
    final parsed = CaptureDraft.fromText(text);
    // Fresh parse is the base; only explicit manual edits and the pinned
    // attached product survive across re-parses.
    final willRefine = text.trim().length >= 8;
    state = state.copyWith(
      draft: parsed.copyWith(
        name: state.manualName ?? parsed.name,
        phone: state.manualPhone ?? parsed.phone,
        items: [?state.attachedItem, ...parsed.items],
      ),
      aiRefining: willRefine,
      aiHighlight: const {},
    );
    if (willRefine) _refine(text, token);
  }

  void attachScreenshot(Uint8List bytes,
      {required String path, String mime = 'image/jpeg'}) {
    _parseToken++;
    final token = _parseToken;
    state = state.copyWith(
      screenshotPath: path,
      screenshotBytes: bytes,
      aiRefining: true,
      aiHighlight: const {},
    );
    _refine(state.draft.raw, token, image: bytes, mime: mime);
  }

  void clearScreenshot() {
    _parseToken++; // discard any in-flight image refine
    state = state.copyWith(clearScreenshot: true, aiRefining: false);
  }

  Future<void> _refine(String text, int token,
      {Uint8List? image, String mime = 'image/jpeg'}) async {
    final ai = await _ai.refine(text, image: image, mime: mime);
    if (!mounted || token != _parseToken) return; // superseded
    if (ai == null) {
      state = state.copyWith(aiRefining: false);
      return;
    }
    final cur = state.draft;
    final highlight = <String>{};

    String? name = cur.name;
    if (state.manualName == null && ai.name != null) {
      if (ai.name != cur.name) highlight.add('name');
      name = ai.name;
    }

    String? phone = cur.phone;
    if (state.manualPhone == null && ai.phone != null) {
      if (ai.phone != cur.phone) highlight.add('phone');
      phone = ai.phone;
    }

    List<DraftItem> items = cur.items;
    if (ai.items != null && ai.items!.isNotEmpty) {
      items = [?state.attachedItem, ...ai.items!];
      highlight.add('items');
    }

    String intent = cur.intent;
    String type = cur.type;
    if (ai.type != null) {
      if (ai.type != cur.type) highlight.add('intent');
      type = ai.type!;
      intent = ai.intent ?? cur.intent;
    }

    DateTime? followUp = cur.followUpDate;
    if (ai.followUpDate != null) {
      if (ai.followUpDate != cur.followUpDate) highlight.add('followUp');
      followUp = ai.followUpDate;
    }

    state = state.copyWith(
      draft: cur.copyWith(
        name: name,
        phone: phone,
        items: items,
        intent: intent,
        type: type,
        followUpDate: followUp,
        budget: ai.budget,
        notes: ai.notes,
        confidence: ai.confidence,
      ),
      aiRefining: false,
      aiHighlight: highlight,
    );
  }

  // Any manual edit takes control from the AI: bumping the token discards an
  // in-flight refine so it cannot clobber the user's change (name/phone are
  // also guarded by manualName/manualPhone; this protects items/date/intent).
  void setName(String name) {
    final v = name.trim();
    if (v.isEmpty) return;
    _parseToken++;
    state = state.copyWith(
        manualName: v, draft: state.draft.copyWith(name: v), aiRefining: false);
  }

  void setPhone(String phone) {
    final v = CaptureDraft.normalizePhone(phone);
    if (v == null) return;
    _parseToken++;
    state = state.copyWith(
        manualPhone: v,
        draft: state.draft.copyWith(phone: v),
        aiRefining: false);
  }

  void editDraft(CaptureDraft draft) {
    _parseToken++;
    state = state.copyWith(draft: draft, aiRefining: false);
  }

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
    _parseToken++;
    final removed = state.draft.items[index];
    final items = [...state.draft.items]..removeAt(index);
    state = state.copyWith(
      draft: state.draft.copyWith(items: items),
      aiRefining: false,
      // Removing the attached product's row also releases the attachment so a
      // save no longer links/books that product.
      clearAttachment: identical(removed, state.attachedItem),
    );
  }

  Future<SaveResult> save({String? quoteText}) async {
    final draft = state.draft;
    state = state.copyWith(saving: true);
    try {
      final customer = await _customers.createOrLink(
        name: draft.name ?? 'Customer',
        phone: draft.phone,
      );

      final msgSource = state.screenshotPath != null
          ? 'screenshot'
          : (state.attachedProductId != null
              ? 'manual'
              : (draft.raw.trim().isEmpty ? 'manual' : 'paste'));

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
        await _writeConversationMessage(
            customerId: customer.id!, source: msgSource, body: draft.raw);
        return SaveResult(SaveKind.order, customer.name);
      }

      final enquiry = await _enquiries.addEnquiry(
        customerId: customer.id!,
        productId: state.attachedProductId,
        source: msgSource,
        message: draft.raw.trim(),
        intent: draft.intent,
        followUpDate: draft.followUpDate,
        screenshotPath: state.screenshotPath,
        quoteText: quoteText,
      );

      await _writeConversationMessage(
          customerId: customer.id!, source: msgSource, body: draft.raw);

      if (draft.followUpDate != null && enquiry.id != null) {
        await _followUps.upsertForLead(
          customerId: customer.id!,
          leadId: enquiry.id!,
          dueAt: draft.followUpDate!,
          kind: draft.intent == 'payment' ? 'payment' : 'reply',
          note: draft.notes,
        );
      }

      return SaveResult(SaveKind.enquiry, customer.name);
    } finally {
      if (mounted) state = state.copyWith(saving: false);
    }
  }

  Future<void> _writeConversationMessage({
    required String customerId,
    required String source,
    required String body,
  }) async {
    final conversation = await _conversations.getOrCreate(customerId);
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _conversations.addMessage(
      conversationId: conversation.id,
      direction: 'inbound',
      source: source,
      body: trimmed,
    );
  }

  Quotation buildQuotation({
    required String businessName,
    required String? upiId,
    required String? upiName,
    required List<Product> products,
  }) {
    final lines = matchCatalog(state.draft.items, products);
    return Quotation.compose(
      businessName: businessName,
      upiId: upiId,
      upiName: upiName,
      customerName: state.draft.name,
      lines: lines,
    );
  }
}
