import 'package:orderly_app/features/work/data/work_item_kinds.dart';

/// The primary action a Focus task offers. Presentation maps each to a label,
/// icon, colour and handler; the mapping *by kind* lives here so it is testable.
enum FocusActionKind { sendReminder, sendReply, sendOffer, openWorkspace }

FocusActionKind resolveFocusAction(String kind) {
  switch (workItemGroup(kind)) {
    case WorkItemGroup.collect:
      return FocusActionKind.sendReminder;
    case WorkItemGroup.reply:
      return FocusActionKind.sendReply;
    case WorkItemGroup.offer:
      return FocusActionKind.sendOffer;
    case WorkItemGroup.other:
      return FocusActionKind.openWorkspace;
  }
}
