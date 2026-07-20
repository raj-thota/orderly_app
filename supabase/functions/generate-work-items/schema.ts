export type WorkItemKind =
  | "payment_reminder"
  | "reply"
  | "create_order"
  | "invoice"
  | "follow_up"
  | "share_catalog";

export type WorkItemPriority = "high" | "medium" | "low";

export interface WorkItemOutput {
  customerId: string;
  kind: WorkItemKind;
  priority: WorkItemPriority;
  score: number;
  title: string;
  context: string;
  draftMessage: string;
  confidence: number;
}

export interface GenerateOutput {
  items: WorkItemOutput[];
}
