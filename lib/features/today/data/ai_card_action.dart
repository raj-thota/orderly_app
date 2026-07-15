import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// What a Today AI-action-card CTA should do when tapped.
enum AiCardActionType { call, whatsapp, workspace }

class AiCardAction {
  const AiCardAction(this.type, [this.uri]);

  final AiCardActionType type;

  /// Launchable target for [call]/[whatsapp]; null for [workspace].
  final Uri? uri;
}

/// Pure decision: given a work item, what direct action the card CTA performs.
///
/// - call kinds (`follow_up`, `call`) with a phone → `tel:`
/// - message/payment kinds with a phone → WhatsApp (prefilled with the draft)
/// - offer/catalog kinds, or any item without a phone → open the workspace
AiCardAction resolveAiCardAction(AiWorkItem item) {
  final digits = _digits(item.phone);

  switch (item.kind) {
    case 'offer':
    case 'share_catalog':
      return const AiCardAction(AiCardActionType.workspace);
  }

  if (digits.isEmpty) {
    return const AiCardAction(AiCardActionType.workspace);
  }

  switch (item.kind) {
    case 'follow_up':
    case 'call':
      return AiCardAction(AiCardActionType.call, Uri.parse('tel:${item.phone!.trim()}'));
    default:
      return AiCardAction(AiCardActionType.whatsapp, _whatsAppUri(digits, item.draftMessage));
  }
}

Uri _whatsAppUri(String digits, String? draft) {
  final number = digits.length == 10 ? '91$digits' : digits;
  final text = draft?.trim();
  return Uri(
    scheme: 'https',
    host: 'wa.me',
    path: '/$number',
    queryParameters:
        (text != null && text.isNotEmpty) ? {'text': text} : null,
  );
}

String _digits(String? phone) =>
    phone == null ? '' : phone.replaceAll(RegExp(r'[^0-9]'), '');
