import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/focus/data/focus_action.dart';

void main() {
  test('maps kind groups to a primary action', () {
    expect(resolveFocusAction('overdue_payment'), FocusActionKind.sendReminder);
    expect(resolveFocusAction('payment_reminder'), FocusActionKind.sendReminder);
    expect(resolveFocusAction('reply'), FocusActionKind.sendReply);
    expect(resolveFocusAction('follow_up'), FocusActionKind.sendReply);
    expect(resolveFocusAction('offer'), FocusActionKind.sendOffer);
    expect(resolveFocusAction('mystery'), FocusActionKind.openWorkspace);
  });
}
