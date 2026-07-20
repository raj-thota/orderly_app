import type { NeutralSchema } from "../schema.ts";

export interface CustomerSignal {
  customerId: string;
  customerName: string;
  lastMessage: string | null;
  lastMessageDirection: string | null;
  daysSinceLastMessage: number | null;
  hasUnpaidOrder: boolean;
  followUpOverdueDays: number | null;
  leadIntent: string | null;
  leadMessage: string | null;
}

export interface GenerateInput {
  signals: CustomerSignal[];
  sellerName: string;
}

export const workItemsSchema: NeutralSchema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          customerId: { type: "string" },
          kind: {
            type: "string",
            enum: ["payment_reminder", "reply", "create_order", "invoice", "follow_up", "share_catalog"],
          },
          priority: { type: "string", enum: ["high", "medium", "low"] },
          score: { type: "integer" },
          title: { type: "string" },
          context: { type: "string" },
          draftMessage: { type: "string" },
          confidence: { type: "number" },
        },
        required: ["customerId", "kind", "priority", "score", "title", "context", "draftMessage", "confidence"],
      },
    },
  },
  required: ["items"],
};

export function workItemsPrompt(input: GenerateInput): string {
  const signalLines = input.signals.map((s, i) => {
    const parts = [`${i + 1}. Customer ID: ${s.customerId}`, `   Name: ${s.customerName}`];
    if (s.lastMessage) {
      parts.push(`   Last message (${s.lastMessageDirection}): "${s.lastMessage.slice(0, 120)}"`);
    }
    if (s.daysSinceLastMessage !== null) {
      parts.push(`   Days since last contact: ${s.daysSinceLastMessage}`);
    }
    if (s.hasUnpaidOrder) {
      parts.push("   Has unpaid order: yes (amount will be added by seller — DO NOT include amounts)");
    }
    if (s.followUpOverdueDays !== null) {
      parts.push(`   Follow-up overdue by: ${s.followUpOverdueDays} day(s)`);
    }
    if (s.leadIntent) parts.push(`   Lead intent: ${s.leadIntent}`);
    if (s.leadMessage) parts.push(`   Lead context: "${s.leadMessage.slice(0, 100)}"`);
    return parts.join("\n");
  });

  return [
    `You are an AI sales assistant helping Indian seller "${input.sellerName}" prioritize their work.`,
    "For each customer signal below, decide what action is most important right now.",
    "",
    "CRITICAL RULES:",
    "- NEVER include rupee amounts, UPI IDs, bank account numbers, or phone numbers in ANY field.",
    "- draftMessage must be prose only — seller will add payment details from their records.",
    "- score: 0–100 (higher = more urgent). high priority = score 70+, medium = 40–69, low = below 40.",
    "- title: short action label for the seller (e.g., 'Payment due from Priya', 'Follow up with Rahul').",
    "- context: one-line reason why this action matters now.",
    "- draftMessage: a WhatsApp-ready draft in natural Indian business tone, under 60 words.",
    "- Only return items that genuinely need action. Skip customers who seem fine.",
    "- At most 20 items total.",
    "",
    "Customer signals:",
    ...signalLines,
    "",
    "Return JSON matching the schema.",
  ].join("\n");
}
