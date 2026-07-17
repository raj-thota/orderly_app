/// Coarse grouping of AI work-item kinds, shared by the Home brief and Focus Mode.
enum WorkItemGroup { collect, reply, offer, other }

bool isCollectKind(String kind) =>
    kind == 'payment_reminder' || kind == 'overdue_payment';

bool isReplyKind(String kind) =>
    kind == 'follow_up' || kind == 'call' || kind == 'reply';

bool isOfferKind(String kind) => kind == 'share_catalog' || kind == 'offer';

WorkItemGroup workItemGroup(String kind) {
  if (isCollectKind(kind)) return WorkItemGroup.collect;
  if (isReplyKind(kind)) return WorkItemGroup.reply;
  if (isOfferKind(kind)) return WorkItemGroup.offer;
  return WorkItemGroup.other;
}
