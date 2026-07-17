import 'package:orderly_app/core/utils/money.dart';
import 'package:orderly_app/features/today/data/today_brief.dart';
import 'package:orderly_app/features/work/data/ai_work_item.dart';

/// Time-of-day flavor for the hero brief.
enum BriefDaypart { morning, afternoon, evening }

BriefDaypart briefDaypart(DateTime now) {
  if (now.hour < 12) return BriefDaypart.morning;
  if (now.hour < 17) return BriefDaypart.afternoon;
  return BriefDaypart.evening;
}

/// The AI copilot's spoken summary for the hero card. Pure so it can be
/// unit-tested without widgets or Supabase.
class BriefNarrative {
  const BriefNarrative({
    required this.eyebrow,
    required this.body,
    this.bullets = const [],
  });

  /// Small-caps label above the narrative, e.g. "YOUR MORNING BRIEF".
  final String eyebrow;

  /// The narrative paragraph the assistant "says".
  final String body;

  /// Scannable action lines ("Collect ₹3,360 from 1 customer"). When
  /// non-empty the UI renders these instead of [body].
  final List<String> bullets;
}

bool _isCollectKind(String kind) =>
    kind == 'payment_reminder' || kind == 'overdue_payment';

bool _isReplyKind(String kind) =>
    kind == 'follow_up' || kind == 'call' || kind == 'reply';

bool _isOfferKind(String kind) => kind == 'share_catalog' || kind == 'offer';

BriefNarrative buildBriefNarrative({
  required TodayBrief brief,
  required List<AiWorkItem> items,
  required DateTime now,
}) {
  final daypart = briefDaypart(now);
  final eyebrow = switch (daypart) {
    BriefDaypart.morning => 'YOUR MORNING BRIEF',
    BriefDaypart.afternoon => 'YOUR AFTERNOON BRIEF',
    BriefDaypart.evening => 'YOUR EVENING BRIEF',
  };

  final pending = items.length;

  if (pending == 0) {
    if (daypart == BriefDaypart.evening && brief.revenueToday > 0) {
      final orders = brief.ordersToday > 0
          ? ' across ${brief.ordersToday} order${brief.ordersToday == 1 ? '' : 's'}'
          : '';
      return BriefNarrative(
        eyebrow: eyebrow,
        body:
            'You collected ${Money.inr(brief.revenueToday)}$orders today. Nothing else needs you — enjoy your evening.',
      );
    }
    return BriefNarrative(
      eyebrow: eyebrow,
      body:
          'All clear — nothing needs you right now. A good time to add products or check in on quiet customers.',
    );
  }

  // Break pending work into what the owner actually has to do.
  var collectCount = 0;
  var collectAmount = 0.0;
  var replyCount = 0;
  var offerCount = 0;
  for (final item in items) {
    if (_isCollectKind(item.kind)) {
      collectCount++;
      collectAmount += item.amount ?? 0;
    } else if (_isReplyKind(item.kind)) {
      replyCount++;
    } else if (_isOfferKind(item.kind)) {
      offerCount++;
    }
  }
  collectAmount = (collectAmount * 100).round() / 100;

  final parts = <String>[];
  if (collectCount > 0) {
    final amount =
        collectAmount > 0 ? '${Money.inr(collectAmount)} to collect' : 'payments to collect';
    parts.add(
        '$amount from $collectCount customer${collectCount == 1 ? '' : 's'}');
  }
  if (replyCount > 0) {
    parts.add(
        '$replyCount customer${replyCount == 1 ? ' is' : 's are'} waiting on a reply');
  }
  if (offerCount > 0) {
    parts.add(
        '$offerCount customer${offerCount == 1 ? '' : 's'} to win back with an offer');
  }

  final lead = daypart == BriefDaypart.evening
      ? '$pending task${pending == 1 ? '' : 's'} still open.'
      : '$pending thing${pending == 1 ? '' : 's'} need${pending == 1 ? 's' : ''} you today.';

  final detail = switch (parts.length) {
    0 => '',
    1 => ' ${_capitalize(parts[0])}.',
    _ => ' ${_capitalize(parts.sublist(0, parts.length - 1).join(', '))}, and ${parts.last}.',
  };

  final prefix = daypart == BriefDaypart.evening && brief.revenueToday > 0
      ? 'You collected ${Money.inr(brief.revenueToday)} today. '
      : '';

  final bullets = <String>[];
  if (collectCount > 0) {
    final target = '$collectCount customer${collectCount == 1 ? '' : 's'}';
    bullets.add(collectAmount > 0
        ? 'Collect ${Money.inr(collectAmount)} from $target'
        : 'Collect payments from $target');
  }
  if (replyCount > 0) {
    bullets.add(
        'Reply to $replyCount waiting customer${replyCount == 1 ? '' : 's'}');
  }
  if (offerCount > 0) {
    bullets.add(
        'Win back $offerCount inactive customer${offerCount == 1 ? '' : 's'}');
  }
  final otherCount = pending - collectCount - replyCount - offerCount;
  if (otherCount > 0) {
    bullets.add('Handle $otherCount other task${otherCount == 1 ? '' : 's'}');
  }

  return BriefNarrative(
      eyebrow: eyebrow, body: '$prefix$lead$detail', bullets: bullets);
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Rough effort per task, so the brief can promise a session length.
/// Heuristic by kind: reminders are one WhatsApp tap, replies take a moment.
int estimatedMinutesFor(AiWorkItem item) {
  if (_isCollectKind(item.kind)) return 2;
  if (_isReplyKind(item.kind)) return 3;
  if (_isOfferKind(item.kind)) return 3;
  return 2;
}

int estimatedMinutes(List<AiWorkItem> items) =>
    items.fold(0, (sum, item) => sum + estimatedMinutesFor(item));

/// One-line task label ("Collect ₹3,360 from Priya") for the work list.
String focusLabel(AiWorkItem item) {
  final name = item.customerName ?? 'a customer';
  if (_isCollectKind(item.kind)) {
    return item.amount != null
        ? 'Collect ${Money.inr(item.amount!)} from $name'
        : 'Collect payment from $name';
  }
  switch (item.kind) {
    case 'follow_up':
    case 'call':
      return 'Follow up with $name';
    case 'share_catalog':
    case 'offer':
      return 'Send $name an offer';
    default:
      return 'Reply to $name';
  }
}
