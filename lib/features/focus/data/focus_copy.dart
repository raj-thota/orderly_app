import 'package:orderly_app/features/work/data/work_item_kinds.dart';

/// Deterministic, one-line assistant copy. No free-form generation — every
/// string is derived from position/kind so it is testable and never chatty.

String focusEntryLine(int taskCount) =>
    "Let's clear your $taskCount tasks together.";

String focusTaskLead(String kind, String firstName) {
  switch (workItemGroup(kind)) {
    case WorkItemGroup.collect:
      return "Let's start with this payment.";
    case WorkItemGroup.reply:
      return "$firstName's waiting — let's reply.";
    case WorkItemGroup.offer:
      return "Let's win $firstName back.";
    case WorkItemGroup.other:
      return "Let's handle this next.";
  }
}

String focusSuccessLine(int remaining) => remaining == 1
    ? 'Nice work! Just 1 more to go.'
    : 'Nice work! $remaining more to go.';

String focusFinishLine(String firstName) => 'Great momentum today, $firstName.';
