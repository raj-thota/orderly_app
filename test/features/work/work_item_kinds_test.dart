import 'package:flutter_test/flutter_test.dart';
import 'package:orderly_app/features/work/data/work_item_kinds.dart';

void main() {
  test('classifies kinds into groups', () {
    expect(workItemGroup('payment_reminder'), WorkItemGroup.collect);
    expect(workItemGroup('overdue_payment'), WorkItemGroup.collect);
    expect(workItemGroup('reply'), WorkItemGroup.reply);
    expect(workItemGroup('follow_up'), WorkItemGroup.reply);
    expect(workItemGroup('call'), WorkItemGroup.reply);
    expect(workItemGroup('share_catalog'), WorkItemGroup.offer);
    expect(workItemGroup('offer'), WorkItemGroup.offer);
    expect(workItemGroup('something_new'), WorkItemGroup.other);
  });

  test('a kind in one group is not in another', () {
    expect(isCollectKind('reply'), isFalse);
    expect(isReplyKind('overdue_payment'), isFalse);
    expect(isOfferKind('call'), isFalse);
  });
}
